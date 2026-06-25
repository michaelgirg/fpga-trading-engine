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
