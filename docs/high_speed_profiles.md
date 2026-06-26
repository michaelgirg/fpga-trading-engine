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
| 512-bit parallel pipeline | 512 bits | 64 bytes | Packet-buffered descriptor, window, and event extraction path. |

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
- The 512-bit boundary scanner decodes the first MoldUDP64 header and discovers
  ITCH message-length candidates near beat boundaries.
- The 512-bit frontend carries packet byte offsets across beats and emits
  message descriptors for downstream parallel field extraction.
- The event extractor consumes descriptors and a two-beat packet window to emit
  golden-compatible normalized events.
- The integrated 512-bit pipeline connects descriptor generation, two-beat
  window buffering, and event extraction, then verifies event backpressure,
  bad-frame propagation, and truncated-packet handling.

## What This Does Not Claim

The current adapter serializes valid byte lanes into the byte-oriented parser
core. The newer 512-bit descriptor frontend, window buffer, and event extractor
are wired together in a packet-buffered parallel pipeline, but this is not yet a
cut-through sustained-line-rate parser.

A true line-rate design would need a more parallel frontend, such as:

1. Overlapping packet ingress with descriptor/window extraction and event egress.
2. Packing normalized events independently from packet ingestion.
3. Applying deeper backpressure without losing beat-level alignment.
4. Closing timing at the MAC clock rate on the target FPGA.

This project intentionally separates those concerns. The current design proves
protocol correctness and frontend-width portability first; a future line-rate
parser can replace the serializing adapter while keeping the normalized event
interface and verification vectors.
