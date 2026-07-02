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

## Minimum Board Shell

A first real hardware integration should include:

- CMAC example design or board shell with RX statistics exposed.
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
6. Implement the full RTL shell with `tools/run_hft_impl_matrix.sh` on the
   selected school-supported part and compare post-route WNS/TNS against the
   OOC timing matrix.
7. Only after timing closes, add board traffic tests using replayed UDP payloads
   and verify counters/events through the management plane.

The key claim should stay precise: the repo now has a 512-bit parser
architecture that closes OOC on a realistic U50-class target, plus a CMAC-facing
Ethernet/IP/UDP ingress shell. It is not yet a finished trading NIC.
