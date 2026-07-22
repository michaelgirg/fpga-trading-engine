# Market Parser

SystemVerilog implementation of a low-latency NASDAQ TotalView-ITCH 5.0
parser. The design accepts MoldUDP64 frames, tracks session and sequence
continuity, decodes
ITCH messages into normalized events, and maintains bounded single- or
multi-symbol top of book. The main datapath is a 512-bit AXI4-Stream-style
pipeline intended for 100G-class FPGA Ethernet user clocks.

## What Is Included

- MoldUDP64 header, sequence, message-length, heartbeat, session, and
  end-of-session handling.
- ITCH add, execute, cancel, delete, replace, trade, system, and unknown-message handling.
- Normalized 256-bit event records, exact Replace reference tracking, and
  packet-to-top-of-book strategy paths.
- 64-, 256-, and 512-bit stream adapters with valid/ready backpressure.
- 512-bit cut-through parsing with descriptor generation, parallel extraction,
  event buffering, counters, sticky error flags, and AXI-Lite status registers.
- Fail-closed multi-symbol book invalidation for MoldUDP64 session changes,
  end-of-session markers, sequence gaps, CMAC
  packet-buffer loss, and packet inactivity, with event suppression,
  configurable AXI-Lite liveness monitoring, fault counters, two-phase book
  rebuild, session/sequence re-baselining, and explicit feed activation.
- A 64-beat no-backpressure CMAC burst buffer and 32-beat parser packet
  envelope sized for back-to-back standard-MTU-class feed frames.
- Hardware-qualified feed activation that requires applied rebuild traffic and
  records rejected premature activation commands through AXI-Lite.
- CMAC-facing UDP payload stripping and AXI stream buffering for a generated
  AMD/Xilinx UltraScale+ CMAC interface.
- A venue-neutral quote-to-order-intent engine with spread, liquidity,
  imbalance, signed position, exposure-limit, feed-health, and kill-switch
  checks. It emits intents for downstream gateway work; it does not encode or
  transmit exchange orders.
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
- `rtl/market_parser_100g_cmac_axis_multi_strategy_top.sv`: source-only CMAC AXIS to guarded multi-symbol strategy path.
- `rtl/market_parser_signal_engine.sv`: deterministic quote-to-intent and risk boundary.
- `rtl/market_parser_100g_cmac_axis_decision_top.sv`: complete source-only packet-to-intent integration.
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
single- and multi-symbol golden-model top-of-book replay. It also verifies
contiguous no-`tready` CMAC bursts, packet-atomic overflow rollback, immediate
feed invalidation on bridge loss, bridge-health telemetry, session-change,
end-of-session, and sequence-gap handling, packet-inactivity timeout, distinct
fault causes, and AXI-Lite rebuild/activation from an independent replay
sequence. A contiguous pair of 1462-byte Ethernet frames additionally proves
lossless parsing and accounting of 200 ITCH messages without an idle CMAC
cycle. The signal-engine regression adds output backpressure, feed/kill gating,
market filters, signed fill accounting, long/short exposure limits, and exact
suppression counters. The checked-in baseline passes with zero compile errors,
zero compile warnings, and zero failed tests.

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

The end-of-session-guarded source-only CMAC AXIS four-symbol packet-to-quote top
closes 2.500 ns / 400 MHz with `+0.011 ns` WNS, using 26,652 LUTs, 26,689
registers, and 8.5 BRAM tiles on the same U50-class part. This boundary includes Ethernet/IP/UDP stripping,
MoldUDP64/ITCH parsing, event buffering, four independent order tables,
fail-closed session, sequence, packet-loss, and liveness protection, and ordered quote
arbitration. The packet window uses 1,000 distributed-memory LUTs and the CMAC
burst buffer infers block RAM. These source-level OOC results do not require
CMAC IP.

The complete source-only packet-to-intent top also closes 2.500 ns / 400 MHz
OOC with `+0.014 ns` WNS and zero TNS. It uses 27,474 LUTs, 27,307 registers,
8.5 BRAM tiles, and zero DSPs. This boundary extends the guarded four-symbol
book path with a registered quote FIFO, deterministic imbalance policy, signed
position tracking, exposure limits, kill/feed gating, and a backpressured
venue-neutral order-intent stream.

The source-only CMAC AXIS implementation harness, including packet buffering,
UDP realignment, parser, feed guard, AXI-Lite rebuild/activation, and four
bounded books, also closes post-route at the native 3.102 ns / 322 MHz target
with `+0.176 ns` WNS and `+0.011 ns` WHS, using 23156 LUTs and 29607 registers.
This routed result includes the end-of-session guard. The subsequent 64-beat
CMAC burst-buffer and 32-beat packet-envelope expansion is locally verified and
awaits refreshed timing. The harness excludes the
generated encrypted CMAC IP and is not a bitstream or hardware-programming
claim.

The generated AXIS CAUI-4 CMAC integration has also been routed on the
U50-class target. This harness contains the real encrypted CMAC IP and the
single-symbol packet-to-book path:

- CMAC core: `CMACE4_X0Y4`.
- GT lanes: `X0Y28` through `X0Y31`.
- Reference-clock site: `GTYE4_COMMON_X0Y7`.
- Board I/O and hard-block placement are constrained and reported.
- Zero black boxes remain after integrated synthesis.
- Post-route timing at 3.102 ns: WNS `+0.071 ns`, TNS `0.000 ns`, WHS
  `+0.011 ns`, THS `0.000 ns`.
- Post-route utilization: 17,074 LUTs, 18,502 registers, 8.5 BRAM tiles,
  1,312 LUTs as memory, and zero DSPs.
- The route report has zero routing errors and the final DRC summary contains
  no errors, critical warnings, or warnings.

Bitstream generation is currently blocked by the encrypted CMAC IP license
level exposed by the available Vivado installation. A fresh IP/netlist
regeneration still reports `Design_Linking` for `cmac_usplus` and
`write_bitstream` rejects `i_cmac_usplus_0_top` as an encrypted cell for which
bitstream generation is not permitted. This is a license-entitlement
limitation after successful synthesis, placement, routing, timing, and DRC;
it is not evidence that the design has been programmed onto hardware.

See `docs/cmac_integration.md` for the generated-IP flow and board-shell
details, `docs/timing_matrix.md` for measured timing, and
`docs/implementation_timing.md` for routed-report conventions. The
quote-to-intent policy and safety boundary are documented in
`docs/decision_engine.md`.

## License And Data Handling

No credentials, hostnames, user directories, school paths, generated reports,
vendor IP output products, or machine-specific simulator metadata belong in
the repository. Keep those artifacts in ignored `build/` or local workspace
directories. Before publishing a change, run:

```bash
git diff --check
git status --short
```
