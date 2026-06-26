param(
    [string]$Top = "market_parser_512_system",
    [string]$Part = $(if ($env:MARKET_PARSER_PART) { $env:MARKET_PARSER_PART } else { "xc7z020clg484-1" }),
    [string]$ClockPeriodNs = $(if ($env:MARKET_PARSER_CLOCK_PERIOD_NS) { $env:MARKET_PARSER_CLOCK_PERIOD_NS } else { "3.102" }),
    [string]$Vivado = ""
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot\.."
$Script = Join-Path $Root "tools\run_vivado_ooc.tcl"

if ([string]::IsNullOrWhiteSpace($Vivado)) {
    $Command = Get-Command vivado -ErrorAction SilentlyContinue
    if ($Command) {
        $Vivado = $Command.Source
    }
}

if ([string]::IsNullOrWhiteSpace($Vivado) -and $env:VIVADO_BIN) {
    $Vivado = $env:VIVADO_BIN
}

if ([string]::IsNullOrWhiteSpace($Vivado) -or -not (Test-Path -LiteralPath $Vivado)) {
    throw "Could not find Vivado. Pass -Vivado <path-to-vivado.bat> or set VIVADO_BIN."
}

& $Vivado -mode batch -source $Script -tclargs $Top $Part $ClockPeriodNs
