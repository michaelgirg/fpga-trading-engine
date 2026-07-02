# Market Parser

SystemVerilog FPGA market-data parser project for a production-shaped Nasdaq
ITCH/MoldUDP64 feed-handler core.

The first version is intentionally simulation-first. It uses the same coding
style as the class references in this workspace: parameterized modules,
active-high synchronous reset, explicit FSMs, AXI-stream-style valid/ready
interfaces, and self-checking SystemVerilog testbenches.

## Current V1 Scope

- One MoldUDP64 packet per input stream frame.
- Byte-wide parser core plus 64-bit input wrapper.
- MoldUDP64 header parsing.
- Message count and sequence tracking.
- Gap detection.
- ITCH message splitting by MoldUDP64 length.
- Normalized 256-bit event output.
- Self-checking testbench using generated Add Order and System Event packet vectors.
- Generated vectors for `A`, `F`, `E`, `C`, `X`, `D`, `U`, `P`, and unknown-message handling.
- Gap, randomized output-backpressure, zero-length malformed-message, truncated-packet, heartbeat, and end-of-session smoke checks.
- 64-bit wrapper simulation using packed `tdata` and `tkeep` beats.
- Parameterized AXI-stream-style adapter tested at 64-, 256-, and 512-bit input widths.
- 512-bit 100G-facing ingress shell with FIFO, ingress counters, and no-stall burst test.
- First-beat 512-bit boundary scanner for MoldUDP64 header fields and early ITCH message-length candidates.
- Multi-beat 512-bit descriptor frontend for packet-relative ITCH message descriptors.
- Parallel 512-bit event extractor that turns descriptors plus a parameterized packet window into normalized events.
- Cut-through 512-bit parallel pipeline that wires descriptor generation, four-beat/256-byte default window buffering, staged field alignment, and event extraction into one event stream.
- Output event FIFO wrapper that decouples normalized parser events from downstream consumer backpressure.
- Back-to-back no-idle, dense tiny-message, and FIFO-pressure regressions with randomized event readiness.
- Extraction-window sweep regression at 128, 256, and 512 bytes.
- Pre-hardware 512-bit system wrapper with AXI-Lite control/status registers, parser enable, sticky error flags, software-visible counter clear, and event FIFO status.
- Optional cocotb randomized verification and Verilator lint hook for industry-style Python/open-source checks.
- Optional Vivado out-of-context synthesis script for pre-hardware resource/timing reports.
- School-side HFT OOC matrix wrapper for U50/U55/Virtex UltraScale+ style targets.
- Lightweight counter and latency reports in the Questa transcript.
- Strategy-facing packet-to-book top that turns raw 100G-style feed frames into
  single-symbol quote updates.

## Event Format

| Bits | Field |
| :--- | :--- |
| `[7:0]` | Normalized event kind |
| `[15:8]` | Original ITCH message type |
| `[31:16]` | Stock locate |
| `[47:32]` | Tracking number |
| `[95:48]` | Timestamp |
| `[159:96]` | Order reference |
| `[191:160]` | Shares |
| `[223:192]` | Price |
| `[231:224]` | Side |
| `[239:232]` | Flags |
| `[255:240]` | Reserved |

## Directory Layout

```text
market_parser/
  rtl/
    market_parser_pkg.sv
    market_parser.sv
    market_parser_axis_adapter.sv
    market_parser_64.sv
    market_parser_axis_register_slice.sv
    market_parser_100g_ingress.sv
    market_parser_512_boundary_scan.sv
    market_parser_512_frontend.sv
    market_parser_512_event_extract.sv
    market_parser_512_window_buffer.sv
    market_parser_512_pipeline.sv
    market_parser_event_fifo.sv
    market_parser_512_pipeline_fifo.sv
    market_parser_axi_lite_regs.sv
    market_parser_512_system.sv
    market_parser_100g_cmac_system.sv
    market_parser_top_of_book.sv
    market_parser_100g_strategy_top.sv
  verification/
    market_parser_tb.sv
    market_parser_64_tb.sv
    market_parser_axis_adapter_tb.sv
    market_parser_100g_ingress_tb.sv
    market_parser_512_boundary_scan_tb.sv
    market_parser_512_frontend_tb.sv
    market_parser_512_event_extract_tb.sv
    market_parser_512_pipeline_tb.sv
    market_parser_512_pipeline_fifo_tb.sv
    market_parser_512_system_tb.sv
    market_parser_top_of_book_tb.sv
    market_parser_100g_strategy_top_tb.sv
    run_verilator_lint.ps1
    cocotb/
    vectors/
  tools/
    itch_packets.py
    generate_vectors.py
    run_vivado_ooc.ps1
    run_vivado_ooc.tcl
    run_hft_ooc_matrix.sh
  docs/
    100g_readiness.md
    architecture.md
    cmac_integration.md
    high_speed_profiles.md
    project_pitch.md
    register_map.md
    references.md
    strategy_top.md
    timing_matrix.md
    zedboard_architecture.md
```

## Simulation Commands

Questa/ModelSim:

```tcl
cd verification
vsim -c -do run_questa.do
```

Vivado xsim:

```tcl
xvlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv verification/market_parser_tb.sv
xelab market_parser_tb -debug typical
xsim market_parser_tb -runall
```

Current Questa FSE smoke result:

```text
Core tests passed: 63
Wrapper tests passed: 21
AXI adapter profile tests passed: 66
100G ingress tests passed: 26
100G CMAC shell tests passed: 36
512-bit boundary scan tests passed: 17
512-bit frontend tests passed: 180
512-bit event extract tests passed: 42
512-bit pipeline sweep tests passed: 492
512-bit pipeline FIFO/stress tests passed: 247
512-bit system / AXI-Lite tests passed: 49
Top-of-book tests passed: 70
100G strategy top tests passed: 34
Tests failed: 0
Errors: 0, Warnings: 0
```

Optional cocotb setup:

```powershell
pip install -r verification/cocotb/requirements.txt
cd verification/cocotb
make SIM=questa
```

Without `make`, use:

```powershell
cd verification/cocotb
python run_cocotb.py --sim questa
```

Current cocotb smoke covers the golden mixed packet, repeated mixed packets
with randomized input/output timing, and bad/truncated packet flag checks:

```text
TESTS=3 PASS=3 FAIL=0
Errors: 0, Warnings: 0
```

Optional Verilator lint, when Verilator is installed:

```powershell
cd verification
powershell -ExecutionPolicy Bypass -File .\run_verilator_lint.ps1
```

If Verilator is installed in Ubuntu/WSL:

```bash
cd /mnt/d/Market_Parser
bash verification/run_verilator_lint_wsl.sh
```

Optional Vivado out-of-context synthesis:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_vivado_ooc.ps1
```

The default top is `market_parser_512_system` and the default part is the
ZedBoard `xc7z020clg484-1`. For a different board or a narrower top:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_vivado_ooc.ps1 -Top market_parser_512_pipeline -Part <xilinx-part> -ClockPeriodNs 3.102 -Directive RuntimeOptimized
```

Reports are written under `build/vivado_ooc/<top>/`.

Summarize generated Vivado reports:

```powershell
python tools/summarize_vivado_reports.py build/vivado_ooc/market_parser_512_pipeline
```

Run the school Linux HFT matrix wrapper after sourcing Vivado:

```bash
source /apps/xilinx/Vivado/2024.2/settings64.sh
bash tools/run_hft_ooc_matrix.sh
```

The matrix wrapper writes per-run reports and a `summary.tsv` under
`build/hft_ooc_matrix/<timestamp>/`. Override the run with
`MARKET_PARSER_PARTS`, `MARKET_PARSER_TOPS`, and `MARKET_PARSER_PERIODS` when
you want a smaller sweep.

Current Zynq-7020 OOC timing at a 3.102 ns target does not close for the
512-bit path. The latest `market_parser_512_pipeline` run reports WNS
`-3.290 ns`; the latest standalone `market_parser_512_frontend` run reports
WNS `-3.341 ns`. Zynq-7020 is therefore treated as a future functional demo
target, not the 100G timing target.

On a school Vivado 2024.2 install targeting the U50-class
`xcu50-fsvh2104-2-e` part, OOC synthesis at the same 3.102 ns target meets
timing: `market_parser_512_frontend` reports WNS `0.872 ns`, and
`market_parser_512_pipeline` reports WNS `1.091 ns`. This is an OOC synthesis
result for a realistic reference FPGA target, not full placed-and-routed
board-level timing closure. A follow-up OOC clock sweep for
`market_parser_512_pipeline` on the same U50-class part closes through
`2.000 ns` (500 MHz, WNS `0.030 ns`) and misses `1.950 ns` (~513 MHz) by
`0.020 ns`. After a lane-offset retiming cleanup, the standalone
`market_parser_512_frontend` also closes at `2.100 ns`; the integrated parser
top is the 500 MHz timing headline.

The full packet-to-book strategy top, `market_parser_100g_strategy_top`, also
meets the 3.102 ns / 322 MHz 100G user-clock target on `xcu50-fsvh2104-2-e`
with WNS `0.776 ns`, TNS `0.000 ns`, 23007 LUTs, 21869 registers, and no
BRAM/DSP usage after adding a payload register slice and staging the frontend
beat-offset update. A strategy-top clock sweep now closes `2.350 ns` / 426 MHz
with WNS `0.024 ns` and near-misses `2.300 ns` / 435 MHz by `0.026 ns`, so
500 MHz remains the parser-pipeline headline rather than the full packet-to-book
shell target.

## Test Vector Generation

The Python helper creates deterministic MoldUDP64/ITCH packets and the expected
normalized event words:

```powershell
python tools/generate_vectors.py
```

## Pre-Hardware Next Build Steps

1. Add larger replay-style strategy tests and a Python golden-model book checker.
2. Integrate with actual AMD CMAC IP, clocking, resets, and board constraints.
3. Run full implementation timing on the selected U50/U55-class board target.
4. Use the 1.950 ns parser near miss as an optional timing cleanup target.
5. Keep the ZedBoard wrapper and software demo as a separate optional functional hardware track.
