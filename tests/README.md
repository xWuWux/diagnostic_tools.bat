# Testing diagnostic_tools.bat

BATS is a Bash framework and doesn't apply to a `.bat`/`cmd.exe` script. The
practical Windows equivalent used here is [Pester](https://pester.dev/), the
standard test framework for PowerShell and batch scripts.

**Only run these on a disposable Windows VM or Windows Sandbox, never on a
machine you care about.** Even with stubs in place, the script still runs a
handful of genuinely real, but safe, read-only commands (`ipconfig`, `ping`,
`driverquery`, `pnputil`, `wevtutil`, `powercfg`, `gpupdate`) and writes real
files under `.\Logs` and `%userprofile%\Desktop\DiagnosticReports`.

## What's stubbed vs. real

| Command | In tests |
|---|---|
| `sfc`, `DISM`, `chkdsk`, `defrag`, `bootrec`, `netsh`, `fsutil dirty query` | Stubbed (`tests/stubs`) - never touch real disk/boot/network state |
| `shutdown` | Stubbed as a safety net so a test can never trigger a real reboot, even if it answers "Y" to a reboot prompt |
| `net session` (elevation check) | Real - reflects whatever elevation the test process actually has |
| `ipconfig`, `ping`, `driverquery`, `pnputil`, `wevtutil`, `powercfg`, `gpupdate`, `powershell` (timestamp/logging/restore point) | Real - safe, read-only or idempotent |

## One-time setup

1. Provision a disposable Windows 10 or 11 VM (Hyper-V, VirtualBox, or
   Windows Sandbox for a lighter-weight option, though Sandbox resets on
   close so you'd re-clone the repo each session).
2. Install Pester 5, since Windows ships an old Pester 3.4 by default:
   ```powershell
   Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
   ```
3. Clone/copy this repo onto the VM.

## Running the tests

The elevation-abort test and the "elevated runs" tests are mutually
exclusive (one needs a non-elevated session, the rest need an elevated
one), so run the suite twice:

```powershell
# 1. From a NON-elevated PowerShell prompt - exercises the abort path:
Invoke-Pester -Path .\tests\diagnostic_tools.Tests.ps1 -Output Detailed

# 2. From an elevated ("Run as administrator") PowerShell prompt - exercises
#    everything else; the non-elevated test auto-skips itself here:
Invoke-Pester -Path .\tests\diagnostic_tools.Tests.ps1 -Output Detailed
```

Each run's tests auto-skip whichever scenarios don't apply to the current
elevation level, so you'll see a handful of `Skipped` results in each pass -
that's expected.

## If a test hangs

`choice.exe`'s behavior when its stdin comes from a pipe rather than an
interactive console is a known source of flakiness. If a run hangs instead
of completing, it almost always means the piped answer sequence in
`Invoke-DiagnosticScript` (in the `.Tests.ps1` file) didn't line up with an
actual `choice` prompt in the script - compare the captured `$r.Output` up
to the hang point against `diagnostic_tools.bat` to see which prompt is
waiting, and adjust the `-Answers` array for that test.

## Cleaning up between runs

Test runs accumulate real files:

- `..\Logs\diagnostics_*.log` in the repo
- `%userprofile%\Desktop\DiagnosticReports\*` (battery/energy reports, event
  log exports)

Delete both between test sessions if you want a clean slate; neither is
required for correctness (the timestamp test specifically relies on old
report files still being there to prove new ones don't overwrite them).

## Beyond these tests

These tests only verify control flow: menu branching, errorlevel handling,
logging, WinRE detection, and timestamped filenames. They cannot verify that
the *real* commands behave as expected (e.g. that `bootrec` actually repairs
a boot record from inside a real WinRE session, or that a real `chkdsk /f
/r` schedule survives a real restart). Do that once, manually, on the
disposable VM:

- Boot the VM into WinRE (`shutdown /r /o /t 0`, or hold Shift while
  clicking Restart) and run the script from the WinRE command prompt to
  confirm the real `bootrec` branch works end-to-end.
- Run the script normally with disk-repair opted in against a volume you've
  marked dirty (`fsutil dirty set C:`), then actually restart the VM and
  confirm `chkdsk` runs at boot.
