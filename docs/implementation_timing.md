# Implementation Timing Flow

## Purpose

OOC synthesis is the fast architecture gate. Routed implementation is the
stronger timing check because it includes placement, routing, clocks, and
physical optimization. The repository provides non-project Vivado flows for
both without checking generated artifacts into source control.

## Scripts

- `tools/run_vivado_ooc.tcl`: synthesize one selected top out of context.
- `tools/run_hft_ooc_matrix.sh`: sweep parts, tops, and periods and emit a TSV
  summary.
- `tools/run_vivado_impl.tcl`: synthesize, optimize, place, optionally run
  physical optimization, route, and report one compact harness.
- `tools/run_hft_impl_matrix.sh`: sweep routed harness configurations.
- `tools/run_vivado_cmac_ip_impl.tcl`: generate and synthesize CMAC IP, link
  the checkpoint, reject black boxes, apply optional board constraints, and
  run implementation.
- `tools/summarize_vivado_reports.py`: extract timing and utilization from a
  completed report directory.

All scripts use repository-relative paths and environment variables. Vivado
projects, checkpoints, reports, IP products, and bitstreams are ignored.

## Compact Harnesses

Implementation harnesses keep the functional datapath internal and expose only
clock, reset, physical CMAC pins where applicable, and a compact status
signature. This prevents package-I/O pressure from dominating a timing probe
that would otherwise expose every 512-bit lane and debug counter.

The maintained routed boundary is `market_parser_100g_ouch5_impl_harness`. It
includes the CMAC AXIS burst buffer, packet filter, ITCH parser, guarded books,
decision logic, lifecycle state, final risk, OUCH encoding and decoding, Soup
logical-session control, deterministic venue feedback, and passive latency
telemetry.

## Routed Results

All rows target `xcu50-fsvh2104-2-e` at 3.102 ns in Vivado 2024.2.

| Boundary | WNS | TNS | WHS | LUTs | Registers | BRAM |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| Packet-to-book | `0.000 ns` | `0.000 ns` | not recorded | 18,492 | 21,194 | 0 |
| CMAC AXIS guarded feed | `+0.176 ns` | `0.000 ns` | `+0.011 ns` | 23,156 | 29,607 | 8.5 |
| Packet-to-intent | `+0.103 ns` | `0.000 ns` | `+0.011 ns` | 20,142 | 22,515 | 8.5 |
| Packet-to-lifecycle | `+0.110 ns` | `0.000 ns` | `+0.011 ns` | 21,300 | 23,721 | 8.5 |
| Packet-to-final-risk | `+0.047 ns` | `0.000 ns` | `+0.010 ns` | 21,171 | 24,172 | 8.5 |
| Packet-to-Soup/OUCH | `+0.075 ns` | `0.000 ns` | `+0.010 ns` | 26,227 | 30,185 | 8.5 |
| Generated CAUI-4 CMAC plus parser | `+0.071 ns` | `0.000 ns` | `+0.011 ns` | 17,074 | 18,502 | 8.5 |

The generated-CMAC row links zero black boxes, is fully routed with zero route
errors, and has a clean final DRC report. Bitstream generation is excluded
because the installed `cmac_usplus` entitlement is limited to
`Design_Linking`.

## Running A Matrix

```bash
source <vivado-install>/settings64.sh

MARKET_PARSER_PARTS="xcu50-fsvh2104-2-e" \
MARKET_PARSER_TOPS="market_parser_100g_ouch5_impl_harness" \
MARKET_PARSER_PERIODS="3.102" \
MARKET_PARSER_SYNTH_DIRECTIVE="RuntimeOptimized" \
MARKET_PARSER_PLACE_DIRECTIVE="Explore" \
MARKET_PARSER_ROUTE_DIRECTIVE="Explore" \
MARKET_PARSER_PHYS_OPT_DIRECTIVE="Explore" \
bash tools/run_hft_impl_matrix.sh
```

Each run writes:

- `post_synth_timing_summary.rpt`
- `post_place_timing_summary.rpt`
- `timing_summary.rpt`
- `utilization.rpt`
- `clock_utilization.rpt`
- `route_status.rpt`
- `drc.rpt`
- `post_route.dcp`

The matrix summary uses the post-route `timing_summary.rpt`.

## Regression Policy

Run the 38-configuration Questa regression and Python model tests before a
timing sweep. Rerun the 500 MHz parser-core OOC check when parser internals
change, and rerun the 322.4 MHz complete routed harness when changes affect the
ingress buffer, feed guards, books, decisions, lifecycle, risk, OUCH, Soup, or
latency telemetry.
