$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot\.."
$RtlFiles = @(
    "$Root\rtl\market_parser_pkg.sv",
    "$Root\rtl\market_parser.sv",
    "$Root\rtl\market_parser_axis_adapter.sv",
    "$Root\rtl\market_parser_64.sv",
    "$Root\rtl\market_parser_100g_ingress.sv",
    "$Root\rtl\market_parser_512_boundary_scan.sv",
    "$Root\rtl\market_parser_512_frontend.sv",
    "$Root\rtl\market_parser_512_event_extract.sv",
    "$Root\rtl\market_parser_512_window_buffer.sv",
    "$Root\rtl\market_parser_512_pipeline.sv",
    "$Root\rtl\market_parser_event_fifo.sv",
    "$Root\rtl\market_parser_512_pipeline_fifo.sv"
)

verilator --lint-only -sv --timing -Wall `
    -Wno-DECLFILENAME `
    -Wno-UNUSEDSIGNAL `
    -Wno-UNUSEDPARAM `
    $RtlFiles
