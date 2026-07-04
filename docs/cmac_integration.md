# CMAC Integration Notes

## Current Boundary

`market_parser_512_pipeline` expects a 512-bit AXI-stream-style packet payload
where byte 0 is the first byte of the MoldUDP64 header. A raw 100G CMAC RX
stream usually begins with an Ethernet frame, so a real board shell needs a
small packet pre-parser before this core. The repo now includes a first-pass
CMAC-facing shell for that boundary:

```text
100G CMAC RX
    |
    v
market_parser_udp_payload_strip
    Ethernet II / IPv4 / UDP filter and 42-byte header strip
    |
    v
MoldUDP64 payload stream, 512-bit AXI style
    |
    v
market_parser_512_system
    |
    v
event FIFO / AXI-Lite observability / strategy logic / DMA
```

The integration wrapper is `market_parser_100g_cmac_system`. It accepts a
512-bit raw RX stream, filters for a configured UDP destination port, realigns
the UDP payload so MoldUDP64 byte 0 lands on parser lane 0, and exposes simple
accepted/drop/header-error/payload counters.

The raw CMAC stream is registered before the header-strip block and again before
the parser system. Those slices are intentional implementation boundaries:
they keep the wide CMAC-facing stream local to the packet filter and avoid a
single routed path from board-shell RX flops through UDP realignment into the
payload FIFO.

The UDP payload-strip block also stages the accepted RX beat and predecodes the
valid-byte/header fields before writing its payload FIFO. That stage is a timing
boundary for the generated CMAC AXIS wrapper path, where Vivado otherwise built
a long path from RX `tkeep` through byte-count/header logic into the payload
FIFO write controls.

The current filter intentionally targets the common low-latency feed shape:
Ethernet II, IPv4 without options, UDP, no VLAN tag, and no IP fragmentation.
VLAN, IPv6, IP options, RSS/flow steering, checksum policy, and full board
control-plane integration remain board-shell work.

## Stream Mapping

| Parser signal | CMAC-shell source |
| :--- | :--- |
| `s_axis_rx_tvalid` | Payload beat valid after Ethernet/IP/UDP filter accepts the packet. |
| `s_axis_rx_tready` | Backpressure into the payload FIFO or skid buffer, if the selected shell supports ready. |
| `s_axis_rx_tdata[511:0]` | UDP payload bytes, little-lane packed the same way as the testbenches. |
| `s_axis_rx_tkeep[63:0]` | Valid payload byte lanes on the beat. |
| `s_axis_rx_tlast` | Last beat of the UDP payload, not necessarily the Ethernet frame. |
| `s_axis_rx_tuser_bad_frame` | CMAC/FCS/error indication mapped onto the first payload beat or carried beside the packet. |

`market_parser_udp_payload_strip` includes a small payload FIFO and backpressures
the incoming ready/valid stream when it fills. If the selected CMAC example
design cannot be backpressured directly, add a larger RX FIFO or vendor AXI
stream buffering block ahead of this shell.

## Clocking And Reset

The measured 3.102 ns target corresponds to the common 322 MHz-class 512-bit
100G CMAC user-clock regime. In a board design, the parser should run in the
same clock domain as the post-CMAC payload stream unless the shell already
provides a CDC FIFO. Reset should be synchronized into that domain, and sticky
error/counter state should remain accessible through the AXI-Lite management
plane.

Out-of-context synthesis on `xcu50-fsvh2104-2-e` shows
`market_parser_100g_cmac_system` meeting this 3.102 ns target with WNS
`0.265 ns`. Faster stress sweeps from 2.2 ns down to 1.95 ns do not close for
the full header-strip shell; those frequencies are parser-core stress targets
rather than required 100G CMAC shell targets.

The routed implementation harness for the full strategy path also closes this
3.102 ns target post-route on `xcu50-fsvh2104-2-e` with WNS `0.000 ns` and TNS
`0.000 ns`. That harness keeps the full packet-to-book logic internal and uses
a compact board-like IO surface; it is implementation evidence for the RTL
path, not a replacement for actual CMAC IP and board constraints.

The school Vivado 2024.2 IP catalog for `xcu50-fsvh2104-2-e` includes the
UltraScale+ CMAC IP needed for a real board shell:

- `xilinx.com:ip:cmac_usplus:3.1`
- `xilinx.com:ip:cmac:2.6`
- `xilinx.com:ip:dcmac:2.5`
- related Ethernet IP such as `xxv_ethernet`, `l_ethernet`, and
  `ethernet_1_10_25g`

For the U50-class UltraScale+ target, `cmac_usplus:3.1` is the likely next IP
boundary. Use `tools/probe_cmac_usplus_config.tcl` to dump the exact core
properties and generated instantiation template from the school Vivado install
before wiring a wrapper.

## CMAC UltraScale+ Probe Result

The July 3, 2026 school Vivado 2024.2 probe successfully created
`cmac_usplus:3.1` for `xcu50-fsvh2104-2-e` and generated instantiation
templates. The default IP configuration is important:

- `CONFIG.USER_INTERFACE = LBUS`
- `CONFIG.ENABLE_AXIS = 0`
- `CONFIG.CLOCKING_MODE = Asynchronous`
- `CONFIG.GT_TYPE = GTY`
- `CONFIG.GT_REF_CLK_FREQ = 156.25`
- `CONFIG.NUM_LANES = 10x10`
- `CONFIG.INCLUDE_RS_FEC = 0`
- `CONFIG.RX_FRAME_CRC_CHECKING = Enable FCS Stripping`
- `CONFIG.RX_MAX_PACKET_LEN = 9600`

The AXIS-requested probe was also accepted:

- `CONFIG.USER_INTERFACE = AXIS`
- `CONFIG.ENABLE_AXIS = 1`
- generated `cmac_usplus_0.veo`
- generated `cmac_usplus_0.vho`

Use this command shape to regenerate the AXIS template:

```bash
vivado -mode batch -source tools/probe_cmac_usplus_config.tcl \
  -tclargs xcu50-fsvh2104-2-e cmac_usplus_0 AXIS
```

The generated AXIS template is the preferred production wrapper boundary for
the next integration pass. If a selected board shell later exposes only LBUS,
add a thin LBUS-to-AXI-stream receive adapter ahead of
`market_parser_100g_cmac_system`; the school U50 IP itself can produce an AXIS
boundary.

The generated AXIS RX port list has:

- `rx_axis_tvalid`
- `rx_axis_tdata[511:0]`
- `rx_axis_tkeep[63:0]`
- `rx_axis_tlast`
- `rx_axis_tuser`
- no `rx_axis_tready`

Because the real CMAC RX stream cannot be backpressured, the repo now includes
`market_parser_cmac_axis_rx_bridge`. It buffers complete CMAC RX packets before
presenting them to the existing ready/valid shell, and drops a whole current
packet if the buffer fills so the parser never sees a truncated frame. The
wrapper `market_parser_100g_cmac_axis_strategy_top` is the owned RTL boundary
for wiring the generated CMAC AXIS template into the packet-to-book strategy
path. The default bridge depth is 16 beats to match the current
`PACKET_BEATS_MAX` timing target; larger RX buffers should be swept separately
once the board traffic profile and acceptable overflow policy are fixed.

## CMAC AXIS Boundary Timing

After staging the UDP payload-strip predecode path, the CMAC AXIS strategy
wrapper closes OOC on the school U50-class target at the 3.102 ns / 322 MHz
100G user-clock target:

| Part | Top | Period | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_strategy_top` | `3.102 ns` | `0.449 ns` | `0.000 ns` | `23965 / 871680 (2.75%)` | `23709 / 1743360 (1.36%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_strategy_top` | `2.750 ns` | `0.097 ns` | `0.000 ns` | `24146 / 871680 (2.77%)` | `23709 / 1743360 (1.36%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_strategy_top` | `2.500 ns` | `-0.153 ns` | `-399.967 ns` | `24150 / 871680 (2.77%)` | `23713 / 1743360 (1.36%)` | Stress miss |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_strategy_top` | `2.350 ns` | `-0.303 ns` | `-1015.845 ns` | `24150 / 871680 (2.77%)` | `23713 / 1743360 (1.36%)` | Stress miss |

This pass covers the source-only CMAC AXIS RX bridge, UDP strip/realignment,
MoldUDP64/ITCH parser pipeline, event buffering, and top-of-book strategy path.
The same boundary closes through 2.750 ns / 364 MHz and misses 2.500 ns /
400 MHz by 0.153 ns. It is still an OOC RTL result, not a placed vendor-CMAC
board design, but it is the right source-level boundary for the generated
`cmac_usplus` AXIS template.

## Minimum Board Shell

A first real hardware integration should include:

- CMAC example design or board shell with RX statistics exposed.
- AXIS CMAC RX template wiring into `market_parser_100g_cmac_axis_strategy_top`,
  or an LBUS-to-AXI-stream adapter if a later board shell exposes only LBUS.
- The checked-in `market_parser_100g_cmac_system` shell for Ethernet/IP/UDP
  filtering and MoldUDP64 payload realignment.
- Payload FIFO sizing review for the selected CMAC backpressure behavior.
- The existing `market_parser_512_system` block for parser event buffering and
  AXI-Lite observability.
- AXI-Lite or debug-register access for parser enable, counters, FIFO level,
  bad-frame count, and sticky error flags.
- XDC constraints for the CMAC user clock, parser clock, resets, and any CDC
  paths.

## Validation Plan

1. Loop generated MoldUDP64/ITCH packets through the header-strip block in
   simulation and compare parser events against `verification/vectors`.
2. Run `market_parser_100g_cmac_system_tb` to verify valid UDP feed traffic
   reaches the parser and wrong-port UDP frames are dropped before parsing.
3. Run Vivado OOC synthesis for `market_parser_100g_cmac_system` at the 3.102 ns
   100G CMAC user-clock target.
4. Run the dense tiny-message, mixed-message, malformed, and backpressure
   regressions with the shell attached.
5. Use `tools/probe_cmac_ip.tcl` to record the CMAC/100G IP definitions visible
   in the selected Vivado install.
6. Keep `market_parser_100g_cmac_axis_strategy_top` in the OOC matrix as the
   no-backpressure CMAC RX boundary regression before adding the generated
   vendor IP.
7. Keep `tools/run_hft_impl_matrix.sh` as the routed RTL harness regression for
   the selected school-supported part.
8. Replace the harness boundary with actual CMAC IP, board clocks, resets, and
   constraints.
9. Only after board-constrained timing closes, add board traffic tests using replayed UDP payloads
   and verify counters/events through the management plane.

The key claim should stay precise: the repo now has a 512-bit parser
architecture that closes OOC on a realistic U50-class target, a routed RTL
implementation harness that closes the 100G user-clock class, and a CMAC-facing
Ethernet/IP/UDP ingress shell. It is not yet a finished trading NIC.
