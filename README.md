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
- Parallel 512-bit event extractor that turns descriptors plus a two-beat packet window into normalized events.
- Packet-buffered 512-bit parallel pipeline that wires descriptor generation, two-beat window buffering, and event extraction into one event stream.
- Optional cocotb verification scaffold and Verilator lint hook for industry-style Python/open-source checks.
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
  verification/
    market_parser_tb.sv
    market_parser_64_tb.sv
    market_parser_axis_adapter_tb.sv
    market_parser_100g_ingress_tb.sv
    market_parser_512_boundary_scan_tb.sv
    market_parser_512_frontend_tb.sv
    market_parser_512_event_extract_tb.sv
    market_parser_512_pipeline_tb.sv
    run_verilator_lint.ps1
    cocotb/
    vectors/
  tools/
    itch_packets.py
    generate_vectors.py
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
512-bit pipeline tests passed: 59
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

## Test Vector Generation

The Python helper creates deterministic MoldUDP64/ITCH packets and the expected
normalized event words:

```powershell
python tools/generate_vectors.py
```

## Next Build Steps

1. Add a ZedBoard RTL wrapper with AXI-Lite register reads and an event FIFO.
2. Evolve the 512-bit packet-buffered pipeline into a cut-through pipeline that overlaps ingress, descriptor extraction, and event egress.
