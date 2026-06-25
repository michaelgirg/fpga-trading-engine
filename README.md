# Market Parser

SystemVerilog FPGA market-data parser project for a production-shaped Nasdaq
ITCH/MoldUDP64 feed-handler core.

The first version is intentionally simulation-first. It uses the same coding
style as the class references in this workspace: parameterized modules,
active-high synchronous reset, explicit FSMs, AXI-stream-style valid/ready
interfaces, and self-checking SystemVerilog testbenches.

## Current V1 Scope

- One MoldUDP64 packet per input stream frame.
- Byte-wide input stream for readable first-pass RTL.
- MoldUDP64 header parsing.
- Message count and sequence tracking.
- Gap detection.
- ITCH message splitting by MoldUDP64 length.
- Normalized 256-bit event output.
- Self-checking testbench using generated Add Order and System Event packet vectors.
- Generated vectors for `A`, `F`, `E`, `C`, `X`, `D`, `U`, `P`, and unknown-message handling.
- Gap, output-backpressure, zero-length malformed-message, and truncated-packet smoke checks.

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
  verification/
    market_parser_tb.sv
    vectors/
  tools/
    itch_packets.py
    generate_vectors.py
  docs/
    architecture.md
    references.md
```

## Simulation Commands

Questa/ModelSim:

```tcl
vlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv verification/market_parser_tb.sv
vsim -c market_parser_tb -do "run -all; quit"
```

Vivado xsim:

```tcl
xvlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv verification/market_parser_tb.sv
xelab market_parser_tb -debug typical
xsim market_parser_tb -runall
```

Current Questa FSE smoke result:

```text
Tests passed: 49
Tests failed: 0
Errors: 0, Warnings: 0
```

## Test Vector Generation

The Python helper creates deterministic MoldUDP64/ITCH packets and the expected
normalized event words:

```powershell
python tools/generate_vectors.py
```

## Next Build Steps

1. Add randomized output backpressure tests.
2. Add heartbeat and end-of-session packet tests.
3. Add a 64-bit input packing wrapper.
4. Add a lightweight latency/counter report in the testbench.
5. Add ZedBoard integration wrapper after simulation behavior is stable.
