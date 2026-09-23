# FPGA Trading Engine

SystemVerilog implementation of a low-latency market-data and order gateway.
The design accepts 512-bit Ethernet/IPv4/UDP traffic, parses Nasdaq
MoldUDP64/TotalView-ITCH 5.0, maintains guarded multi-symbol books, applies
decision and risk logic, and emits SoupBinTCP-framed OUCH 5.0 orders.

```text
100G RX AXIS
  -> packet buffer and UDP strip
  -> redundant A/B MoldUDP64 arbitration
  -> parallel ITCH parser
  -> guarded multi-symbol top of book
  -> quote decision and position risk
  -> order lifecycle and final egress risk
  -> SoupBinTCP / OUCH 5.0 gateway
```

## Highlights

- 512-bit cut-through parser with parallel boundary detection, field
  extraction, normalized 256-bit events, buffering, and backpressure.
- ITCH Add, Execute, Cancel, Delete, Replace, Trade, System, and unknown-event
  handling.
- Packet-atomic redundant A/B feed arbitration with sequence-aware
  deduplication, bounded-skew failover, session normalization, and fail-closed
  gap or metadata-divergence handling.
- Four guarded symbol books with exact order-reference tracking, feed
  invalidation, two-phase rebuild, and explicit activation.
- Quote-to-intent policy with spread, liquidity, imbalance, signed position,
  exposure, feed-health, and kill-switch checks.
- Order lifecycle tracking with monotonic client IDs, partial fills,
  cancellation, final egress risk, and local-reject reconciliation.
- Byte-exact OUCH Enter/Cancel encoding and Accepted, Rejected, Executed, and
  Canceled response handling.
- SoupBinTCP logical-session handling for login, heartbeat, logout, reconnect,
  sequence state, response deframing, and watchdog faults. TCP transport is
  intentionally external.
- Passive order-ID latency telemetry for new-to-wire, new-to-ACK, and
  new-to-first-fill measurements.

## Verification

The checked-in Questa regression runs 38 self-checking configurations. It
covers parser correctness, malformed and truncated packets, dense messages,
randomized backpressure, FIFO pressure, AXI-Lite control, book replay, feed
faults and recovery, A/B duplicate suppression and failover, strategy and risk
gating, order lifecycle events, exact protocol bytes, and closed-loop
packet-to-fill behavior.

The Python models add deterministic and seeded-adversarial exchange behavior.
The exchange regression conserves all accepted shares across 1,500 orders and
five seeds and separately checks 120 cancellations under response
backpressure.

Run the primary regressions from the repository root:

```bash
cd verification
vsim -c -do run_questa.do
cd ..
python -m unittest verification/test_exchange_simulator.py \
  verification/test_signal_engine_golden.py
```

Optional cocotb and Verilator flows are documented in
`verification/cocotb/README.md` and `verification/run_verilator_lint.ps1`.

## Measured Results

All results target `xcu50-fsvh2104-2-e` in Vivado 2024.2. OOC and routed
implementation results are reported separately and are not hardware-deployment
claims.

| Boundary | Flow | Clock | WNS | Resources |
| :--- | :--- | ---: | ---: | :--- |
| 512-bit parser pipeline | OOC | 500.0 MHz | `+0.030 ns` | 12,278 LUTs, 12,700 registers |
| Redundant A/B packet-to-book | OOC | 363.6 MHz | `+0.009 ns` | 28,096 LUTs, 27,625 registers, 17 BRAM |
| Packet-to-intent | OOC | 400.0 MHz | `+0.014 ns` | 27,474 LUTs, 27,307 registers, 8.5 BRAM |
| Packet-to-Soup/OUCH | OOC | 322.4 MHz | `+0.012 ns` | 33,210 LUTs, 35,049 registers, 8.5 BRAM |
| Packet-to-Soup/OUCH compact harness | Routed | 322.4 MHz | `+0.075 ns` | 26,227 LUTs, 30,185 registers, 8.5 BRAM |
| Generated CAUI-4 CMAC plus parser | Routed | 322.4 MHz | `+0.071 ns` | 17,074 LUTs, 18,502 registers, 8.5 BRAM |

The generated CMAC design links with zero black boxes, routes without routing
errors, meets timing, and has a clean final DRC report. Bitstream generation is
not claimed: the available `cmac_usplus` entitlement reports
`Design_Linking`, so Vivado rejects the encrypted CMAC cell during
`write_bitstream`.

See `docs/timing_matrix.md` for the complete result set and
`docs/cmac_integration.md` for the generated-IP boundary.

## Repository Guide

```text
rtl/            Synthesizable parser, feed, book, risk, and gateway RTL
verification/   SystemVerilog benches, cocotb tests, and packet vectors
tools/          Python models, vector generation, and Vivado flows
docs/           Architecture, protocol, register, timing, and integration notes
filelist.f      Common synthesizable RTL file list
```

Key entry points:

- `rtl/market_parser_512_pipeline.sv`: integrated parallel parser.
- `rtl/market_parser_100g_ab_multi_strategy_top.sv`: redundant-feed guarded
  packet-to-book path.
- `rtl/market_parser_100g_cmac_axis_decision_top.sv`: packet-to-intent path.
- `rtl/market_parser_100g_cmac_axis_egress_top.sv`: lifecycle and final-risk
  path.
- `rtl/market_parser_100g_ouch5_top.sv`: complete packet-to-Soup/OUCH path.
- `rtl/market_parser_moldudp64_ab_arbiter.sv`: redundant-feed merger.
- `rtl/market_parser_order_latency_monitor.sv`: passive latency scoreboard.
- `tools/exchange_simulator.py`: deterministic and adversarial venue model.
- `verification/run_questa.do`: complete RTL regression.

Start with `docs/README.md` for the documentation map.

## Vivado Flows

The scripts use relative paths and environment variables. Generated projects,
reports, checkpoints, IP products, and bitstreams belong under ignored local
directories.

```bash
source <vivado-install>/settings64.sh
MARKET_PARSER_PARTS="xcu50-fsvh2104-2-e" \
MARKET_PARSER_TOPS="market_parser_512_pipeline" \
MARKET_PARSER_PERIODS="2.100 2.000" \
bash tools/run_hft_ooc_matrix.sh
```

Use `tools/run_hft_impl_matrix.sh` for routed harnesses and
`tools/summarize_vivado_reports.py` for compact report summaries.

## Scope

The repository contains source-level RTL, verification, and reproducible
Vivado flows. It does not contain exchange credentials, captured proprietary
market data, generated vendor IP, machine-specific paths, or programming
artifacts. The Soup interface operates above TCP; Ethernet/TCP reliability,
socket establishment, host software, and live exchange connectivity remain
outside the implemented boundary.
