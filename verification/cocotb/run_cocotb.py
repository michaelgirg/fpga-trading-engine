from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

from cocotb_tools.runner import get_runner


def rtl_sources(repo_root: Path) -> list[Path]:
    rtl = repo_root / "rtl"
    return [
        rtl / "market_parser_pkg.sv",
        rtl / "market_parser.sv",
        rtl / "market_parser_axis_adapter.sv",
        rtl / "market_parser_64.sv",
        rtl / "market_parser_100g_ingress.sv",
        rtl / "market_parser_512_boundary_scan.sv",
        rtl / "market_parser_512_frontend.sv",
        rtl / "market_parser_512_event_extract.sv",
        rtl / "market_parser_512_window_buffer.sv",
        rtl / "market_parser_512_pipeline.sv",
        rtl / "market_parser_event_fifo.sv",
        rtl / "market_parser_512_pipeline_fifo.sv",
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Run cocotb tests for the 512-bit market parser pipeline.")
    parser.add_argument("--sim", default="questa", choices=["questa", "verilator"], help="Simulator backend.")
    parser.add_argument("--waves", action="store_true", help="Enable waveform dumping when supported.")
    parser.add_argument("--clean", action="store_true", help="Clean cocotb build directory before running.")
    args = parser.parse_args()

    cocotb_dir = Path(__file__).resolve().parent
    repo_root = cocotb_dir.parents[1]
    os.chdir(cocotb_dir)
    build_dir = f"sim_build_{args.sim}"
    runner = get_runner(args.sim)

    if args.sim == "verilator":
        build_args = [
            "--timing",
            "-Wno-DECLFILENAME",
            "-Wno-IMPORTSTAR",
            "-Wno-UNUSEDSIGNAL",
            "-Wno-UNUSEDPARAM",
        ]
        test_args = []
    else:
        build_args = ["-sv"]
        test_args = ["-no_autoacc"]

    runner.build(
        sources=rtl_sources(repo_root),
        hdl_toplevel="market_parser_512_pipeline",
        build_args=build_args,
        build_dir=build_dir,
        clean=args.clean,
        timescale=("1ns", "1ps"),
        waves=args.waves,
    )

    if args.sim == "questa":
        subprocess.run(["vmap", "top", str(Path(build_dir) / "top")], check=True)

    runner.test(
        hdl_toplevel="market_parser_512_pipeline",
        hdl_toplevel_lang="verilog",
        test_module="test_market_parser_512_pipeline",
        test_dir=cocotb_dir,
        build_dir=build_dir,
        test_args=test_args,
        timescale=("1ns", "1ps"),
        waves=args.waves,
    )


if __name__ == "__main__":
    main()
