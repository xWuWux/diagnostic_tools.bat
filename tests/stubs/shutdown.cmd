@echo off
rem Safety stub: prevents any test run from ever triggering a real reboot,
rem no matter what a test answers at the reboot prompt.
echo [STUB] shutdown %* -- real reboot suppressed for testing
exit /b 0
