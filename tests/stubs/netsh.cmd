@echo off
if not defined STUB_NETSH_EXIT set "STUB_NETSH_EXIT=0"
echo [STUB] netsh %*
exit /b %STUB_NETSH_EXIT%
