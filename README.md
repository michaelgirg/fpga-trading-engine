# Market Parser

SystemVerilog implementation of a low-latency FPGA market-data and order
gateway. The design accepts 512-bit Ethernet/IPv4/UDP traffic, parses Nasdaq
MoldUDP64/TotalView-ITCH 5.0, maintains a guarded multi-symbol top of book,
generates risk-checked orders, and closes the loop through OUCH 5.0 and a
SoupBinTCP logical-session boundary. The datapath targets 100G-class FPGA
Ethernet user clocks.

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
  checks.
- A protocol-independent order lifecycle manager with monotonic client IDs,
  ready/valid command backpressure, pending/live/cancel state, partial-fill
  reconciliation, and fail-closed cancellation.
- An independent final egress risk guard with quantity, price, outstanding,
  rate, session, and kill checks; classified local rejects; and cancel bypass
  for fail-closed exposure withdrawal.
- A Nasdaq OUCH 5.0 gateway for byte-exact Enter and Cancel encoding plus
  Accepted, Rejected, Executed, and Canceled response handling.
- A SoupBinTCP logical-packet boundary with AXI backpressure, client login,
  heartbeat and logout generation, reconnect sequence tracking, one- and
  two-beat response deframing, a two-entry registered RX predecode FIFO, and a
  fail-closed watchdog. TCP transport and credentials remain external.
- A registered two-entry order-command FIFO that isolates lifecycle timing
  from exchange-gateway backpressure while preserving command order.
- A passive order-ID latency scoreboard with cycle-level new-to-wire,
  new-to-ACK, and new-to-first-fill extrema plus explicit anomaly counters.
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
- `rtl/market_parser_100g_cmac_axis_decision_impl_harness.sv`: compact routed packet-to-intent harness with fill feedback.
- `rtl/market_parser_100g_cmac_axis_order_top.sv`: complete packet-to-order lifecycle and position-reconciliation path.
- `rtl/market_parser_100g_cmac_axis_order_impl_harness.sv`: compact closed-loop order implementation harness.
- `rtl/market_parser_100g_cmac_axis_egress_top.sv`: packet-to-command path with final independent risk checks.
- `rtl/market_parser_100g_cmac_axis_egress_impl_harness.sv`: compact routed egress-risk harness.
- `rtl/market_parser_100g_ouch5_top.sv`: packet-to-Soup/OUCH integration with venue-response feedback.
- `rtl/market_parser_ouch5_gateway.sv`: command-level OUCH codec and Soup session boundary.
- `rtl/market_parser_100g_ouch5_impl_harness.sv`: compact routed packet-to-OUCH closed-loop harness.
- `rtl/market_parser_order_latency_monitor.sv`: passive order-path cycle telemetry.
- `tools/exchange_simulator.py`: deterministic and seeded-adversarial Python exchange model.
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
suppression counters. The order-lifecycle regression adds command
backpressure, client-ID assignment, acknowledgments, rejects, partial fills,
cancellation, kill-switch behavior, and closed-loop position updates. The
egress-risk regression adds independent quantity, price, outstanding-order,
rate, session, and kill checks, local-reject lifecycle reconciliation, cancel
bypass during session loss, and exact rejection counters. The OUCH/Soup
regression adds byte-exact order encoding, 64-byte two-beat response
reconstruction, logical-session watchdogs, transport rejects, and a closed-loop
market-packet-to-fill replay. The
Soup session regression additionally checks exact login bytes, ASCII sequence
parsing, reconnect state, client/server heartbeats, logout, transport loss, and
lossless packet queuing while the OUCH output is backpressured.
The
checked-in baseline passes with zero compile errors, zero compile warnings,
and zero failed tests.

The latency regression also checks Soup output stalls, partial fills, table
pressure, and malformed event sequences. The Python exchange suite adds
seeded latency jitter, probabilistic rejects, randomized fill slicing, and
response backpressure; it conserves every accepted share across 1,500 orders
and five seeds, while a separate 120-order replay
checks cancellation under backpressure. See `docs/order_latency.md` for
measurement semantics and local testbench latency.

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

The compact decision implementation harness replays a deterministic 512-bit
packet stream and acknowledges accepted intents as fills one cycle later. Its
self-checking test proves packet acceptance, quote evaluation, intent
generation, tracked position updates, and lossless replay. It closes post-route
at 3.102 ns / 322.4 MHz on the U50-class target with `+0.103 ns` WNS and
`+0.011 ns` WHS, using 20,142 LUTs, 22,515 registers, 8.5 BRAM tiles, and zero
DSPs.

The complete source-only packet-to-order top adds monotonic client IDs,
pending/live/cancel state, exchange-event reconciliation, partial-fill leaves,
fail-closed cancellation, and signed position feedback. It closes OOC at
3.102 ns / 322.4 MHz with `+0.490 ns` WNS; 2.500 ns / 400 MHz is a `0.112 ns`
stress near miss. Its compact closed-loop implementation harness closes
post-route at 3.102 ns with `+0.110 ns` WNS, zero TNS, and `+0.011 ns` WHS,
using 21,300 LUTs, 23,721 registers, 8.5 BRAM tiles, and zero DSPs.

The final source-only packet-to-command boundary adds independent quantity,
price, outstanding-order, rate, session, and kill checks after lifecycle state.
It closes OOC at 3.102 ns / 322.4 MHz with `+0.154 ns` WNS. Its compact
implementation harness closes post-route at the same clock with `+0.047 ns`
WNS, zero TNS, and `+0.010 ns` WHS, using 21,171 LUTs, 24,172 registers, 8.5
BRAM tiles, and zero DSPs.

The complete packet-to-Soup/OUCH implementation harness closes post-route at
3.102 ns / 322.4 MHz with `+0.075 ns` WNS, zero TNS, and `+0.010 ns` WHS,
using 26,227 LUTs, 30,185 registers, 8.5 BRAM tiles, and zero DSPs. This measured
result includes the 64-beat CMAC receive buffer, packet parsing, guarded
multi-symbol book, decision and lifecycle engines, final risk checks,
byte-exact OUCH transmission, Soup login/heartbeat/logout/reconnect state, and
two-beat acceptance/fill feedback, registered Soup RX predecode, and passive
order-path latency telemetry. The corresponding full OOC top closes the same
clock with `+0.012 ns` WNS and zero TNS.

An earlier source-only CMAC AXIS implementation harness, including packet
buffering, UDP realignment, parser, feed guard, AXI-Lite rebuild/activation,
and four bounded books, closes post-route at the native 3.102 ns / 322 MHz
target with `+0.176 ns` WNS and `+0.011 ns` WHS. The newer complete OUCH/Soup
harness above is the current source-level routed milestone. These harnesses
exclude the generated encrypted CMAC IP and are not bitstream or
hardware-programming claims.

The routed OUCH result above is the baseline immediately before adding the
passive order-latency monitor. Direct-indexed tagged telemetry reduced the
instrumented OOC miss to 18 ps, while routed implementation missed by 105 ps
on a raw `tkeep`-to-OUCH-capture path. A two-entry registered Soup RX predecode
FIFO removed that path; the next OOC run remained an 18 ps miss in the final
ASCII login-sequence commit enable. The current source registers that commit
as a separate cycle. The resulting full top closes OOC with 12 ps margin and
the compact harness closes post-route with 75 ps margin at 3.102 ns.

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
`docs/decision_engine.md`; the protocol-neutral command and reconciliation
boundary is documented in `docs/order_lifecycle.md`; the final independent
command checks are documented in `docs/egress_risk.md`; and the complete
logical session and order-gateway boundary is documented in
`docs/ouch5_gateway.md`.

## License And Data Handling

No credentials, hostnames, user directories, school paths, generated reports,
vendor IP output products, or machine-specific simulator metadata belong in
the repository. Keep those artifacts in ignored `build/` or local workspace
directories. Before publishing a change, run:

```bash
git diff --check
git status --short
```
