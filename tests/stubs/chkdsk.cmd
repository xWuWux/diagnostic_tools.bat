@echo off
if not defined STUB_CHKDSK_SCAN_EXIT set "STUB_CHKDSK_SCAN_EXIT=0"
if not defined STUB_CHKDSK_REPAIR_EXIT set "STUB_CHKDSK_REPAIR_EXIT=0"
echo [STUB] chkdsk %*
echo %*| find /I "/f" >nul
if %errorlevel% EQU 0 (
    exit /b %STUB_CHKDSK_REPAIR_EXIT%
) else (
    exit /b %STUB_CHKDSK_SCAN_EXIT%
)
