@echo off
setlocal EnableDelayedExpansion

:: ===========================================================================
:: Comprehensive Diagnostic and Troubleshooting Script for Windows 10 / 11
:: Author: Wojciech Wozniak - king of infrastructure - https://www.linkedin.com/in/wojciech-wo%C5%BAniak-8261a214a/
::
:: Features:
::   - Aborts with a clear message if not run elevated
::   - Checks %errorlevel% after every step and prints a pass/fail summary
::   - Tees ALL console output (not just our own echo lines) to a timestamped
::     log file, so nothing is lost after the window closes
::   - Creates a System Restore point before any disk/boot-altering step
::   - Timestamps every report file instead of overwriting the previous run
::   - Choice-driven menu: slow or risky steps are opt-in, not automatic
::   - Prompts for a reboot at the end if a change needs one to apply
:: ===========================================================================

set "SCRIPT_DIR=%~dp0"

:: ---------------------------------------------------------------------------
:: 0a. Elevation check - abort immediately and clearly if not Administrator
:: ---------------------------------------------------------------------------
net session >nul 2>&1
if not "!errorlevel!"=="0" (
    echo =======================================
    echo   ERROR: Administrator privileges required
    echo =======================================
    echo This script must be run as Administrator, otherwise most steps below
    echo will silently fail. Right-click the script and choose
    echo "Run as administrator", then try again.
    echo.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------------------
:: 0b. Re-launch under a logging wrapper so every line of output - ours and
::     every external command's - is teed to a timestamped log file.
:: ---------------------------------------------------------------------------
if /I "%~1"=="__LOGGED__" (
    set "TIMESTAMP=%~2"
    goto :AfterRelaunch
)

for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TIMESTAMP=%%T"
if not exist "%SCRIPT_DIR%Logs" mkdir "%SCRIPT_DIR%Logs"
set "LOGFILE=%SCRIPT_DIR%Logs\diagnostics_%TIMESTAMP%.log"
set "EXITCODE_FILE=%TEMP%\diagnostic_tools_exitcode_%TIMESTAMP%.tmp"

echo Logging full output to "%LOGFILE%"
"%~f0" __LOGGED__ %TIMESTAMP% 2>&1 | powershell -NoProfile -Command "$input | Tee-Object -FilePath '%LOGFILE%'"

set "FINAL_FAILS=0"
if exist "%EXITCODE_FILE%" (
    set /p FINAL_FAILS=<"%EXITCODE_FILE%"
    del "%EXITCODE_FILE%" >nul 2>&1
)
exit /b !FINAL_FAILS!

:AfterRelaunch
set "LOGFILE=%SCRIPT_DIR%Logs\diagnostics_%TIMESTAMP%.log"
set "EXITCODE_FILE=%TEMP%\diagnostic_tools_exitcode_%TIMESTAMP%.tmp"
set "REPORT_DIR=%userprofile%\Desktop\DiagnosticReports"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"

set "STEP_COUNT=0"
set "FAIL_COUNT=0"
set "NEED_REBOOT=0"
set "REBOOT_TO_WINRE=0"
set "RESTORE_POINT_DONE=0"

echo =======================================
echo      Windows 10/11 Diagnostics Script
echo      Run started: %TIMESTAMP%
echo =======================================
echo.

:: ---------------------------------------------------------------------------
:: 1. Choice-driven menu - slow / risky steps are opt-in
:: ---------------------------------------------------------------------------
echo Choose a run mode:
echo   [1] Guided    - ask before each slow or system-modifying step - recommended
echo   [2] Quick     - safe, read-only checks only, skip everything slow or risky
echo   [3] Full      - run every step without prompting, not recommended unattended
echo.
choice /c 123 /m "Select mode 1, 2 or 3"
if !errorlevel! EQU 3 (set "MODE=FULL") else if !errorlevel! EQU 2 (set "MODE=QUICK") else (set "MODE=GUIDED")
echo Running in !MODE! mode.
echo.

call :ShouldRun "System File Checker - sfc /scannow - slow, can take 10-20 minutes" RUN_SFC
call :ShouldRun "DISM full scan and restore health - slow, needs internet access" RUN_DISM_FULL
call :ShouldRun "Full disk repair scheduling if chkdsk finds problems" RUN_CHKDSK_REPAIR
call :ShouldRun "Network reset - winsock reset, IP reset, release/renew - drops connectivity briefly" RUN_NET_RESET
call :ShouldRun "Clean temporary files in %%TEMP%%" RUN_TEMP_CLEAN
call :ShouldRun "Optimize/defragment drive C: - slow" RUN_DEFRAG
echo.

set "RESTORE_NEEDED=0"
if "!RUN_SFC!"=="1" set "RESTORE_NEEDED=1"
if "!RUN_DISM_FULL!"=="1" set "RESTORE_NEEDED=1"
if "!RUN_CHKDSK_REPAIR!"=="1" set "RESTORE_NEEDED=1"
if "!RUN_DEFRAG!"=="1" set "RESTORE_NEEDED=1"

:: ---------------------------------------------------------------------------
:: 2. System Restore point before any disk/boot-altering step
:: ---------------------------------------------------------------------------
if "!RESTORE_NEEDED!"=="1" (
    echo Creating a System Restore point before making changes...
    powershell -NoProfile -Command "Checkpoint-Computer -Description 'Pre-Diagnostics %TIMESTAMP%' -RestorePointType 'MODIFY_SETTINGS'"
    if !errorlevel! EQU 0 (
        echo Restore point created successfully.
        set "RESTORE_POINT_DONE=1"
    ) else (
        echo WARNING: Could not create a restore point - System Protection may be
        echo disabled, or Windows only allows one restore point per 24 hours.
        echo Continuing anyway, but you will not be able to roll back automatically.
    )
    call :Result "System Restore Point Creation"
    echo.
)

:: ---------------------------------------------------------------------------
:: 3. System File Check - sfc
:: ---------------------------------------------------------------------------
if "!RUN_SFC!"=="1" (
    echo Running System File Checker...
    sfc /scannow
    call :Result "SFC /scannow"
) else (
    echo Skipped: System File Checker.
)
echo.

:: ---------------------------------------------------------------------------
:: 4. DISM - always run the fast health check, gate the slow repair steps
:: ---------------------------------------------------------------------------
echo Checking system health with DISM - quick check...
DISM /Online /Cleanup-Image /CheckHealth
call :Result "DISM CheckHealth"
if "!RUN_DISM_FULL!"=="1" (
    echo Running DISM full scan and restore health...
    DISM /Online /Cleanup-Image /ScanHealth
    call :Result "DISM ScanHealth"
    DISM /Online /Cleanup-Image /RestoreHealth
    call :Result "DISM RestoreHealth"
) else (
    echo Skipped: DISM ScanHealth / RestoreHealth.
)
echo.

:: ---------------------------------------------------------------------------
:: 5. Clean DNS Resolver Cache
:: ---------------------------------------------------------------------------
echo Flushing DNS resolver cache...
ipconfig /flushdns
call :Result "DNS Flush"
echo.

:: ---------------------------------------------------------------------------
:: 6. Check Disk for Errors
::    C: is the boot volume so it cannot be locked for an offline chkdsk /f /r
::    without a Y/N prompt this script can't answer. Use the online /scan
::    pass instead, which does not require a dismount, and only schedule the
::    offline repair - auto-confirming the reboot prompt - if it is actually
::    needed and the user opts in.
:: ---------------------------------------------------------------------------
echo Running online disk scan on %SystemDrive% - no dismount or reboot required...
chkdsk %SystemDrive% /scan
call :Result "Disk Scan - chkdsk /scan"

for /f "delims=" %%A in ('fsutil dirty query %SystemDrive%') do set "DIRTY_OUTPUT=%%A"
echo !DIRTY_OUTPUT!
echo !DIRTY_OUTPUT! | find /I "is Dirty" >nul
if !errorlevel! EQU 0 (
    echo %SystemDrive% is marked dirty - a full offline repair requires a restart.
    if "!RUN_CHKDSK_REPAIR!"=="1" (
        echo Scheduling chkdsk /f /r on %SystemDrive% for the next restart...
        echo Y| chkdsk %SystemDrive% /f /r >nul
        call :Result "Disk Repair Scheduling - chkdsk /f /r"
        set "NEED_REBOOT=1"
    ) else (
        echo Skipped: scheduling full disk repair. Re-run with mode 1 or 3, or
        echo manually run "chkdsk %SystemDrive% /f /r" and accept the restart prompt.
    )
) else (
    echo No disk repair required.
)
echo.

:: ---------------------------------------------------------------------------
:: 7. Check Driver Status
:: ---------------------------------------------------------------------------
echo Listing installed drivers and their status...
driverquery
call :Result "Driver Query"
echo.

:: ---------------------------------------------------------------------------
:: 8. Update Group Policy
:: ---------------------------------------------------------------------------
echo Forcing group policy updates...
gpupdate /force
call :Result "GPUpdate /force"
echo.

:: ---------------------------------------------------------------------------
:: 9. Network Diagnostics
:: ---------------------------------------------------------------------------
echo Displaying network adapter information...
ipconfig /all
call :Result "Network Info - ipconfig /all"

echo Testing internet connectivity...
ping 8.8.8.8 -n 5
call :Result "Ping Test"

if "!RUN_NET_RESET!"=="1" (
    echo Resetting network settings...
    netsh winsock reset
    call :Result "Winsock Reset"
    netsh int ip reset
    call :Result "IP Stack Reset"
    echo Releasing and renewing IP configuration...
    ipconfig /release
    call :Result "IP Release"
    ipconfig /renew
    call :Result "IP Renew"
    ipconfig /registerdns
    call :Result "Register DNS"
    set "NEED_REBOOT=1"
) else (
    echo Skipped: network reset - winsock/IP stack reset and release/renew.
)
echo.

:: ---------------------------------------------------------------------------
:: 10. Driver Diagnostics
:: ---------------------------------------------------------------------------
echo Detecting problematic drivers...
pnputil /enum-devices /problem
call :Result "Problem Device Enumeration"
echo Reinstalling problematic drivers - manually specify oemXX.inf if required.
:: Uncomment and replace oemXX.inf with the appropriate file name if needed.
:: pnputil /delete-driver oemXX.inf /uninstall
echo.

:: ---------------------------------------------------------------------------
:: 11. Optimize Windows Performance
:: ---------------------------------------------------------------------------
if "!RUN_TEMP_CLEAN!"=="1" (
    echo Cleaning temporary files...
    del /s /q /f "%temp%\*" 2>nul
    call :Result "Temp File Cleanup"
) else (
    echo Skipped: temporary file cleanup.
)

if "!RUN_DEFRAG!"=="1" (
    echo Optimizing drive %SystemDrive%...
    defrag %SystemDrive% /O
    call :Result "Defrag %SystemDrive%"
) else (
    echo Skipped: drive optimization/defrag.
)
echo.

:: ---------------------------------------------------------------------------
:: 12. Hardware Diagnostics - timestamped reports, never overwritten
:: ---------------------------------------------------------------------------
echo Checking battery report if applicable...
powercfg /batteryreport /output "%REPORT_DIR%\battery-report_%TIMESTAMP%.html"
call :Result "Battery Report"

echo Generating energy report...
powercfg /energy /output "%REPORT_DIR%\energy-report_%TIMESTAMP%.html"
call :Result "Energy Report"
echo.

:: ---------------------------------------------------------------------------
:: 13. System Event Logs - timestamped, never overwritten
:: ---------------------------------------------------------------------------
echo Exporting system event logs for diagnostics...
wevtutil epl System "%REPORT_DIR%\SystemLogs_%TIMESTAMP%.evtx"
call :Result "System Event Log Export"
wevtutil epl Application "%REPORT_DIR%\ApplicationLogs_%TIMESTAMP%.evtx"
call :Result "Application Event Log Export"
echo Event logs and reports saved to "%REPORT_DIR%".
echo.

:: ---------------------------------------------------------------------------
:: 14. Boot Issues Diagnostics
::     bootrec only functions from the Windows Recovery Environment. From a
::     normal elevated prompt on Windows 10 or 11 these commands fail every
::     time, so detect WinRE and skip with instructions otherwise instead of
::     silently failing four times.
:: ---------------------------------------------------------------------------
if /I "%SystemDrive%"=="X:" (
    echo Windows Recovery Environment detected - running boot repair commands...
    bootrec /fixmbr
    call :Result "bootrec /fixmbr"
    bootrec /fixboot
    call :Result "bootrec /fixboot"
    bootrec /scanos
    call :Result "bootrec /scanos"
    bootrec /rebuildbcd
    call :Result "bootrec /rebuildbcd"
) else (
    echo Boot repair - bootrec - only works from the Windows Recovery
    echo Environment, not from a normal elevated Command Prompt, so this step
    echo cannot run here on either Windows 10 or 11. To repair boot issues:
    echo   1. Restart and hold Shift while selecting Restart, or run:
    echo        shutdown /r /o /t 0
    echo   2. Choose Troubleshoot, then Advanced options, then Command Prompt
    echo   3. Run: bootrec /fixmbr, bootrec /fixboot, bootrec /scanos,
    echo        bootrec /rebuildbcd
    set "RESULT_SKIP_BOOTREC=SKIPPED: bootrec requires WinRE, not available from normal Windows"
    echo.
    choice /c YN /m "Reboot into Advanced Startup - WinRE - now to run boot repair"
    if !errorlevel! EQU 1 (
        set "NEED_REBOOT=1"
        set "REBOOT_TO_WINRE=1"
    )
)
echo.

:: ---------------------------------------------------------------------------
:: 15. Pass/fail summary
:: ---------------------------------------------------------------------------
echo =======================================
echo   Diagnostics Summary
echo =======================================
for /l %%i in (1,1,!STEP_COUNT!) do (
    call set "LINE=%%R%%i%%"
    echo !LINE!
)
if defined RESULT_SKIP_BOOTREC echo !RESULT_SKIP_BOOTREC!
echo.
echo Total steps run: !STEP_COUNT!    Failed: !FAIL_COUNT!
if "!RESTORE_POINT_DONE!"=="1" echo A System Restore point was created before making changes.
echo Full log saved to "%LOGFILE%"
echo Reports and event log exports saved to "%REPORT_DIR%"
echo =======================================
echo.

:: ---------------------------------------------------------------------------
:: 16. Reboot prompt - several fixes above only take effect after a restart
:: ---------------------------------------------------------------------------
if "!NEED_REBOOT!"=="1" (
    echo Some changes made by this script - scheduled disk repair, network
    echo reset, or boot repair - require a restart to take effect.
    choice /c YN /m "Reboot now"
    if !errorlevel! EQU 1 (
        if "!REBOOT_TO_WINRE!"=="1" (
            echo Rebooting into Advanced Startup...
            shutdown /r /o /t 5
        ) else (
            echo Rebooting...
            shutdown /r /t 5
        )
    ) else (
        echo Remember to restart your computer later to apply the pending changes.
    )
) else (
    echo No restart is required.
)

echo !FAIL_COUNT! > "%EXITCODE_FILE%"
pause
exit /b !FAIL_COUNT!

:: ===========================================================================
:: Subroutines
:: ===========================================================================

:: Records the errorlevel of the command that ran immediately before this
:: call as a pass/fail line in the summary. Usage: call :Result "Step name"
:Result
set "STEP_ERR=!errorlevel!"
set /a STEP_COUNT+=1
if "!STEP_ERR!"=="0" (
    echo [PASS] %~1
    set "R!STEP_COUNT!=[PASS] %~1"
) else (
    set /a FAIL_COUNT+=1
    echo [FAIL] %~1 - exit code !STEP_ERR!
    set "R!STEP_COUNT!=[FAIL] %~1 - exit code !STEP_ERR!"
)
goto :eof

:: Decides whether an opt-in step should run, based on the selected mode.
:: Usage: call :ShouldRun "description" RESULT_VAR_NAME
:ShouldRun
if /I "!MODE!"=="FULL" (
    set "%~2=1"
    goto :eof
)
if /I "!MODE!"=="QUICK" (
    set "%~2=0"
    goto :eof
)
choice /c YN /m "Run: %~1"
if !errorlevel! EQU 1 (set "%~2=1") else (set "%~2=0")
goto :eof
