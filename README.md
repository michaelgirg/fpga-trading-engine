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
- Cut-through 512-bit parallel pipeline that wires descriptor generation, four-beat/256-byte default window buffering, and event extraction into one event stream.
- Output event FIFO wrapper that decouples normalized parser events from downstream consumer backpressure.
- Back-to-back no-idle packet stress and FIFO-pressure regression with randomized event readiness.
- Extraction-window sweep regression at 128, 256, and 512 bytes.
- Pre-hardware 512-bit system wrapper with AXI-Lite control/status registers, parser enable, sticky error flags, software-visible counter clear, and event FIFO status.
- Optional cocotb randomized verification and Verilator lint hook for industry-style Python/open-source checks.
- Optional Vivado out-of-context synthesis script for pre-hardware resource/timing reports.
- Lightweight counter and latency reports in the Questa transcript.

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
    run_verilator_lint.ps1
    cocotb/
    vectors/
  tools/
    itch_packets.py
    generate_vectors.py
    run_vivado_ooc.ps1
    run_vivado_ooc.tcl
  docs/
    100g_readiness.md
    architecture.md
    high_speed_profiles.md
    project_pitch.md
    register_map.md
    references.md
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
512-bit boundary scan tests passed: 17
512-bit frontend tests passed: 88
512-bit event extract tests passed: 42
512-bit pipeline sweep tests passed: 210
512-bit pipeline FIFO/stress tests passed: 247
512-bit system / AXI-Lite tests passed: 47
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
powershell -ExecutionPolicy Bypass -File .\tools\run_vivado_ooc.ps1 -Top market_parser_512_pipeline -Part <xilinx-part> -ClockPeriodNs 3.102
```

Reports are written under `build/vivado_ooc/<top>/`.

Summarize generated Vivado reports:

```powershell
python tools/summarize_vivado_reports.py build/vivado_ooc/market_parser_512_pipeline
```

## Test Vector Generation

The Python helper creates deterministic MoldUDP64/ITCH packets and the expected
normalized event words:

```powershell
python tools/generate_vectors.py
```

## Pre-Hardware Next Build Steps

1. Run Vivado OOC synthesis and record resource/timing summaries for the 512-bit pipeline and system tops.
2. Add more cocotb randomized packet/backpressure tests around the AXI-Lite system wrapper.
3. Add deeper event FIFO and 512-byte long-payload stress cases.
4. Only after the simulation and OOC synthesis story is stronger, add the ZedBoard-specific wrapper and software demo.
