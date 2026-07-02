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
| 512-bit parallel pipeline | 512 bits | 64 bytes | Cut-through descriptor, window, and event extraction path. |
| 512-bit pipeline + FIFO | 512 bits | 64 bytes | Parallel parser path with queued normalized-event output. |

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
- The event extractor consumes descriptors and a parameterized packet-local
  window to emit golden-compatible normalized events.
- The integrated 512-bit pipeline connects descriptor generation,
  four-beat/256-byte default window buffering, and event extraction, then
  verifies cut-through first-event output, event backpressure, bad-frame
  propagation, truncated-packet handling, and a long four-beat message case.
- The FIFO-backed pipeline proves that normalized events can be queued across
  downstream stalls without changing golden event contents.
- Back-to-back no-idle packet stress and FIFO-pressure tests prove that event
  ordering, `event_last`, counters, and FIFO backpressure accounting stay
  correct when packet ingress and event egress contend.
- Extraction-window sweeps verify the integrated 512-bit pipeline at 128, 256,
  and 512 bytes.
- cocotb adds Python-randomized repeated-packet, gap/stall, bad-frame, and
  truncated-packet checks around the 512-bit pipeline.
- Vivado OOC scripts provide resource and timing reports. The 512-bit frontend
  and integrated 512-bit pipeline meet a 3.102 ns OOC synthesis target on the
  U50-class `xcu50-fsvh2104-2-e` UltraScale+ reference part. The integrated
  pipeline also meets through a 2.100 ns OOC target on that part. The school
  matrix wrapper in `tools/run_hft_ooc_matrix.sh` is the next comparison path
  for U50/U55/Virtex UltraScale+ class targets.

## What This Does Not Claim

The current adapter serializes valid byte lanes into the byte-oriented parser
core. The newer 512-bit descriptor frontend, window buffer, and event extractor
are wired together in a first-stage cut-through parallel pipeline, and OOC
synthesis meets the 322 MHz-class target on a U50-class UltraScale+ reference
part, with OOC clock-sweep headroom through about 476 MHz. This is still not a
proven sustained-line-rate parser.

A true line-rate design would need a more parallel frontend, such as:

1. Packing normalized events independently from packet ingestion.
2. Applying deeper backpressure without losing beat-level alignment.
3. Integrating with a concrete 100G MAC/CMAC and board clocking shell.
   `docs/cmac_integration.md` tracks the expected attachment boundary.
4. Closing full implementation timing at the MAC clock rate on the target FPGA.

This project intentionally separates those concerns. The current design proves
protocol correctness and frontend-width portability first; a future line-rate
parser can replace the serializing adapter while keeping the normalized event
interface and verification vectors.
