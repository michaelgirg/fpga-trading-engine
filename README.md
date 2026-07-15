# Market Parser

SystemVerilog implementation of a low-latency NASDAQ TotalView-ITCH 5.0
parser. The design accepts MoldUDP64 frames, tracks sequence gaps, decodes
ITCH messages into normalized events, and maintains bounded single- or
multi-symbol top of book. The main datapath is a 512-bit AXI4-Stream-style
pipeline intended for 100G-class FPGA Ethernet user clocks.

## What Is Included

- MoldUDP64 header, sequence, message-length, heartbeat, and session handling.
- ITCH add, execute, cancel, delete, replace, trade, system, and unknown-message handling.
- Normalized 256-bit event records, exact Replace reference tracking, and
  packet-to-top-of-book strategy paths.
- 64-, 256-, and 512-bit stream adapters with valid/ready backpressure.
- 512-bit cut-through parsing with descriptor generation, parallel extraction,
  event buffering, counters, sticky error flags, and AXI-Lite status registers.
- CMAC-facing UDP payload stripping and AXI stream buffering for a generated
  AMD/Xilinx UltraScale+ CMAC interface.
- Self-checking Questa/SystemVerilog tests, deterministic packet vectors,
  optional cocotb tests, and optional Verilator lint.
- Vivado OOC and routed implementation scripts. Generated reports and vendor
  IP output products remain outside version control.

## Repository Layout

```text
rtl/            Synthesizable parser, stream, strategy, and CMAC-shell RTL
verification/   SystemVerilog testbenches, cocotb tests, and packet vectors
tools/          Vector generation, Vivado flows, and report helpers
docs/           Architecture, timing, register, and integration notes
filelist.f      Common RTL file list
```

The most useful entry points are:

- `rtl/market_parser_512_pipeline.sv`: integrated 512-bit parser pipeline.
- `rtl/market_parser_100g_strategy_top.sv`: packet-to-top-of-book strategy path.
- `rtl/market_parser_100g_multi_strategy_top.sv`: bounded multi-symbol strategy path.
- `rtl/market_parser_100g_cmac_ip_strategy_top.sv`: generated CMAC AXIS boundary.
- `rtl/market_parser_100g_cmac_ip_impl_harness.sv`: board-oriented U50 shell.
- `verification/run_questa.do`: complete Questa regression.
- `tools/run_vivado_ooc.tcl`: single-top OOC synthesis.
- `tools/run_vivado_cmac_ip_impl.tcl`: generated-CMAC implementation flow.

## Quick Start

Run the complete local simulation regression from the repository root:

```tcl
cd verification
vsim -c -do run_questa.do
```

The regression covers parser correctness, malformed and truncated frames,
randomized backpressure, dense messages, FIFO pressure, AXI-Lite status, and
single- and multi-symbol golden-model top-of-book replay. The current
checked-in baseline passes with zero compile errors, zero compile warnings,
and zero failed tests.

Generate or refresh deterministic packet vectors with Python 3:

```powershell
python tools/generate_vectors.py
```

Optional cocotb and Verilator checks are documented in
`verification/cocotb/README.md` and `verification/run_verilator_lint.ps1`.

## Vivado Flows

The scripts use relative paths and environment variables. Supply the Vivado
installation setup appropriate to the machine running them; no installation
path is hard-coded in this repository.

Single-top OOC synthesis on a local Vivado installation:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_vivado_ooc.ps1 `
  -Top market_parser_512_pipeline `
  -Part <xilinx-part> `
  -ClockPeriodNs 2.000 `
  -Directive RuntimeOptimized
```

Linux Vivado matrix flow:

```bash
source <vivado-install>/settings64.sh
MARKET_PARSER_PARTS="<xilinx-part>" \
MARKET_PARSER_TOPS="market_parser_512_pipeline" \
MARKET_PARSER_PERIODS="3.102 2.100 2.000" \
bash tools/run_hft_ooc_matrix.sh
```

Reports are written below `build/`, which is ignored by Git. Use
`tools/summarize_vivado_reports.py` to turn a report directory into a compact
timing and utilization summary.

## Current Hardware Evidence

The 512-bit parser pipeline closes a 2.000 ns target, equivalent to 500 MHz,
in U50-class UltraScale+ OOC synthesis with positive slack. The full strategy
path is a larger packet-to-book design and is intentionally evaluated at the
native 100G CMAC user-clock class rather than presented as a 500 MHz claim.

The bounded four-symbol packet-to-quote top closes through 2.500 ns / 400 MHz
with `+0.171 ns` WNS, using about 3.41% of LUTs and 1.92% of registers on the
same U50-class part. This boundary includes Ethernet/IP/UDP stripping,
MoldUDP64/ITCH parsing, event buffering, four independent order tables, and
ordered quote arbitration. These source-level OOC results do not require CMAC
IP.

The CAUI-4 CMAC integration flow has also been routed on the U50-class target:

- CMAC core: `CMACE4_X0Y4`.
- GT lanes: `X0Y28` through `X0Y31`.
- Reference-clock site: `GTYE4_COMMON_X0Y7`.
- Board I/O and hard-block placement are constrained and reported.
- Zero black boxes remain after integrated synthesis.
- Post-route timing at 3.102 ns: WNS `+0.026 ns`, TNS `0.000 ns`.
- Final DRC has no errors or critical warnings; one non-blocking `PDRC-146`
  slice-packing warning remains.

Bitstream generation is currently blocked by the encrypted CMAC IP license on
the available Vivado installation. This is a tool-license limitation after
successful synthesis, placement, routing, timing, and DRC; it is not evidence
that the design has been programmed onto hardware.

See `docs/cmac_integration.md` for the generated-IP flow and board-shell
details, `docs/timing_matrix.md` for measured timing, and
`docs/implementation_timing.md` for routed-report conventions.

## License And Data Handling

No credentials, hostnames, user directories, school paths, generated reports,
vendor IP output products, or machine-specific simulator metadata belong in
the repository. Keep those artifacts in ignored `build/` or local workspace
directories. Before publishing a change, run:

```bash
git diff --check
git status --short
```
