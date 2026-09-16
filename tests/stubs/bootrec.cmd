@echo off
if not defined STUB_BOOTREC_EXIT set "STUB_BOOTREC_EXIT=0"
echo [STUB] bootrec %*
exit /b %STUB_BOOTREC_EXIT%
