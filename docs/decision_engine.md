# Decision Engine

## Scope

`market_parser_signal_engine` converts guarded top-of-book updates into a
venue-neutral order-intent stream. It is a deterministic hardware policy and
risk boundary, not an order-entry protocol implementation. A downstream
gateway must still assign venue identifiers, manage acknowledgments and
cancel/replace state, encode the selected protocol, and enforce its own final
risk checks.

`market_parser_100g_cmac_axis_decision_top` connects the engine after the
source-only CMAC AXIS, Ethernet/IPv4/UDP, MoldUDP64/ITCH, feed-guard, and
multi-symbol book path.

## Policy

A quote is eligible only when all of these conditions hold:

- The feed is healthy, the strategy is enabled, and the kill switch is clear.
- Order quantity and maximum absolute position are nonzero.
- The symbol is tracked and both sides of the market are valid and noncrossed.
- Spread is nonzero and no wider than `max_spread_ticks`.
- Bid and ask top-level quantities both meet `min_top_shares`.
- One side is strictly larger than the other side shifted left by
  `imbalance_shift`.
- The resulting signed position remains within `max_abs_position`.

A bid-heavy market emits a buy intent at the current ask. An ask-heavy market
emits a sell intent at the current bid. Balanced or ambiguous markets emit no
intent. This intentionally simple policy makes the cycle behavior auditable
and gives timing work a concrete downstream consumer without presenting the
logic as a profitable trading strategy.

## Risk And Flow Control

The engine keeps one signed 32-bit position per configured stock locate. Fill
inputs update those positions; untracked fills are counted separately. A fill
or position clear holds in-flight quote analysis for one cycle, withdraws a
pending intent, and then rechecks risk against the updated position.

The quote input uses a four-entry registered FIFO so downstream risk or intent
backpressure cannot form a combinational ready path into the book and feed
control logic. The intent output is a one-entry elastic ready/valid stage. It
holds the full payload stable while backpressured and can accept a new quote in
the same cycle an old intent is consumed. An unhealthy feed, disabled strategy,
or asserted kill switch withdraws and flushes pending intent. These controls
are synchronous to `clk` at the integration boundary.

The datapath exposes saturating counters for evaluated quotes, generated
intents, control suppression, market suppression, risk suppression, applied
fills, and untracked fills. Each accepted quote increments exactly one of the
generated or suppression categories.

## Verification

`verification/market_parser_signal_engine_tb.sv` checks:

- Buy and sell decisions and crossing prices.
- Stable intent payload under output backpressure.
- Feed-health, enable, zero-configuration, and kill-switch behavior.
- Spread, liquidity, balance, and untracked-symbol filtering.
- Signed fill accounting, position clearing, and long/short exposure limits.
- A fill arriving while a quote is in flight cannot use stale position state.
- Four consecutive quotes are accepted at one quote per clock.
- Exact generated and suppression counters.

`tools/signal_engine_golden.py` is the Python 3.6-compatible reference model;
`verification/test_signal_engine_golden.py` checks the same policy independently.
Registered quote buffering, market analysis, and risk/intent generation are
separate boundaries. Quote acceptance to intent-valid latency is two clock
cycles when the FIFO is empty, the output slot is available, and no fill is
being applied; the pipeline can still accept one quote per cycle.

## Measured Timing

Vivado 2024.2 OOC synthesis on `xcu50-fsvh2104-2-e` closes the complete
source-only packet-to-intent top at 2.500 ns / 400 MHz with WNS `+0.014 ns`,
TNS `0.000 ns`, WHS `+0.036 ns`, and THS `0.000 ns`. Utilization is 27,474
LUTs, 27,307 registers, 8.5 BRAM tiles, and zero DSPs. The same top misses
2.450 ns / 408 MHz by 0.036 ns.

The compact packet-to-intent-and-fill implementation harness also closes
post-route at 3.102 ns / 322.4 MHz with WNS `+0.103 ns`, TNS `0.000 ns`, WHS
`+0.011 ns`, and THS `0.000 ns`. It uses 20,142 LUTs, 22,515 registers, 8.5
BRAM tiles, and zero DSPs. This is a routed source-only result, not a hardware
deployment claim.

## Lifecycle Integration

`market_parser_100g_cmac_axis_order_top` now connects this intent stream to the
protocol-independent lifecycle manager documented in `order_lifecycle.md`.
That boundary assigns client order IDs, tracks pending and live orders,
reconciles acknowledgments, rejects, partial fills, and cancel acknowledgments,
and cancels working exposure when feed or strategy controls fail closed.

Actual venue encoding, session transport, and network transmission remain
separate gateway responsibilities.
