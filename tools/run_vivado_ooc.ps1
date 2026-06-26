param(
    [string]$Top = "market_parser_512_system",
    [string]$Part = $(if ($env:MARKET_PARSER_PART) { $env:MARKET_PARSER_PART } else { "xc7z020clg484-1" })
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot\.."
$Script = Join-Path $Root "tools\run_vivado_ooc.tcl"

vivado -mode batch -source $Script -tclargs $Top $Part
