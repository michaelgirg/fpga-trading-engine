# Implementation Timing Flow

The OOC matrix is useful for fast iteration, but the next realism step is a
routed implementation run on the selected HFT-class part. The repo includes a
non-project Vivado implementation flow for that purpose:

- `tools/run_vivado_impl.tcl` runs synth, opt, place, optional phys-opt, route,
  and post-route timing/utilization reports.
- `tools/run_hft_impl_matrix.sh` wraps the Tcl flow into the same summary-table
  style as the OOC matrix.
- `tools/probe_cmac_ip.tcl` records the CMAC/100G/Ethernet IP definitions
  visible in the school Vivado install for the chosen part.
- `tools/probe_cmac_usplus_config.tcl` creates a local `cmac_usplus:3.1` IP
  instance and records its configurable properties/template for the selected
  part.

The first routed target is `market_parser_100g_strategy_impl_harness` at
`3.102 ns` on `xcu50-fsvh2104-2-e`. The harness keeps
`market_parser_100g_strategy_top` internal, drives a generated replay packet
through its CMAC-style RX stream, and exposes only `clk`, `rst`, and a compact
status hash as package pins. That avoids meaningless IO-placement failure from
trying to assign every debug counter and 512-bit stream lane to package pins.
The follow-up routed target is `market_parser_100g_cmac_axis_impl_harness`,
which drives the source-only CMAC AXIS RX boundary used by the generated
`cmac_usplus` AXIS template before the packet-to-book strategy path.
The current routed target is `market_parser_100g_ouch5_impl_harness`, which
extends that compact boundary through quote analysis, client-order lifecycle,
independent final risk, byte-exact OUCH, Soup logical-session control, and
deterministic exchange acknowledgment/fill handling.

## Measured Routed Result

The strongest vendor-IP result is the board-constrained generated-CMAC
single-symbol harness:

| Part | Top | Period | Frequency | WNS | WHS | LUTs | Registers | BRAM | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_ip_impl_harness` | `3.102 ns` | 322.4 MHz | `0.071 ns` | `0.011 ns` | `17074 / 871680 (1.96%)` | `18502 / 1743360 (1.06%)` | `8.5 / 1344 (0.63%)` | Fully routed, timing met |

The implementation has zero unrouted nets, zero routing errors, and a clean
DRC summary. Bitstream generation is a separate failed step: the encrypted
CMAC cell remains limited to `Design_Linking`, including after fresh output
product and netlist generation under the updated server license.

Vivado 2024.2 post-route implementation on the school U50-class target closes
the 100G user-clock class after adding a CMAC RX register slice before payload
stripping:

| Part | Top | Period | Frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_impl_harness` | `3.102 ns` | 322.4 MHz | `0.000 ns` | `0.000 ns` | `18492 / 871680 (2.12%)` | `21194 / 1743360 (1.22%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_impl_harness` | `3.102 ns` | 322.4 MHz | `0.176 ns` | `0.000 ns` | `23156 / 871680 (2.66%)` | `29607 / 1743360 (1.70%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_decision_impl_harness` | `3.102 ns` | 322.4 MHz | `0.103 ns` | `0.000 ns` | `20142 / 871680 (2.31%)` | `22515 / 1743360 (1.29%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_order_impl_harness` | `3.102 ns` | 322.4 MHz | `0.110 ns` | `0.000 ns` | `21300 / 871680 (2.44%)` | `23721 / 1743360 (1.36%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_egress_impl_harness` | `3.102 ns` | 322.4 MHz | `0.047 ns` | `0.000 ns` | `21171 / 871680 (2.43%)` | `24172 / 1743360 (1.39%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_ouch5_impl_harness` | `3.102 ns` | 322.4 MHz | `0.075 ns` | `0.000 ns` | `26227 / 871680 (3.01%)` | `30185 / 1743360 (1.73%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_impl_harness` | `2.500 ns` | 400.0 MHz | `-0.826 ns` | `-4858.989 ns` | `18620 / 871680 (2.14%)` | `21169 / 1743360 (1.21%)` | Stress miss |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_impl_harness` | `2.350 ns` | 425.5 MHz | `-0.957 ns` | `-8524.854 ns` | `18632 / 871680 (2.14%)` | `21181 / 1743360 (1.21%)` | Stress miss |

The prior routed attempt failed with a path from raw CMAC `tkeep` into the UDP
payload-strip FIFO write logic. Registering the CMAC RX stream before header
strip creates the intended implementation boundary and removes the false
board-pin/debug-port placement problem.

Routed stress points at `2.500 ns` and `2.350 ns` do not close. That is expected
to be harder than the OOC sweep because the implementation harness includes
placement, routing, clocking, and a board-like IO boundary. The key routed
milestone is the `3.102 ns` / 322 MHz pass.

The CMAC AXIS implementation harness is now the stronger routed boundary proof:
it includes the no-backpressure CMAC AXIS packet buffer, UDP strip/realignment,
MoldUDP64/ITCH parser pipeline, event buffering, fail-closed session, sequence,
loss, and
liveness protection, AXI-Lite feed rebuild/activation, and four-symbol
top-of-book path, while still avoiding unrealistic package-pin pressure from
debug buses. Its 176 ps setup margin is a valid native-clock pass, but is not
evidence for a higher routed frequency. The complete OUCH/Soup harness below
supersedes it as the current source-level routed proof and includes the later
64-beat CMAC burst buffer and 32-beat parser packet envelope.

The order harness is the current complete source-only routed boundary. It
extends the same packet/feed/book path through quote analysis, a backpressured
intent stream, monotonic client IDs, pending/live/cancel state, deterministic
exchange acknowledgment and fill reconciliation, and signed position risk
feedback. It meets the native 100G clock with 110 ps of setup margin and 11 ps
of hold margin, with zero total negative slack.

The egress harness adds the independent final risk boundary after lifecycle
state. A registered elastic input stage removes lifecycle-state feedback from
the risk decision and ready path. The complete harness meets the native clock
post-route with 47 ps of setup margin and 10 ps of hold margin, with zero total
negative slack.

The OUCH implementation harness extends that boundary through byte-exact order
encoding, Soup logical framing, two-beat venue response reconstruction,
client-generated login/heartbeat/logout/reconnect state, and acceptance/fill
feedback. The current instrumented revision meets 3.102 ns post-route with 75
ps setup margin, 10 ps hold margin, and zero total negative slack. It includes
the passive order-latency monitor, registered exchange-response boundary, and
two-entry Soup RX predecode FIFO.

## Soup Timing Closure

`market_parser_order_latency_monitor` passively tracks risk-approved new orders
through logical Soup transmission, ACK, and first fill without feeding any
ready or risk path. Registered telemetry stages and a direct-indexed tagged
table improved the instrumented 3.102 ns OOC result from WNS `-1.973 ns` to
`-0.018 ns`, TNS `-1.211 ns`. The corresponding routed result reached WNS
`-0.105 ns`, TNS `-20.289 ns`. Its worst path was not in the monitor: it ran
from the synthetic exchange response `tkeep` register through Soup length and
validity decoding to an OUCH receive register clock enable.

The next revision inserted a two-entry registered Soup RX predecode FIFO. It
captures each beat with precomputed keep count, keep validity, packet length,
payload length, and packet type, then presents that metadata to the receive
state machine one stage later. The FIFO accepts a second packet while OUCH
output is stalled and propagates backpressure only when both entries are full.
The following OOC run confirmed that the raw `tkeep` path was gone, but still
reported WNS `-0.018 ns`, TNS `-1.175 ns` from the last ASCII sequence character
through login-sequence validation to the `next_sequence` clock enable. The
current source places final-character parsing and session/sequence commit in
separate registered cycles. The resulting full OUCH top closes 3.102 ns OOC
with WNS `+0.012 ns`, TNS `0.000 ns`, while the compact routed harness closes
with WNS `+0.075 ns`, TNS `0.000 ns`, WHS `+0.010 ns`, and THS `0.000 ns`.
All 36 local Questa testbenches pass with zero compile errors, zero compile
warnings, and zero failed tests. See `docs/order_latency.md` for exact
measurement semantics.

This is still an RTL implementation flow, not a finished Alveo shell. The CMAC
probe is intentionally separate because the actual IP wrapper depends on the
available Vivado IP definition, board shell, GT placement, reference clocks,
resets, and management interface.

The U50-class school install exposes `xilinx.com:ip:cmac_usplus:3.1`. The first
configuration probe successfully created the IP and generated an instantiation
template, with the default core using `CONFIG.USER_INTERFACE = LBUS` and
`CONFIG.ENABLE_AXIS = 0`. A follow-up AXIS-requested probe also succeeded with
`CONFIG.USER_INTERFACE = AXIS` and `CONFIG.ENABLE_AXIS = 1`, generating both
`.veo` and `.vho` templates. The generated AXIS RX side exposes `tvalid`,
`tdata`, `tkeep`, `tlast`, and `tuser`, but no `tready`, so the repo now
includes a source-only CMAC AXIS RX bridge and
`market_parser_100g_cmac_axis_strategy_top` wrapper.

The CMAC AXIS strategy wrapper closes OOC at `3.102 ns` / 322.4 MHz on
`xcu50-fsvh2104-2-e` with WNS `0.449 ns`, TNS `0.000 ns`, 23965 LUTs, 23709
registers, and no BRAM/DSP usage after staging the UDP payload-strip predecode
path. A stress sweep closes the same wrapper at `2.750 ns` / 363.6 MHz with WNS
`0.097 ns`, then misses `2.500 ns` / 400.0 MHz by `0.153 ns`. A separate flow
has already generated and routed the actual CAUI-4 CMAC checkpoint with board
clock/reset and hard-block constraints; see `docs/cmac_integration.md`.

## Report Files

Each implementation run produces:

- `post_synth_timing_summary.rpt`
- `post_place_timing_summary.rpt`
- `timing_summary.rpt`
- `utilization.rpt`
- `clock_utilization.rpt`
- `route_status.rpt`
- `drc.rpt`
- `post_route.dcp`

The matrix summary uses the post-route `timing_summary.rpt`.
