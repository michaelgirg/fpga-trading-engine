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

## Measured Routed Result

Vivado 2024.2 post-route implementation on the school U50-class target closes
the 100G user-clock class after adding a CMAC RX register slice before payload
stripping:

| Part | Top | Period | Frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_impl_harness` | `3.102 ns` | 322.4 MHz | `0.000 ns` | `0.000 ns` | `18492 / 871680 (2.12%)` | `21194 / 1743360 (1.22%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_impl_harness` | `3.102 ns` | 322.4 MHz | `0.022 ns` | `0.000 ns` | `19418 / 871680 (2.23%)` | `22531 / 1743360 (1.29%)` | Meets |
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
MoldUDP64/ITCH parser pipeline, event buffering, and top-of-book strategy path,
while still avoiding unrealistic package-pin pressure from debug buses.

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
`0.097 ns`, then misses `2.500 ns` / 400.0 MHz by `0.153 ns`. The next
implementation-realism step is replacing the source-only wrapper boundary with
the generated CMAC IP, board clock/reset wiring, and constraints, then rerunning
routed implementation.

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
