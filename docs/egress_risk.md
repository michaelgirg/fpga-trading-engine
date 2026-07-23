# Egress Risk Boundary

## Scope

`market_parser_order_risk_guard` is an independent final check between the
order lifecycle manager and a future venue gateway. It does not depend on the
strategy's earlier controls, so a bad command cannot bypass limits merely
because it originated inside the FPGA.

`market_parser_100g_cmac_axis_egress_top` connects the complete source-only
path:

```text
512-bit CMAC AXIS -> packet and feed guards -> four-symbol book
    -> decision engine -> order lifecycle -> egress risk guard
    -> protocol-neutral venue command
```

## Checks And Flow Control

Every new order is checked for:

- Risk enable, active gateway session, and kill-switch state.
- Nonzero quantity and a configurable maximum quantity.
- Configurable minimum and maximum price.
- Maximum outstanding lifecycle orders.
- Maximum new orders in a fixed clock window.

The command and reject outputs are elastic ready/valid interfaces. All fields
remain stable while backpressured. Cancels always pass the guard, including
while the session or risk controls block new orders, so existing exposure can
still be withdrawn.

A one-entry elastic input stage snapshots each command and its outstanding
order count before rule evaluation. This adds one decision clock, sustains one
command per clock, and prevents lifecycle state from feeding combinationally
through the risk rules and back into lifecycle ready/register-enable logic.

## Local Reject Reconciliation

A blocked new order never reaches the venue command output. The guard instead
returns its client order ID and a classified local-reject reason to the order
manager. The wrapper arbitrates that reject ahead of external exchange events,
and the normal lifecycle reconciliation path retires the pending order. This
keeps outstanding-order state and risk accounting consistent.

Gateway-session loss also drives the lifecycle cancel-all input. Working
orders are therefore withdrawn fail closed while the guard continues to admit
the resulting cancel commands.

## Verification

`verification/market_parser_order_risk_guard_tb.sv` checks every rejection
class, cancel bypass, exact counters, and output stability under backpressure.

`verification/market_parser_order_risk_integration_tb.sv` connects the guard
to the real lifecycle manager. It proves that a quantity violation creates one
local reject, emits no venue command, and clears outstanding state without a
protocol error. It then proves a valid new order can be acknowledged and its
cancel can cross after the gateway session becomes inactive.

`verification/market_parser_100g_cmac_axis_egress_impl_harness_tb.sv` replays
the complete packet-to-command path with permissive limits and deterministic
exchange feedback.

## Measured Timing

Vivado 2024.2 OOC synthesis on `xcu50-fsvh2104-2-e` closes the complete
`market_parser_100g_cmac_axis_egress_top` at 3.102 ns / 322.4 MHz with WNS
`+0.154 ns`, TNS `0.000 ns`, WHS `+0.036 ns`, and THS `0.000 ns`. It uses
28,618 LUTs, 28,806 registers, 8.5 BRAM tiles, and zero DSPs. The 2.500 ns /
400 MHz stress target misses by 0.448 ns.

The compact `market_parser_100g_cmac_axis_egress_impl_harness` closes
post-route at 3.102 ns / 322.4 MHz with WNS `+0.047 ns`, TNS `0.000 ns`, WHS
`+0.010 ns`, and THS `0.000 ns`. Routed utilization is 21,171 LUTs, 24,172
registers, 8.5 BRAM tiles, and zero DSPs.
