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

An earlier source-only CMAC AXIS routed harness closes the same target
post-route with WNS `0.176 ns`, TNS `0.000 ns`, WHS `0.011 ns`, 23,156 LUTs,
and 29,607 registers. The current complete source-level routed proof is the
packet-to-Soup/OUCH harness: it includes the 64-beat CMAC burst buffer and
closes 3.102 ns with WNS `0.075 ns`, including passive order telemetry and the
registered Soup receive boundary. Generated vendor-IP implementation is
reported separately below.

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

Before changing the proven wrapper from Vivado's default `10x10` lane profile,
probe the production-shaped `4x25` profile and inspect its generated GT port
widths:

```bash
vivado -mode batch -source tools/probe_cmac_usplus_config.tcl \
  -tclargs xcu50-fsvh2104-2-e cmac_usplus_0 AXIS 4x25
```

The probe exits nonzero if the requested interface or lane profile cannot be
applied. For `4x25`, it first enables `CONFIG.CMAC_CAUI4_MODE=1` and then
applies `CONFIG.NUM_LANES=4x25`, matching the CMAC property's dependency order.
The production wrapper was kept at `10x10` until this probe confirmed the
`4x25` GT interface and resolved CMAC properties.

The July 13, 2026 school Vivado 2024.2 CAUI-4 probe completed successfully:

- `CONFIG.CMAC_CAUI4_MODE = 1`
- `CONFIG.NUM_LANES = 4x25`
- `CONFIG.GT_TYPE = GTY`
- `CONFIG.GT_REF_CLK_FREQ = 161.1328125`
- `CONFIG.USER_INTERFACE = AXIS`
- GT TX/RX ports are `[3:0]`
- RX AXIS remains 512-bit data with 64-bit `tkeep`

The generator, OOC flow, full implementation flow, and generated-IP wrappers
therefore use CAUI-4 as the production profile. The earlier `10x10` routed run
remains valid part-level integration evidence for the previous default profile;
the CAUI-4 results below are the current production-profile evidence.

The subsequent CAUI-4 declaration-wrapper OOC run also completed successfully
at 3.102 ns. The generated CMAC stub confirmed four-bit GT TX/RX,
`gt_rxrecclkout`, and `gt_powergoodout` ports plus a 12-bit loopback input. The
512-bit AXIS parser path reported WNS `0.449 ns`, TNS `0.000 ns`, 23966 LUTs,
23709 registers, and no BRAM/DSP usage. The black-box and scoped-XDC warnings
in this OOC check are expected because it deliberately reads only the generated
CMAC declaration; the full implementation flow must still report zero black
boxes before placement.

The full CAUI-4 implementation run then synthesized the actual CMAC checkpoint,
linked it with zero black boxes, and completed placement and routing:

| Part | Top | Profile | Period | WNS | TNS | LUTs | Registers | Black boxes | Status |
| :--- | :--- | :--- | ---: | ---: | ---: | :--- | :--- | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_ip_impl_harness` | CAUI-4 `4x25` | `3.102 ns` | `0.007 ns` | `0.000 ns` | `21128 / 871680 (2.42%)` | `25324 / 1743360 (1.45%)` | `0` | Routed, timing met |

The result has only 0.007 ns of setup margin, so the claim stays at the native
322 MHz CMAC user-clock target. The sole critical warning is still
`DRC AVAL-326`: the generic part-level flow needs the selected board's
reference-clock-buffer `LOC` and matching CMAC/GT constraints before bitstream
or hardware claims.

Before adding a manual `LOC`, run the CAUI-4 placement probe:

```bash
vivado -mode batch -source tools/probe_cmac_usplus_placement.tcl \
  -tclargs xcu50-fsvh2104-2-e cmac_usplus_0

cat build/cmac_placement_probe/xcu50-fsvh2104-2-e/cmac_usplus_placement.txt
```

The report records the current and Vivado-legal `CMAC_CORE_SELECT`,
`GT_GROUP_SELECT`, `GT_LOCATION`, per-lane GT locations, candidate hard-block
sites, and placement-related lines from the generated CMAC XDC files. These
are part-valid choices only. The final core, GT group, and reference-clock
buffer `LOC` must match the selected U50 shell and its physical QSFP wiring.

The first probe showed that generic part-level generation selected
`CMACE4_X0Y3`, GT group `X0Y28~X0Y31`, and lanes `X0Y28` through `X0Y31`.
The official Xilinx OpenNIC U50 configuration uses the same GT group and lanes
but selects `CMACE4_X0Y4`; its U50 constraints map the 161.1328125 MHz QSFP
reference clock to package pins `N36` (P) and `N37` (N). The implementation
script exposes this exact mapping as the opt-in `au50` board profile:

```bash
MARKET_PARSER_BOARD_PROFILE=au50 \
MARKET_PARSER_WRITE_BITSTREAM=1 \
vivado -mode batch -source tools/run_vivado_cmac_ip_impl.tcl \
  -tclargs market_parser_100g_cmac_ip_impl_harness \
  xcu50-fsvh2104-2-e 3.102 RuntimeOptimized Explore Explore Explore 8
```

The profile also matches OpenNIC's enabled RS-FEC and CMAC pipeline-register
settings, verifies the resolved core and lane properties before synthesis, and
writes `cmac_hard_block_placement.rpt` after routing. A board-qualified pass
requires zero black boxes, timing met, and a clean final DRC report.

The final `au50` implementation run resolved the hard-block placement exactly
as intended: `CMACE4_X0Y4`, `GTYE4_CHANNEL_X0Y28` through `X0Y31`, and
`GTYE4_COMMON_X0Y7` for the reference-clock buffer. The complete generated
CMAC plus parser design linked zero black boxes, placed and routed fully, and
met the 3.102 ns / 322 MHz target with WNS `0.071 ns`, TNS `0.000 ns`, WHS
`0.011 ns`, and THS `0.000 ns`. Post-route utilization was 17,074 LUTs,
18,502 registers, 8.5 BRAM tiles, 1,312 LUTs as memory, and zero DSPs.

The board shell uses the 100 MHz CMC differential clock on `G17/G16`, PCIe
reset on `AW27`, a one-bit status LED on `E18`, grounded HBM `CATTRIP` on
`J18`, and the 161.1328125 MHz QSFP reference clock on `N36/N37`. The CMAC TX
user clock drives the parser at the native 322 MHz rate, DRP is tied off, and
the RS-FEC controls select correction and IEEE error indication. This removed
the earlier `AVAL-326`, `PPURQ-1`, `NSTD-1`, and `UCIO-1` findings. The final
route report contains zero routing errors, and the final DRC summary contains
no errors, critical warnings, or warnings.

With `MARKET_PARSER_WRITE_BITSTREAM=1`, Vivado proceeded through that complete
implementation and then stopped at the encrypted CMAC bitstream-license gate:
`i_cmac_usplus_0_top (<encrypted cellview>)` was not permitted for bitstream
generation. The U50 implementation/device license was acquired, and
`report_ip_status -license_status` showed `Design_Linking` for `cmac_usplus`.
The same failure remained after a fresh source directory regenerated the CMAC
output products, synthesis checkpoint, and integrated netlist under the newly
installed partial license. This is not a synthesis, placement, routing,
timing, pin, stale-netlist, or DRC failure; the installation needs a
bitstream-authorized CMAC entitlement before the same run can emit
`market_parser_100g_cmac_ip_impl_harness_au50.bit` and move to hardware
programming.

Use this command shape when moving from a probe to actual generated vendor IP
artifacts:

```bash
vivado -mode batch -source tools/build_cmac_usplus_axis_ip.tcl \
  -tclargs xcu50-fsvh2104-2-e cmac_usplus_0
```

The generator creates the AXIS-mode `cmac_usplus:3.1` IP under
`build/cmac_usplus_axis_ip/<part>/`, applies the required AXIS configuration,
generates synthesis/simulation/template targets, and writes
`cmac_usplus_axis_manifest.txt`. The generated `.xci`, wrapper, template, and
project files stay under `build/` and are intentionally not checked in; the
checked-in artifact is the repeatable Vivado script plus this manifest-driven
integration note.

The July 4, 2026 school Vivado 2024.2 generator run on
`xcu50-fsvh2104-2-e` completed successfully:

- `validate_ip completed`
- `instantiation_template: ok`
- `synthesis: ok`
- `simulation: ok`
- `export_ip_user_files: ok`
- generated `cmac_usplus_0.xci`, `cmac_usplus_0.v`,
  `cmac_usplus_0.veo`, `cmac_usplus_0.vho`, and CMAC/GT XDC files

Vivado emitted repeated `Design_Linking` license warnings for the CMAC IP, and
the IP generation flow completed. That level is sufficient for the observed
generation, synthesis, and routed implementation flow, but it did not pass the
final encrypted-cell bitstream checkpoint.

`market_parser_100g_cmac_ip_strategy_top` is the first checked-in wrapper around
that generated IP boundary. It instantiates `cmac_usplus_0`, exposes the GT
pins, reference clock, user clocks, key RX status, DRP readback, quote output,
and parser counters, then feeds `rx_axis_tvalid/tdata/tkeep/tlast/tuser` into
`market_parser_100g_cmac_axis_strategy_top`. The transmit AXIS path is held
idle in this receive-focused integration pass; board-level control, real TX
policy, management-plane access to CMAC registers, and physical pin constraints
remain board-shell work.

Use this command shape for the first OOC synthesis check of the generated CMAC
IP plus parser receive path:

```bash
vivado -mode batch -source tools/run_vivado_cmac_ip_ooc.tcl \
  -tclargs market_parser_100g_cmac_ip_strategy_top xcu50-fsvh2104-2-e 3.102 RuntimeOptimized
```

This flow creates the AXIS-mode CMAC IP inside the Vivado project, reads the
generated CMAC declaration stub, reads the parser RTL, synthesizes
`market_parser_100g_cmac_ip_strategy_top`, and writes `ip_status.rpt`,
`utilization.rpt`, `timing_summary.rpt`, and an integration manifest under
`build/vivado_cmac_ip_ooc/`. It validates the checked-in wrapper against the
generated IP port list; full CMAC internals, GT placement, and physical pin
constraints remain part of the board implementation step.

The July 4, 2026 school OOC run for
`market_parser_100g_cmac_ip_strategy_top` completed synthesis successfully with
the generated CMAC declaration stub visible:

| Part | Top | Period | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_ip_strategy_top` | `3.102 ns` | `0.449 ns` | `0.000 ns` | `23966 / 871680 (2.75%)` | `23709 / 1743360 (1.36%)` | Meets |

This result proves the checked-in CMAC-IP wrapper matches the generated AXIS
CMAC port list and preserves the parser-side 3.102 ns timing. Vivado reports
`cmac_usplus_0` as a black box in this OOC flow, so this is not yet routed
timing for the full CMAC/GT hard-IP implementation.

The next implementation probe replaces that declaration-only check with the
CMAC IP's generated synthesis checkpoint:

```bash
vivado -mode batch -source tools/run_vivado_cmac_ip_impl.tcl \
  -tclargs market_parser_100g_cmac_ip_impl_harness \
  xcu50-fsvh2104-2-e 3.102 RuntimeOptimized Explore Explore Explore 8
```

`run_vivado_cmac_ip_impl.tcl` creates and validates the AXIS CMAC, launches its
dedicated synthesis run, launches integrated top-level synthesis, and refuses
to continue if any black-box cell remains. A clean synthesis then proceeds
through optimize, place, physical optimization, and route. Reports and
checkpoints are written under `build/vivado_cmac_ip_impl/`. The implementation
harness retains the CMAC GT/refclock pins but folds the wide quote, AXI-Lite,
and counter interfaces into a 32-bit status signature, avoiding artificial
package-I/O overutilization. This is a part-level integration probe; a
board-qualified result still requires the selected card's CMAC location,
GT/refclock pins, and board XDC.

The July 13, 2026 school Vivado 2024.2 implementation run completed that
part-level probe:

| Part | Top | Period | WNS | TNS | LUTs | Registers | Black boxes | Status |
| :--- | :--- | ---: | ---: | ---: | :--- | :--- | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_ip_impl_harness` | `3.102 ns` | `0.044 ns` | `0.000 ns` | `21023 / 871680 (2.41%)` | `27391 / 1743360 (1.57%)` | `0` | Routed, timing met |

The run synthesized `cmac_usplus_0`, linked its generated checkpoint into the
parser top, passed the explicit zero-black-box check, and completed placement
and routing. Vivado reported `DRC AVAL-326` because the generated CMAC
`IBUFDS_GTE4` reference-clock buffer has no board-specific `LOC`. That warning
does not invalidate the part-level timing result, but it prevents a hardware
claim: the next shell must supply the selected U50 card's CMAC location,
GT/refclock pin assignments, and complete board constraints.

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

`market_parser_100g_cmac_axis_multi_strategy_top` uses the same packet bridge
for the guarded multi-symbol book bank. It exposes feed health, session-change,
end-of-session, sequence-gap,
packet-loss, liveness-timeout, ingress, and book telemetry while keeping
generated CMAC IP out of the source-level boundary.
`market_parser_100g_cmac_axis_impl_harness` retains this hierarchy for routed
timing with a compact external I/O surface.

The bridge management registers expose current FIFO occupancy, a since-reset
occupancy high-water mark, accepted packets, overflowing packets, and dropped
beats. Counter clear establishes a new software baseline without hiding the
physical high-water mark. Simulation covers contiguous full-depth packets and
proves that overflow rollback drops only the current packet while preserving a
previously completed buffered packet.

On the guarded multi-symbol path, the bridge also emits a one-cycle loss event
when rollback begins. That event immediately marks the feed unhealthy, blocks
quotes, clears every bounded book, and leaves the overflow counters intact for
diagnosis. Software must explicitly rearm the feed after correcting or
accepting the loss condition.

Rearming is a two-phase operation performed after the CMAC and event buffers
drain. Recovery first clears the books and parser session/sequence expectations.
The first replay packet establishes new MoldUDP64 baselines, and contiguous replay
traffic rebuilds the books with quote output suppressed. Software activates
the feed only after that rebuild is complete. Any bridge loss, session change,
end-of-session marker, sequence gap, or
liveness timeout during rebuild returns the guard to the faulted state.

The guarded path also monitors cycles since the last complete CMAC packet. A
programmable AXI-Lite threshold converts prolonged packet inactivity into the
same fail-closed response while retaining a separate timeout counter and cause
bit. A zero threshold disables this check; configuration changes and software
recovery restart the interval.

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
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_multi_strategy_top` | `3.102 ns` | `0.613 ns` | `0.000 ns` | `26465 / 871680 (3.04%)` | `26690 / 1743360 (1.53%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_axis_multi_strategy_top` | `2.500 ns` | `0.011 ns` | `0.000 ns` | `26652 / 871680 (3.06%)` | `26689 / 1743360 (1.53%)` | Meets |

This pass covers the source-only CMAC AXIS RX bridge, UDP strip/realignment,
MoldUDP64/ITCH parser pipeline, event buffering, and top-of-book strategy path.
The same boundary closes through 2.750 ns / 364 MHz and misses 2.500 ns /
400 MHz by 0.153 ns. It is still an OOC RTL result, not a placed vendor-CMAC
board design, but it is the right source-level boundary for the generated
`cmac_usplus` AXIS template.

The guarded four-symbol boundary includes the same no-`tready` packet bridge,
plus session-change, sequence-gap, and packet-inactivity invalidation, AXI-Lite feed
rebuild/activation, four independent bounded books, ordered quote arbitration,
and AXI-Lite bridge-health telemetry.
It closes through 2.500 ns / 400 MHz with 11 ps of setup margin, 8.5 BRAM
tiles, and zero DSPs. This measured revision includes the programmable
feed-liveness watchdog, registered fail-closed timing boundary, BRAM-backed
CMAC burst storage, and distributed-RAM parser window.

The production source boundary now uses a 64-beat CMAC packet burst buffer and
a 32-beat per-packet parser store. Local regression drives two contiguous
1462-byte frames carrying 200 total ITCH messages with no idle CMAC cycle and
observes zero overflow or dropped beats. The timing rows above include this
buffer expansion.

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

## Validation And Deployment

Simulation, OOC synthesis, source-only routed harnesses, CMAC IP generation,
zero-black-box linking, board hard-block placement, full routing, and final DRC
are complete and reproducible through the checked-in scripts. Keep the OOC and
routed matrices as regression gates whenever the packet buffer, parser, book,
order, or session paths change.

The remaining deployment work is to obtain a bitstream-authorized CMAC
entitlement, regenerate the IP output products, emit the board bitstream, and
run replayed UDP traffic while observing feed, parser, risk, session, and order
telemetry through the management plane.

The key claim should stay precise: the repo has a 512-bit market-data and order
pipeline that closes OOC and through compact routed harnesses, plus a generated
CAUI-4 CMAC board harness that fully routes with clean timing and DRC. It is not
yet a programmed trading NIC or a live exchange connection.
