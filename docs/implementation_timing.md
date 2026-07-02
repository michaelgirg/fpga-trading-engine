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

The first routed target should be `market_parser_100g_strategy_impl_harness` at
`3.102 ns` on `xcu50-fsvh2104-2-e`. The harness keeps
`market_parser_100g_strategy_top` internal, drives a generated replay packet
through its CMAC-style RX stream, and exposes only `clk`, `rst`, and a compact
status hash as package pins. That avoids meaningless IO-placement failure from
trying to assign every debug counter and 512-bit stream lane to package pins.
If it passes, run `2.500 ns` and `2.350 ns` as stress points. If it fails,
inspect `post_place_timing_summary.rpt` and `timing_summary.rpt` before
changing RTL.

This is still an RTL implementation flow, not a finished Alveo shell. The CMAC
probe is intentionally separate because the actual IP wrapper depends on the
available Vivado IP definition, board shell, GT placement, reference clocks,
resets, and management interface.

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
