#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for diagnostic_tools.bat.

    These use stub replacements for the slow/destructive external commands
    (sfc, DISM, chkdsk, defrag, bootrec, netsh) so the script's control flow
    -- menu branching, errorlevel handling, logging, WinRE detection,
    timestamped filenames -- can be exercised deterministically, without
    running a real SFC/DISM scan or touching real disk/boot state.

    A shutdown.cmd stub is ALWAYS on PATH during these tests as a safety
    net: even if a test answers "Y" to a reboot prompt, it must never
    trigger a real reboot of the VM this runs on.

    Run only on a disposable Windows VM or Windows Sandbox -- never against
    a machine you care about, since the script still writes real files
    under .\Logs and %userprofile%\Desktop\DiagnosticReports, and runs a
    handful of genuinely safe read-only commands (ipconfig, ping,
    driverquery, pnputil, wevtutil, powercfg, gpupdate) for real.

    See tests/README.md for setup and how to run these.
#>

BeforeDiscovery {
    $script:IsElevated = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

BeforeAll {
    $Script = (Resolve-Path (Join-Path $PSScriptRoot '..\diagnostic_tools.bat')).Path
    $StubDir = (Resolve-Path (Join-Path $PSScriptRoot 'stubs')).Path
    $ScriptDir = Split-Path $Script -Parent
    $ReportDir = Join-Path $env:USERPROFILE 'Desktop\DiagnosticReports'
    $OriginalPath = $env:Path

    function Invoke-DiagnosticScript {
        param(
            [string[]] $Answers = @(),
            [hashtable] $StubEnv = @{}
        )

        $env:Path = "$StubDir;$OriginalPath"
        foreach ($key in $StubEnv.Keys) {
            Set-Item -Path "Env:$key" -Value $StubEnv[$key]
        }
        # A couple of spare "N" answers pad every sequence: choice.exe under
        # piped stdin is known to be finicky, and any answers past the last
        # real prompt are simply left unread -- harmless.
        $stdin = ($Answers + @('N', 'N')) -join "`n"
        $output = $stdin | & $Script 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        foreach ($key in $StubEnv.Keys) {
            Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
        }
        $env:Path = $OriginalPath

        [pscustomobject]@{
            Output   = $output
            ExitCode = $exitCode
        }
    }
}

AfterAll {
    $env:Path = $OriginalPath
}

Describe 'diagnostic_tools.bat' {

    It 'aborts with a clear message when not run elevated' -Skip:$IsElevated {
        $result = $null | & $Script 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $result | Should -Match 'Administrator privileges required'
    }

    Context 'Elevated runs (external commands stubbed)' {

        It 'Quick mode skips gated steps, exits 0, and writes a log file' -Skip:(-not $IsElevated) {
            $r = Invoke-DiagnosticScript -Answers @('2') -StubEnv @{ STUB_FSUTIL_DIRTY = '0' }

            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'Skipped: System File Checker'
            $r.Output | Should -Match 'Skipped: DISM ScanHealth'
            $r.Output | Should -Match 'Diagnostics Summary'
            $r.Output | Should -Match 'No disk repair required'

            (Get-ChildItem (Join-Path $ScriptDir 'Logs') -Filter 'diagnostics_*.log' |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1) |
                Should -Not -BeNullOrEmpty
        }

        It 'Full mode schedules disk repair when the volume is dirty, and asks to reboot' -Skip:(-not $IsElevated) {
            $r = Invoke-DiagnosticScript -Answers @('3') -StubEnv @{ STUB_FSUTIL_DIRTY = '1' }

            $r.Output | Should -Match 'is marked dirty'
            $r.Output | Should -Match 'Scheduling chkdsk /f /r'
            $r.Output | Should -Match '\[PASS\] Disk Repair Scheduling'
            $r.Output | Should -Match 'require a restart to take effect'
        }

        It 'reports a [FAIL] line and a non-zero exit code when a stubbed step fails' -Skip:(-not $IsElevated) {
            # Quick mode skips SFC/DISM-restore-health, so force a failure in
            # a step Quick mode still runs: DISM CheckHealth.
            $r = Invoke-DiagnosticScript -Answers @('2') -StubEnv @{
                STUB_FSUTIL_DIRTY = '0'
                STUB_DISM_EXIT    = '1'
            }

            $r.Output | Should -Match '\[FAIL\] DISM CheckHealth - exit code 1'
            [int]$r.ExitCode | Should -BeGreaterThan 0
        }

        It 'skips bootrec outside WinRE with manual instructions' -Skip:(-not $IsElevated) {
            $r = Invoke-DiagnosticScript -Answers @('2') -StubEnv @{ STUB_FSUTIL_DIRTY = '0' }

            $r.Output | Should -Match 'only works from the Windows Recovery'
            $r.Output | Should -Not -Match 'Windows Recovery Environment detected'
        }

        It 'runs bootrec when SystemDrive indicates WinRE' -Skip:(-not $IsElevated) {
            $originalSystemDrive = $env:SystemDrive
            try {
                $env:SystemDrive = 'X:'
                $r = Invoke-DiagnosticScript -Answers @('2') -StubEnv @{ STUB_FSUTIL_DIRTY = '0' }
            } finally {
                $env:SystemDrive = $originalSystemDrive
            }

            $r.Output | Should -Match 'Windows Recovery Environment detected'
            $r.Output | Should -Match '\[PASS\] bootrec /rebuildbcd'
        }

        It 'timestamps report files instead of overwriting them across runs' -Skip:(-not $IsElevated) {
            Invoke-DiagnosticScript -Answers @('2') -StubEnv @{ STUB_FSUTIL_DIRTY = '0' } | Out-Null
            Start-Sleep -Seconds 1
            Invoke-DiagnosticScript -Answers @('2') -StubEnv @{ STUB_FSUTIL_DIRTY = '0' } | Out-Null

            $reports = Get-ChildItem $ReportDir -Filter 'battery-report_*.html' -ErrorAction SilentlyContinue
            $reports.Count | Should -BeGreaterOrEqual 2
            ($reports | Select-Object -ExpandProperty Name -Unique).Count | Should -Be $reports.Count
        }
    }
}
