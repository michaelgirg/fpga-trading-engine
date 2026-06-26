#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

rtl_files=(
    "$repo_root/rtl/market_parser_pkg.sv"
    "$repo_root/rtl/market_parser.sv"
    "$repo_root/rtl/market_parser_axis_adapter.sv"
    "$repo_root/rtl/market_parser_64.sv"
    "$repo_root/rtl/market_parser_100g_ingress.sv"
    "$repo_root/rtl/market_parser_512_boundary_scan.sv"
    "$repo_root/rtl/market_parser_512_frontend.sv"
    "$repo_root/rtl/market_parser_512_event_extract.sv"
    "$repo_root/rtl/market_parser_512_window_buffer.sv"
    "$repo_root/rtl/market_parser_512_pipeline.sv"
    "$repo_root/rtl/market_parser_event_fifo.sv"
    "$repo_root/rtl/market_parser_512_pipeline_fifo.sv"
    "$repo_root/rtl/market_parser_axi_lite_regs.sv"
    "$repo_root/rtl/market_parser_512_system.sv"
)

tops=(
    market_parser
    market_parser_axis_adapter
    market_parser_64
    market_parser_100g_ingress
    market_parser_512_boundary_scan
    market_parser_512_frontend
    market_parser_512_event_extract
    market_parser_512_pipeline
    market_parser_event_fifo
    market_parser_512_pipeline_fifo
    market_parser_axi_lite_regs
    market_parser_512_system
)

for top in "${tops[@]}"; do
    echo "Linting $top"
    verilator --lint-only -sv --timing -Wall \
        -Wno-DECLFILENAME \
        -Wno-IMPORTSTAR \
        -Wno-UNUSEDSIGNAL \
        -Wno-UNUSEDPARAM \
        --top-module "$top" \
        "${rtl_files[@]}"
done
