param([string]$Vsim = 'vsim')
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$LogDir = Join-Path $Root 'build\questa_runner_selftest'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Push-Location $LogDir
try {
    foreach ($Mode in 0..4) {
        $Log = Join-Path $LogDir "mode_$Mode.log"
        $DoFile = (Join-Path $PSScriptRoot 'run_questa_runner_probe.do').Replace('\', '/')
        $ProbeRoot = $Root.Replace('\', '/')
        & $Vsim -c -l $Log -do "set probe_mode $Mode; set probe_root {$ProbeRoot}; do {$DoFile}" | Out-Null
        $Code = $LASTEXITCODE
        $Output = Get-Content -Raw -LiteralPath $Log
        if ($Output -notmatch "RUNNER PROBE mode=$Mode") {
            throw "Mode $Mode never reached the probe; inspect $Log"
        }
        if ($Mode -eq 0) {
            if ($Code -ne 0 -or $Output -notmatch 'REGRESSION PASS:') {
                throw "Passing probe failed with exit code $Code; inspect $Log"
            }
        } elseif ($Code -eq 0 -or $Output -notmatch 'REGRESSION ERROR:') {
            throw "Failing probe mode $Mode was not rejected; inspect $Log"
        }
        Write-Output "PASS: runner mode=$Mode exit=$Code"
    }
} finally {
    Pop-Location
}
