# Order-Path Latency Telemetry

## Measurement Boundary

`market_parser_order_latency_monitor` is a passive, synthesizable scoreboard for
the outbound order path. It starts a sample when the final egress-risk boundary
accepts a new order and correlates that order by client ID through:

1. The SoupBinTCP unsequenced `U` packet carrying an OUCH Enter Order `O`.
2. The first decoded OUCH Accepted response.
3. The first decoded OUCH Executed response.

The reported intervals are new-to-wire, new-to-ACK, and new-to-first-fill.
They include the registered command FIFO, OUCH encoder, Soup framing, and any
logical Soup output backpressure. They do not include packet parsing before
the risk-approved command, TCP/IP transport, the Ethernet PHY, cable
propagation, or external venue time.

The monitor does not drive `valid`, `ready`, risk, lifecycle, or session state.
All telemetry is downstream of accepted handshakes, so instrumentation cannot
create a combinational trading control path.

Telemetry processing is split across four registered stages: accepted-event
capture, order-table lookup and state update, latency subtraction, and extrema
update. The first stage records the original handshake cycle, so this internal
pipeline changes only when a result becomes visible; it does not add cycles to
the measured interval or to the trading datapath.

## Correlation And Counters

The default 16-entry direct-indexed table uses the low client-order-ID bits to
select one slot, then verifies the complete 64-bit ID as a tag. It stores the
command cycle, original quantity, and observed wire/response state. This avoids
a wide associative-search path in passive telemetry. If two live IDs alias to
the same slot, the new sample fails observably through the table-full and
anomaly counters instead of disturbing the trading datapath. Partial fills
decrement tracked leaves quantity, while only the first fill contributes a
latency sample. A reject, cancel acknowledgment, or final fill retires the
entry.

Each interval exports last, minimum, maximum, and sample count in clock cycles.
Before the first sample, minimum is `0xffffffff`. The top level also exports
the number of tracked orders and a saturating aggregate anomaly count covering
duplicate orders, duplicate wire transfers, duplicate ACKs, unmatched wire or
response events, and table exhaustion.

## Verification

`verification/market_parser_order_latency_monitor_tb.sv` checks Soup output
backpressure, ACK and partial-fill correlation, final-fill retirement, bounded
table exhaustion, duplicate and unmatched event accounting, extrema, and
telemetry clear behavior.

The complete packet-to-OUCH replay reports this deterministic local simulation
result at a 3.102 ns clock:

| Interval | Cycles | Time |
| :--- | ---: | ---: |
| Risk-approved new order to Soup wire transfer | 3 | 9.306 ns |
| Risk-approved new order to decoded ACK | 10 | 31.020 ns |
| Risk-approved new order to first decoded fill | 12 | 37.224 ns |

These values describe the zero-network-delay RTL testbench, which injects the
venue response locally after observing the transmitted order. They are useful
for detecting pipeline regressions, not as a claim about exchange round-trip
latency.

`tools/exchange_simulator.py` also includes a Python 3.6-compatible seeded
adversarial venue. It varies ACK, fill, and cancel latency, injects rejects,
splits fills, and holds due events behind a ready boundary. Its regression
replays 1,500 orders across five seeds and proves deterministic reproduction,
ordered response delivery, exact reject accounting, and share conservation
across every accepted order. A separate 120-order replay verifies randomized
cancel acknowledgments while the response interface is backpressured.

## Hardware Status

The pipelined telemetry RTL and compact OUCH harness pass all 36 local Questa
testbenches with zero compile errors, zero compile warnings, and zero failed
tests. The Python exchange suite passes all eight tests and both files parse
with Python 3.6 grammar. U50 OOC synthesis and routed implementation are the
hardware checks for the current Soup sequence-commit revision; both now pass
at the native 3.102 ns clock.

The first instrumented U50 OOC attempt missed the 3.102 ns target by 1.973 ns.
Separating lookup, subtraction, and extrema updates improved the miss to 1.169
ns. Replacing the remaining associative lookup with a direct-indexed tagged
table reduced the OOC result to WNS `-0.018 ns`, TNS `-1.211 ns`. Routed
implementation reached WNS `-0.105 ns`, TNS `-20.289 ns`; its worst path ran
from the synthetic exchange response `tkeep` register through Soup length and
validity decoding to the OUCH receive register clock enable. The current source
adds a two-entry registered Soup RX predecode FIFO that stores length, keep, and
packet-type metadata before the receive state machine. That removed the raw
`tkeep` path, but the following OOC run remained at WNS `-0.018 ns`, TNS
`-1.175 ns` on the final ASCII login-sequence parse and commit enable. The
current source separates that commit into a registered cycle. The resulting
full OUCH top closes OOC with WNS `+0.012 ns`, TNS `0.000 ns`,
using 33,210 LUTs, 35,049 registers, 8.5 BRAM tiles, and zero DSPs. The compact
routed harness closes with WNS `+0.075 ns`, TNS `0.000 ns`, WHS `+0.010 ns`,
and THS `0.000 ns`, using 26,227 LUTs, 30,185 registers, 8.5 BRAM tiles, and
zero DSPs.
