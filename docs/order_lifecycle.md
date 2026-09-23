# Order Lifecycle

## Scope

`market_parser_order_manager` turns the decision engine's venue-neutral intents
into a deterministic command stream and reconciles exchange responses. It is a
protocol-independent lifecycle boundary; binary venue framing, session login,
retransmission, and network transport belong in a downstream gateway.

`market_parser_100g_cmac_axis_order_top` connects the complete source-only path:

```text
512-bit CMAC AXIS -> Ethernet/IPv4/UDP -> MoldUDP64/ITCH
    -> guarded multi-symbol book -> decision engine -> order lifecycle
    -> exchange events -> fill reconciliation -> signed position
```

## Lifecycle

The manager supports one working order per configured symbol. An accepted
intent receives a monotonic 64-bit client order ID and enters the new-order
queue. Transmission, acknowledgment, live-order, cancellation, rejection, and
fill states are tracked independently for each symbol.

The command interface uses ready/valid flow control and holds every field
stable while backpressured. Busy-symbol and untracked-symbol intents are
consumed and counted so one symbol cannot block unrelated work. Exchange
events are matched by client order ID. A registered one-hot match stage
separates 64-bit ID comparison from fill arithmetic and lifecycle state
updates; it adds one reconciliation cycle while sustaining one event per
clock.

Supported response handling includes:

- New-order acknowledgments and rejects.
- Partial and complete fills with leaves-quantity tracking.
- Cancel commands and cancel acknowledgments.
- Overfill clamping with protocol-error accounting.
- Unmatched or state-inconsistent event detection.

## Fail-Closed Controls

Trading is enabled only while the feed is healthy, the strategy is enabled,
and the kill switch is clear. If any condition fails, an unsent new command is
withdrawn and every transmitted or live order is marked for deterministic
cancellation. This does not claim wire-level venue connectivity. The lifecycle
boundary remains protocol-neutral, while `market_parser_ouch5_gateway` is the
implemented downstream OUCH/Soup adapter.

## Verification

`verification/market_parser_order_manager_tb.sv` checks command backpressure,
monotonic IDs, duplicate-intent handling, acknowledgments, rejects, partial
fills, cancel races, cancellation before transmission, overfill protection,
unmatched events, and exact counters.

`verification/market_parser_100g_cmac_axis_order_top_tb.sv` replays two
multi-symbol packet vectors through the full packet-to-order chain, then
checks order emission, acknowledgment, partial-fill position updates,
kill-switch cancellation, and final working-order state.

`tools/exchange_simulator.py` provides Python 3.6-compatible deterministic and
seeded-adversarial exchange models. The adversarial mode varies response
latency, injects rejects, splits fills, and holds due events behind a ready
boundary. `verification/test_exchange_simulator.py` independently verifies
reproducibility, response ordering, exact reject accounting, and share
conservation across 1,500 orders and five seeds. A separate 120-order replay
checks randomized cancel acknowledgments under response backpressure.

`market_parser_order_latency_monitor` passively correlates risk-approved new
orders with their logical Soup wire transfer, first ACK, and first fill. Its
measurement boundary and local cycle results are documented in
`docs/order_latency.md`.

The compact `market_parser_100g_cmac_axis_order_impl_harness` embeds a known
packet replay and deterministic exchange responder so synthesis and routed
implementation preserve the complete packet, decision, order, fill, and
position path. Vivado 2024.2 OOC synthesis on `xcu50-fsvh2104-2-e` closes
3.102 ns / 322.4 MHz with WNS `+0.490 ns`; 2.500 ns / 400 MHz misses by
0.112 ns. The compact harness closes post-route at 3.102 ns with WNS
`+0.110 ns`, TNS `0.000 ns`, WHS `+0.011 ns`, and THS `0.000 ns`, using
21,300 LUTs, 23,721 registers, 8.5 BRAM tiles, and zero DSPs.
