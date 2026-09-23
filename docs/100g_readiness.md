# 100G Readiness

## Implemented Boundary

The source tree implements a 512-bit market-data and order path intended for a
322.4 MHz-class 100G CMAC user clock:

```text
CMAC RX AXIS
  -> packet-atomic burst buffer
  -> Ethernet / IPv4 / UDP strip
  -> MoldUDP64 session and sequence handling
  -> parallel ITCH decode
  -> guarded multi-symbol books
  -> decision and position risk
  -> order lifecycle and final egress risk
  -> SoupBinTCP / OUCH logical packets
```

The parser core and source-level integration tops are synthesizable. Generated
CMAC products, implementation checkpoints, reports, and bitstreams remain
local build artifacts.

## Receive Path

The CMAC-facing interface carries 512-bit `tdata`, 64-bit `tkeep`, `tvalid`,
`tlast`, and bad-frame metadata. Because the generated CMAC AXIS RX interface
has no `tready`, `market_parser_cmac_axis_rx_bridge` buffers complete packets
before converting to the internal ready/valid stream. Overflow rolls back the
current packet atomically so a truncated frame never reaches the parser.

The default production source boundary provides:

- 64-beat no-backpressure CMAC burst storage.
- 32-beat per-packet parser storage.
- Ethernet II, IPv4-without-options, and UDP filtering and realignment.
- Packet, beat, overflow, drop, occupancy, and high-water telemetry.
- Immediate feed invalidation after packet loss or malformed traffic.

VLAN, IPv6, IPv4 options, fragmented IP, RSS, and TCP transport are outside
the current receive boundary.

## Feed Integrity

The guarded path fails closed on packet loss, bad metadata, MoldUDP64 sequence
gaps, session changes, end-of-session markers, and configurable inactivity
timeouts. A two-phase recovery clears bounded state, accepts replay traffic to
rebuild the books with quote output suppressed, and requires explicit software
activation before trading resumes.

The redundant A/B path adds packet-atomic arbitration, exact duplicate
suppression, bounded-skew failover, normalized session handling, and per-source
telemetry. Metadata disagreement or a sequence discontinuity invalidates the
merged feed.

## Trading Path

Four symbol books maintain exact order-reference state and emit ordered quote
updates. The downstream pipeline applies deterministic spread, liquidity,
imbalance, position, exposure, feed-health, and kill-switch checks. It then
tracks pending/live/cancel state, partial fills, local rejects, and signed
position before producing byte-exact OUCH Enter or Cancel messages.

The SoupBinTCP block implements logical login, heartbeat, logout, reconnect,
sequence state, and response deframing above TCP. Ethernet/TCP reliability,
socket establishment, credentials, and live exchange connectivity are not
implemented.

## Verification Evidence

The checked-in Questa regression contains 38 self-checking configurations and
covers:

- Golden ITCH packets, dense tiny messages, cross-beat fields, malformed and
  truncated frames, randomized backpressure, and FIFO pressure.
- No-idle MTU bursts, packet-atomic overflow, loss injection, feed timeout,
  replay rebuild, activation, and session recovery.
- A/B duplicate suppression, skew, failover, divergence, and gap handling.
- Multi-symbol book replay, strategy and risk gating, lifecycle state, exact
  OUCH bytes, Soup session behavior, and closed-loop acceptance/fill feedback.

The Python exchange model adds deterministic and seeded-adversarial venue
behavior. It conserves all accepted shares across 1,500 orders and five seeds
and separately verifies 120 cancellations under response backpressure.

## Timing Evidence

All measurements use Vivado 2024.2 and `xcu50-fsvh2104-2-e`.

| Boundary | Flow | Clock | WNS | Resources |
| :--- | :--- | ---: | ---: | :--- |
| 512-bit parser pipeline | OOC | 500.0 MHz | `+0.030 ns` | 12,278 LUTs, 12,700 registers |
| Redundant A/B packet-to-book | OOC | 363.6 MHz | `+0.009 ns` | 28,096 LUTs, 27,625 registers, 17 BRAM |
| Packet-to-intent | OOC | 400.0 MHz | `+0.014 ns` | 27,474 LUTs, 27,307 registers, 8.5 BRAM |
| Packet-to-Soup/OUCH | OOC | 322.4 MHz | `+0.012 ns` | 33,210 LUTs, 35,049 registers, 8.5 BRAM |
| Packet-to-Soup/OUCH harness | Routed | 322.4 MHz | `+0.075 ns` | 26,227 LUTs, 30,185 registers, 8.5 BRAM |
| Generated CAUI-4 CMAC plus parser | Routed | 322.4 MHz | `+0.071 ns` | 17,074 LUTs, 18,502 registers, 8.5 BRAM |

The generated CMAC design has zero black boxes, zero routing errors, and a
clean final DRC report. Bitstream generation is not claimed because the
available `cmac_usplus` license is limited to `Design_Linking`.

## Remaining Qualification

The next production-oriented work is constrained-random long-burst replay,
functional coverage, protocol assertions, latency distributions, host/TCP
integration, and hardware replay after a bitstream-authorized CMAC license is
available. The repository demonstrates architecture, correctness regression,
and routed timing; it is not a programmed trading NIC or live exchange client.
