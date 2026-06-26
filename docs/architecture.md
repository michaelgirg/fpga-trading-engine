# Architecture Notes

## Design Goal

This project should look like the beginning of a real FPGA feed handler, not a
toy decoder. The parser core is kept independent from the final transport so it
can be simulated first, observed through production-style registers, and later
wrapped for ZedBoard.

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

The `market_parser_512_boundary_scan` block is the first building block for
that parallel parser path. It inspects a 512-bit first beat in parallel, decodes
MoldUDP64 sequence/message count fields, and identifies early ITCH message
length boundaries without walking the beat one byte per cycle.

The `market_parser_512_frontend` block extends that idea across packet beats. It
tracks packet-relative byte offsets, handles length fields split at beat
boundaries, and emits one descriptor per ITCH message for a future parallel
field extractor.

The `market_parser_512_event_extract` block consumes those descriptor fields
plus a two-beat packet window and packs the same 256-bit normalized event format
as the byte-serial parser. This keeps the serial parser as the golden reference
while proving the next parallel event-generation stage.

The `market_parser_512_pipeline` block wires the 512-bit descriptor frontend,
packet-local two-beat window buffer, and parallel extractor into one normalized
event stream. This first integrated version buffers one packet, drains
descriptors, then emits events with ready/valid backpressure. It is the bridge
between the correctness-first parser and a future cut-through line-rate parser.

The `market_parser_512_pipeline_fifo` block adds a normalized event FIFO after
the parallel parser. That makes the downstream boundary more production-like:
events can be queued while software, DMA, or strategy logic temporarily stalls.

The `market_parser_512_system` block is the current pre-hardware top level. It
connects the FIFO-backed 512-bit parser to `market_parser_axi_lite_regs`, which
adds parser enable control, software-visible counters, FIFO status, sticky
error flags, and clear-by-baseline behavior through an AXI-Lite slave.

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
