# Architecture Notes

## Design Goal

This project should look like the beginning of a real FPGA feed handler, not a
toy decoder. The parser core is kept independent from the final transport so it
can be simulated first and later wrapped for ZedBoard.

## Pipeline Shape

```text
MoldUDP64 packet stream
        |
        v
AXI-stream width adapter
        |
        v
MoldUDP64 header parser
        |
        v
sequence / gap checker
        |
        v
message length splitter
        |
        v
ITCH message parser
        |
        v
normalized event stream
```

## Production Signals To Preserve

- Keep sequence state visible.
- Keep sticky error counters visible.
- Emit normalized events instead of exposing raw parser internals.
- Use ready/valid interfaces everywhere.
- Keep transport details outside the core parser.
- Verify frontend width changes without changing parser behavior.

## High-Speed Stream Profiles

The ZedBoard path is a functional hardware-demo path, not a 25G/100G networking
path. To still practice the architecture used around faster MACs, the project
includes a parameterized AXI-stream-style adapter that can be simulated at 64,
256, and 512 bits.

The current adapter serializes valid byte lanes into the byte parser. This keeps
the parser reusable and easy to verify. It should be described as a wide
frontend compatibility profile, not a true line-rate 100G parser. A production
line-rate frontend would need parallel boundary detection and multi-lane message
extraction before the normalized event stage.

The `market_parser_100g_ingress` block adds the hardware-facing 512-bit stream
boundary and FIFO that a 100G-capable board would need before the parser. It is
the correct place to attach a 100G MAC RX stream, while the backend parser
remains the part that must be parallelized for sustained worst-case line rate.

## ZedBoard Path

The eventual ZedBoard demo should not claim to be production networking. The
honest demo path is:

1. PC sends generated UDP packets.
2. Zynq PS receives the packets over 1 Gb Ethernet.
3. PS forwards packet payload bytes into the PL parser through AXI DMA or an
   AXI Stream FIFO.
4. PL parser emits normalized events.
5. PS prints parsed events and counters.

The parser core should not need to change for that demo.
