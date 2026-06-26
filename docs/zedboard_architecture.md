# ZedBoard Architecture

## Goal

The ZedBoard path is a functional hardware demonstration of the parser, not a
25G/100G networking target. It should prove that packets can move from software
through the Zynq PS/PL boundary into the parser and that parsed events/counters
can be observed from software.

## Proposed Data Path

```text
PC packet generator
        |
        v
Zynq PS Ethernet / software UDP receiver
        |
        v
AXI DMA or AXI Stream FIFO
        |
        v
PL parser wrapper
        |
        +--> AXI-Lite counters/status
        |
        v
Event FIFO
        |
        v
PS software prints normalized events
```

## PL Wrapper Shape

The ZedBoard wrapper should use the existing parser path:

- 64-bit AXI-stream-style payload input.
- `market_parser_axis_adapter` or `market_parser_64` feeding the byte parser.
- AXI-Lite register block following `docs/register_map.md`.
- Small event FIFO for 256-bit normalized events.
- Optional interrupt when event FIFO transitions from empty to non-empty.

## Software Demo

The PS-side demo should:

1. Receive or load generated MoldUDP64/ITCH packets.
2. Write packet payloads to the PL stream path through DMA/FIFO.
3. Poll parser counters and event FIFO status.
4. Print normalized events in a compact table.

## What To Say In Interviews

The same parser core has two integration stories:

- ZedBoard proves functional hardware integration on accessible hardware.
- 100G modules model the interface and frontend architecture needed on a
  higher-end FPGA with a real 100G MAC.

Those are intentionally separate so the project stays technically honest.
