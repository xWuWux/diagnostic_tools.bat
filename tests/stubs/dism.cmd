@echo off
if not defined STUB_DISM_EXIT set "STUB_DISM_EXIT=0"
echo [STUB] DISM %*
exit /b %STUB_DISM_EXIT%
