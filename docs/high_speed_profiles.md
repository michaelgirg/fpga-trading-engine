# High-Speed Stream Profiles

## Goal

The ZedBoard demo path is not a 25G or 100G Ethernet design. The board is useful
for proving that the parser can run in hardware behind a Zynq PS/PL data path.

The high-speed profile in this repository is a simulation feature: it verifies
that the parser can sit behind common wide AXI-stream-style MAC datapaths while
keeping the parsing core independent from the transport.

## Current Profiles

| Profile | Input Width | Keep Width | Purpose |
| :--- | ---: | ---: | :--- |
| ZedBoard-friendly | 64 bits | 8 bytes | Small stream width for board-oriented integration work. |
| Wide MAC model | 256 bits | 32 bytes | Conceptual profile for wider low-latency networking datapaths. |
| 100G-style model | 512 bits | 64 bytes | Conceptual profile for very wide MAC-facing stream verification. |
| 100G ingress shell | 512 bits | 64 bytes | Hardware-facing RX stream with FIFO and ingress counters. |

All profiles use the same packet vectors and expected normalized event words.

## What This Proves

- The parser core is transport-independent.
- Byte lane ordering and `tkeep` handling are verified at multiple input widths.
- The same MoldUDP64/ITCH packet produces the same normalized events across
  64-, 256-, and 512-bit stream profiles.
- Counters, sticky error flags, and event outputs remain stable across frontend
  widths.
- The 100G ingress shell can accept a complete test packet as consecutive
  512-bit beats with no input stalls.

## What This Does Not Claim

The current adapter serializes valid byte lanes into the byte-oriented parser
core. That is useful for reuse and verification, but it is not a true 25G/100G
line-rate parser.

A true line-rate design would need a more parallel frontend, such as:

1. Detecting MoldUDP64 and ITCH message boundaries across many byte lanes per
   cycle.
2. Handling messages that begin and end inside the same wide beat.
3. Carrying multiple candidate message offsets through a parallel parser stage.
4. Applying backpressure without losing beat-level alignment.
5. Closing timing at the MAC clock rate on the target FPGA.

This project intentionally separates those concerns. The current design proves
protocol correctness and frontend-width portability first; a future line-rate
parser can replace the serializing adapter while keeping the normalized event
interface and verification vectors.
