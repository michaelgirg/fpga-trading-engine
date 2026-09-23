# Timing Matrix

## Reporting Rules

All rows use Vivado 2024.2 and `xcu50-fsvh2104-2-e`. OOC synthesis is a fast
architecture check; routed implementation includes placement, routing,
clocking, and compact board-like I/O. A pass requires nonnegative WNS and TNS.
Stress misses are retained only where they identify the measured frequency
boundary.

## Parser Core

| Top | Flow | Period | Frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| `market_parser_512_frontend` | OOC | `2.100 ns` | 476.2 MHz | `+0.082 ns` | `0.000 ns` | 983 | 1,043 | Pass |
| `market_parser_512_frontend` | OOC | `2.000 ns` | 500.0 MHz | `-0.018 ns` | `-0.184 ns` | 984 | 1,043 | Near miss |
| `market_parser_512_pipeline` | OOC | `2.100 ns` | 476.2 MHz | `+0.130 ns` | `0.000 ns` | 12,278 | 12,700 | Pass |
| `market_parser_512_pipeline` | OOC | `2.000 ns` | 500.0 MHz | `+0.030 ns` | `0.000 ns` | 12,278 | 12,700 | Pass |
| `market_parser_512_pipeline` | OOC | `1.950 ns` | 512.8 MHz | `-0.020 ns` | `-0.041 ns` | 12,278 | 12,700 | Near miss |

The 500 MHz claim applies to the integrated parser pipeline, not the complete
Ethernet-to-order gateway.

## Source-Level Integration

| Boundary | Top | Flow | Period | Frequency | WNS | LUTs | Registers | BRAM | Status |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| Ethernet-to-book | `market_parser_100g_strategy_top` | OOC | `2.350 ns` | 425.5 MHz | `+0.024 ns` | 23,189 | 21,869 | 0 | Pass |
| Guarded four-symbol feed | `market_parser_100g_multi_strategy_top` | OOC | `2.500 ns` | 400.0 MHz | `+0.098 ns` | 29,760 | 33,591 | 0 | Pass |
| CMAC AXIS guarded feed | `market_parser_100g_cmac_axis_multi_strategy_top` | OOC | `2.500 ns` | 400.0 MHz | `+0.011 ns` | 26,652 | 26,689 | 8.5 | Pass |
| Redundant A/B guarded feed | `market_parser_100g_ab_multi_strategy_top` | OOC | `2.750 ns` | 363.6 MHz | `+0.009 ns` | 28,096 | 27,625 | 17 | Pass |
| Redundant A/B guarded feed | `market_parser_100g_ab_multi_strategy_top` | OOC | `2.500 ns` | 400.0 MHz | `-0.241 ns` | 28,093 | 27,625 | 17 | Stress miss |
| Packet-to-intent | `market_parser_100g_cmac_axis_decision_top` | OOC | `2.500 ns` | 400.0 MHz | `+0.014 ns` | 27,474 | 27,307 | 8.5 | Pass |
| Packet-to-lifecycle | `market_parser_100g_cmac_axis_order_top` | OOC | `3.102 ns` | 322.4 MHz | `+0.490 ns` | 28,415 | 28,303 | 8.5 | Pass |
| Packet-to-lifecycle | `market_parser_100g_cmac_axis_order_top` | OOC | `2.500 ns` | 400.0 MHz | `-0.112 ns` | 28,603 | 28,293 | 8.5 | Stress miss |
| Packet-to-final-risk | `market_parser_100g_cmac_axis_egress_top` | OOC | `3.102 ns` | 322.4 MHz | `+0.154 ns` | 28,618 | 28,806 | 8.5 | Pass |
| Packet-to-Soup/OUCH | `market_parser_100g_ouch5_top` | OOC | `3.102 ns` | 322.4 MHz | `+0.012 ns` | 33,210 | 35,049 | 8.5 | Pass |

All rows use zero DSPs. The 3.102 ns period is the native 512-bit 100G
user-clock target; faster OOC rows are architectural stress points.

## Routed Source Harnesses

Compact harnesses keep the complete internal datapath while avoiding hundreds
of artificial package pins for debug and stream buses.

| Boundary | Top | Period | WNS | WHS | LUTs | Registers | BRAM | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| Packet-to-book | `market_parser_100g_strategy_impl_harness` | `3.102 ns` | `0.000 ns` | not recorded | 18,492 | 21,194 | 0 | Pass |
| CMAC AXIS guarded feed | `market_parser_100g_cmac_axis_impl_harness` | `3.102 ns` | `+0.176 ns` | `+0.011 ns` | 23,156 | 29,607 | 8.5 | Pass |
| Packet-to-intent | `market_parser_100g_cmac_axis_decision_impl_harness` | `3.102 ns` | `+0.103 ns` | `+0.011 ns` | 20,142 | 22,515 | 8.5 | Pass |
| Packet-to-lifecycle | `market_parser_100g_cmac_axis_order_impl_harness` | `3.102 ns` | `+0.110 ns` | `+0.011 ns` | 21,300 | 23,721 | 8.5 | Pass |
| Packet-to-final-risk | `market_parser_100g_cmac_axis_egress_impl_harness` | `3.102 ns` | `+0.047 ns` | `+0.010 ns` | 21,171 | 24,172 | 8.5 | Pass |
| Packet-to-Soup/OUCH | `market_parser_100g_ouch5_impl_harness` | `3.102 ns` | `+0.075 ns` | `+0.010 ns` | 26,227 | 30,185 | 8.5 | Pass |

## Generated CMAC Harness

The board-constrained CAUI-4 `4x25` implementation contains the generated
`cmac_usplus:3.1` checkpoint and parser integration:

| Top | Period | WNS | TNS | WHS | LUTs | Registers | BRAM | Black boxes | Route/DRC |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| `market_parser_100g_cmac_ip_impl_harness` | `3.102 ns` | `+0.071 ns` | `0.000 ns` | `+0.011 ns` | 17,074 | 18,502 | 8.5 | 0 | Clean |

The design is fully routed with zero routing errors. `write_bitstream` remains
blocked because the available CMAC entitlement is `Design_Linking`; this is a
license limitation, not a timing or DRC failure.

## Reproducing Runs

```bash
source <vivado-install>/settings64.sh

MARKET_PARSER_PARTS="xcu50-fsvh2104-2-e" \
MARKET_PARSER_TOPS="market_parser_512_pipeline" \
MARKET_PARSER_PERIODS="2.100 2.000" \
bash tools/run_hft_ooc_matrix.sh

MARKET_PARSER_PARTS="xcu50-fsvh2104-2-e" \
MARKET_PARSER_TOPS="market_parser_100g_ouch5_impl_harness" \
MARKET_PARSER_PERIODS="3.102" \
bash tools/run_hft_impl_matrix.sh
```

Each matrix writes per-run reports and `summary.tsv` beneath ignored `build/`
directories. Preserve the 500 MHz parser-core and 322.4 MHz complete-gateway
checks whenever functional changes touch those paths.
