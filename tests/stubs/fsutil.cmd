@echo off
if /I "%~1"=="dirty" if /I "%~2"=="query" (
    if not defined STUB_FSUTIL_DIRTY set "STUB_FSUTIL_DIRTY=0"
    if "%STUB_FSUTIL_DIRTY%"=="1" (
        echo %~3 - is Dirty
    ) else (
        echo %~3 - is NOT Dirty
    )
    exit /b 0
)
echo [STUB] fsutil %*
exit /b 0
