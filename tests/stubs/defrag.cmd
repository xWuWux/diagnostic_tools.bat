@echo off
if not defined STUB_DEFRAG_EXIT set "STUB_DEFRAG_EXIT=0"
echo [STUB] defrag %*
exit /b %STUB_DEFRAG_EXIT%
