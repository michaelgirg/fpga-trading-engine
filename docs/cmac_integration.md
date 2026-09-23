# CMAC Integration

## Data Path

The generated UltraScale+ CMAC produces raw Ethernet frames. The parser expects
MoldUDP64 byte 0 on AXIS lane 0, so the owned RTL boundary is:

```text
CAUI-4 CMAC RX AXIS
  -> market_parser_cmac_axis_rx_bridge
  -> market_parser_udp_payload_strip
  -> market_parser_512_pipeline
  -> feed, book, decision, risk, and order logic
```

`market_parser_udp_payload_strip` accepts Ethernet II, IPv4 without options,
and UDP packets for a configured destination port. It strips the 42-byte
header, realigns the payload, and reports accepted, dropped, malformed, and
payload counters. VLAN, IPv6, IP options, and fragmentation are outside this
filter.

## AXIS Contract

The generated RX interface exposes:

- `rx_axis_tvalid`
- `rx_axis_tdata[511:0]`
- `rx_axis_tkeep[63:0]`
- `rx_axis_tlast`
- `rx_axis_tuser`
- no `rx_axis_tready`

`market_parser_cmac_axis_rx_bridge` therefore buffers complete packets before
presenting an internal ready/valid stream. If storage fills, it rolls back the
current packet and emits a loss event. The guarded book path immediately
invalidates the feed, clears bounded state, and requires replay plus explicit
activation before quote output resumes.

The production source configuration uses a 64-beat CMAC burst buffer and a
32-beat parser packet store. Regression covers two contiguous 1462-byte frames
containing 200 ITCH messages with no idle RX cycle.

## Clock And Reset

The parser runs in the 322.4 MHz-class CMAC user-clock domain with a 3.102 ns
constraint. Wide RX data, payload-strip metadata, and parser handoff have
intentional register boundaries. Any external management clock requires a CDC
boundary; reset must be synchronized into the CMAC user-clock domain.

## Generated IP Profile

The checked-in scripts target `xilinx.com:ip:cmac_usplus:3.1` on
`xcu50-fsvh2104-2-e` with this resolved profile:

| Property | Value |
| :--- | :--- |
| `CONFIG.USER_INTERFACE` | `AXIS` |
| `CONFIG.ENABLE_AXIS` | `1` |
| `CONFIG.CMAC_CAUI4_MODE` | `1` |
| `CONFIG.NUM_LANES` | `4x25` |
| `CONFIG.GT_TYPE` | `GTY` |
| `CONFIG.GT_REF_CLK_FREQ` | `161.1328125` |

The generated template has four GT TX/RX lanes and a 512-bit AXIS RX data
path with 64-bit `tkeep`.

Probe and generate the IP with:

```bash
vivado -mode batch -source tools/probe_cmac_usplus_config.tcl \
  -tclargs xcu50-fsvh2104-2-e cmac_usplus_0 AXIS 4x25

vivado -mode batch -source tools/build_cmac_usplus_axis_ip.tcl \
  -tclargs xcu50-fsvh2104-2-e cmac_usplus_0
```

Generated `.xci`, wrappers, templates, constraints, projects, and checkpoints
stay under ignored `build/` directories. Only the reproducible scripts and
source wrappers are tracked.

## Integration Tops

- `market_parser_100g_cmac_axis_strategy_top`: source-only CMAC AXIS bridge to
  the single-symbol packet-to-book path.
- `market_parser_100g_cmac_axis_multi_strategy_top`: guarded four-symbol path
  with feed-loss, session, sequence, timeout, rebuild, and activation control.
- `market_parser_100g_cmac_ip_strategy_top`: generated CMAC instance connected
  to the parser-side AXIS integration.
- `market_parser_100g_cmac_ip_impl_harness`: compact board implementation top
  retaining GT and reference-clock pins while folding observability into a
  small status signature.

The generated-IP implementation flow synthesizes the CMAC checkpoint first,
links it into the top, rejects black boxes, and then runs optimize, place,
physical optimization, route, timing, utilization, route-status, and DRC
reports:

```bash
vivado -mode batch -source tools/run_vivado_cmac_ip_impl.tcl \
  -tclargs market_parser_100g_cmac_ip_impl_harness \
  xcu50-fsvh2104-2-e 3.102 RuntimeOptimized Explore Explore Explore 8
```

## U50 Board Profile

The optional `au50` profile applies the board mapping used by the checked-in
implementation flow:

- CMAC hard block `CMACE4_X0Y4`.
- GT channels `GTYE4_CHANNEL_X0Y28` through `X0Y31`.
- GT common `GTYE4_COMMON_X0Y7`.
- 161.1328125 MHz QSFP reference clock on `N36/N37`.
- 100 MHz management clock on `G17/G16`.
- PCIe reset on `AW27`, status LED on `E18`, and grounded HBM `CATTRIP` on
  `J18`.

```bash
MARKET_PARSER_BOARD_PROFILE=au50 \
MARKET_PARSER_WRITE_BITSTREAM=1 \
vivado -mode batch -source tools/run_vivado_cmac_ip_impl.tcl \
  -tclargs market_parser_100g_cmac_ip_impl_harness \
  xcu50-fsvh2104-2-e 3.102 RuntimeOptimized Explore Explore Explore 8
```

## Measured Result

The board-constrained CAUI-4 design links the generated CMAC with zero black
boxes and completes placement and routing at the native user clock:

| Part | Period | WNS | TNS | WHS | LUTs | Registers | BRAM | DSPs |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `xcu50-fsvh2104-2-e` | `3.102 ns` | `+0.071 ns` | `0.000 ns` | `+0.011 ns` | 17,074 | 18,502 | 8.5 | 0 |

The final reports show 1,312 LUTs as memory, zero routing errors, and no DRC
errors, critical warnings, or warnings.

## License Boundary

`report_ip_status -license_status` reports `Design_Linking` for
`cmac_usplus`. That entitlement permits IP generation, synthesis, linking,
placement, and routing, but Vivado rejects the encrypted CMAC cell during
`write_bitstream`. Fresh regeneration of output products and netlists produces
the same result.

Accordingly, the repository claims a generated, fully routed, timing-clean,
DRC-clean CMAC integration, not a bitstream or programmed card. Once a
bitstream-authorized entitlement is available, regenerate the CMAC output
products and rerun the same board-profile flow before hardware replay.
