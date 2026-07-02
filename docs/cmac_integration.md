# CMAC Integration Notes

## Current Boundary

`market_parser_512_pipeline` expects a 512-bit AXI-stream-style packet payload
where byte 0 is the first byte of the MoldUDP64 header. A raw 100G CMAC RX
stream usually begins with an Ethernet frame, so a real board shell needs a
small packet pre-parser before this core:

```text
100G CMAC RX
    |
    v
Ethernet / IPv4 / UDP filter and header strip
    |
    v
MoldUDP64 payload stream, 512-bit AXI style
    |
    v
market_parser_512_pipeline
    |
    v
event FIFO / strategy logic / DMA
```

## Stream Mapping

| Parser signal | CMAC-shell source |
| :--- | :--- |
| `s_axis_rx_tvalid` | Payload beat valid after Ethernet/IP/UDP filter accepts the packet. |
| `s_axis_rx_tready` | Backpressure into the payload FIFO or skid buffer, if the selected shell supports ready. |
| `s_axis_rx_tdata[511:0]` | UDP payload bytes, little-lane packed the same way as the testbenches. |
| `s_axis_rx_tkeep[63:0]` | Valid payload byte lanes on the beat. |
| `s_axis_rx_tlast` | Last beat of the UDP payload, not necessarily the Ethernet frame. |
| `s_axis_rx_tuser_bad_frame` | CMAC/FCS/error indication mapped onto the first payload beat or carried beside the packet. |

If the selected CMAC wrapper cannot be backpressured directly, add a payload
FIFO between the header-strip block and the parser. The parser already uses
ready/valid, but a line-side MAC stream may require absorbing short bursts even
when downstream event handling stalls.

## Clocking And Reset

The measured 3.102 ns target corresponds to the common 322 MHz-class 512-bit
100G CMAC user-clock regime. In a board design, the parser should run in the
same clock domain as the post-CMAC payload stream unless the shell already
provides a CDC FIFO. Reset should be synchronized into that domain, and sticky
error/counter state should remain accessible through the AXI-Lite management
plane.

## Minimum Board Shell

A first real hardware integration should include:

- CMAC example design or board shell with RX statistics exposed.
- Ethernet/IP/UDP header parser that selects the feed UDP port and strips to
  MoldUDP64 payload bytes.
- Payload FIFO or skid buffer sized for MAC-to-parser backpressure behavior.
- The existing `market_parser_512_pipeline_fifo` or `market_parser_512_system`
  block for event buffering and observability.
- AXI-Lite or debug-register access for parser enable, counters, FIFO level,
  bad-frame count, and sticky error flags.
- XDC constraints for the CMAC user clock, parser clock, resets, and any CDC
  paths.

## Validation Plan

1. Loop generated MoldUDP64/ITCH packets through the header-strip block in
   simulation and compare parser events against `verification/vectors`.
2. Run the dense tiny-message, mixed-message, malformed, and backpressure
   regressions with the shell attached.
3. Implement the full shell on the selected school-supported part and compare
   post-route WNS/TNS against the OOC timing matrix.
4. Only after timing closes, add board traffic tests using replayed UDP payloads
   and verify counters/events through the management plane.

The key claim should stay precise: the repo now has a 512-bit parser
architecture that closes OOC on a realistic U50-class target, plus a clear CMAC
integration boundary. It is not yet a finished trading NIC.
