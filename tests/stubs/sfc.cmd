@echo off
if not defined STUB_SFC_EXIT set "STUB_SFC_EXIT=0"
echo [STUB] sfc %*
exit /b %STUB_SFC_EXIT%
