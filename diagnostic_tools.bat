@echo off
:: Comprehensive Diagnostic and Troubleshooting Script for Windows 10
:: Author: Wojciech Wozniak - king of infrastructure - https://www.linkedin.com/in/wojciech-wo%C5%BAniak-8261a214a/

echo =======================================
echo      Windows 10 Diagnostics Script
echo =======================================
echo Running as Administrator is required.
echo Press any key to continue...
pause

:: 1. System File Check (SFC)
echo Running System File Checker (SFC)...
sfc /scannow
echo.

:: 2. Restore system health using DISM
echo Checking and restoring system health with DISM...
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth
echo.

:: 3. Clean DNS Resolver Cache
echo Flushing DNS resolver cache...
ipconfig /flushdns
echo.

:: 4. Check Disk for Errors
echo Running disk check on system drive...
chkdsk C: /f /r
echo.

:: 5. Check Driver Status
echo Listing installed drivers and their status...
driverquery
echo.

:: 6. Update Group Policy
echo Forcing group policy updates...
gpupdate /force
echo.

:: 7. Network Diagnostics
echo Displaying network adapter information...
ipconfig /all
echo Testing internet connectivity...
ping 8.8.8.8 -n 5
echo Resetting network settings...
netsh winsock reset
netsh int ip reset
echo Releasing and renewing IP configuration...
ipconfig /release
ipconfig /renew
ipconfig /registerdns
echo.

:: 8. Driver Diagnostics
echo Detecting problematic drivers...
pnputil /enum-devices /problem
echo.
echo Reinstalling problematic drivers (manually specify oemXX.inf if required)...
:: Uncomment and replace `oemXX.inf` with appropriate file name if needed.
:: pnputil /delete-driver oemXX.inf /uninstall
echo.

:: 9. Optimize Windows Performance
echo Cleaning temporary files...
del /s /q %temp%\*
echo Optimizing drives...
defrag C: /O
echo.

:: 10. Hardware Diagnostics
echo Checking battery report (if applicable)...
powercfg /batteryreport /output "%userprofile%\Desktop\battery-report.html"
echo Generating energy report...
powercfg /energy /output "%userprofile%\Desktop\energy-report.html"
echo.

:: 11. System Event Logs
echo Exporting system event logs for diagnostics...
wevtutil epl System %userprofile%\Desktop\SystemLogs.evtx
wevtutil epl Application %userprofile%\Desktop\ApplicationLogs.evtx
echo Event logs saved to Desktop.
echo.

:: 12. Boot Issues Diagnostics
echo Checking and repairing boot configuration data...
bootrec /fixmbr
bootrec /fixboot
bootrec /scanos
bootrec /rebuildbcd
echo.

echo =======================================
echo Diagnostics and Troubleshooting Complete!
echo Check logs and reports saved on your Desktop.
echo =======================================
pause
