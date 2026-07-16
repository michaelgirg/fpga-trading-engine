# 100G Readiness Notes

## Current Status

The project now has a 512-bit AXI-stream-style ingress shell intended to sit
behind a 100G-capable MAC on appropriate hardware. It also has an integrated
512-bit cut-through parallel path that connects descriptor generation,
four-beat/256-byte default packet-window buffering, normalized event extraction, and an output
event FIFO. The current pre-hardware top level also exposes AXI-Lite
control/status registers for parser enable, counters, FIFO status, bad-frame
counting, and sticky error flags. The regression now sweeps 128-, 256-, and
512-byte extraction windows, and the repo includes a Vivado out-of-context
synthesis hook for pre-hardware resource and timing reports.

Latest local Vivado OOC timing at a 3.102 ns target clock on the ZedBoard
`xc7z020clg484-1` part does not close:

- `market_parser_512_pipeline`: WNS `-3.290 ns`, TNS `-9750.711 ns`,
  LUTs `19435 / 53200`, registers `12900 / 106400`.
- `market_parser_512_frontend`: WNS `-3.341 ns`, TNS `-501.212 ns`,
  LUTs `1171 / 53200`, registers `1049 / 106400`.

That result is useful for stress-testing the RTL, but it is not the intended
100G target. Zynq-7020 is a functional demo target.

On a school Vivado 2024.2 install targeting the U50-class
`xcu50-fsvh2104-2-e` part, OOC synthesis at the same 3.102 ns target meets
timing:

- `market_parser_512_frontend`: WNS `0.872 ns`, TNS `0.000 ns`,
  CLB LUTs `1205 / 871680`, CLB registers `1049 / 1743360`.
- `market_parser_512_pipeline`: WNS `1.091 ns`, TNS `0.000 ns`,
  CLB LUTs `12326 / 871680`, CLB registers `12700 / 1743360`.

The U50-class OOC report is strong evidence that the architecture is realistic
for an UltraScale+ 100G-class target. The repo also now has a routed
implementation harness result for the full packet-to-book strategy path at the
same 3.102 ns / 322 MHz target: WNS `0.000 ns`, TNS `0.000 ns`, 18492 LUTs, and
21194 registers on `xcu50-fsvh2104-2-e`.

A U50-class OOC clock sweep for `market_parser_512_pipeline` shows useful
headroom beyond the 100G-facing 322 MHz target:

| Target period | Approx. frequency | WNS | TNS | Result |
| :--- | ---: | ---: | ---: | :--- |
| `3.102 ns` | 322 MHz | `1.091 ns` | `0.000 ns` | Meets |
| `2.750 ns` | 364 MHz | `0.739 ns` | `0.000 ns` | Meets |
| `2.500 ns` | 400 MHz | `0.489 ns` | `0.000 ns` | Meets |
| `2.250 ns` | 444 MHz | `0.239 ns` | `0.000 ns` | Meets |
| `2.100 ns` | 476 MHz | `0.082 ns` | `0.000 ns` | Meets |
| `2.000 ns` | 500 MHz | `0.030 ns` | `0.000 ns` | Meets |
| `1.950 ns` | 513 MHz | `-0.020 ns` | `-0.041 ns` | Near miss |

After a lane-offset retiming cleanup, `market_parser_512_frontend` also closes
at `2.100 ns`, reporting WNS `0.082 ns` and TNS `0.000 ns`. It now misses
`2.000 ns` by only `0.018 ns`; the integrated 512-bit pipeline closes the
`2.000 ns` target with WNS `0.030 ns`.

This is the right integration boundary for future hardware such as a board with
a 100G Ethernet MAC. It is not a claim that the current byte-serial parser can
sustain worst-case 100G traffic indefinitely.

The maintained HFT timing table and school-side matrix command are in
`docs/timing_matrix.md`. The concrete MAC-facing attachment plan is in
`docs/cmac_integration.md`.

## Hardware-Facing Interface

`market_parser_100g_ingress.sv` exposes a MAC-style RX stream:

| Signal | Direction | Width | Purpose |
| :--- | :--- | ---: | :--- |
| `s_axis_rx_tvalid` | input | 1 | RX beat valid. |
| `s_axis_rx_tready` | output | 1 | Ingress FIFO can accept a beat. |
| `s_axis_rx_tdata` | input | 512 | RX packet data. |
| `s_axis_rx_tkeep` | input | 64 | Valid byte lanes. |
| `s_axis_rx_tlast` | input | 1 | End of packet/frame. |
| `s_axis_rx_tuser_bad_frame` | input | 1 | Bad-frame marker from MAC/FCS layer. |

The testbench drives a MoldUDP64/ITCH packet as consecutive 512-bit beats and
checks that the ingress side accepts the burst without stalls.

## What Is Ready

- Synthesizable 512-bit AXI-stream-style ingress boundary.
- Wide-beat FIFO between the MAC-facing stream and parser path.
- Ingress observability counters:
  - accepted beats
  - accepted packets
  - backpressure cycles
  - bad-frame beats
  - FIFO level
- Regression coverage for a full packet delivered as a no-stall 512-bit burst.
- No-`tready` CMAC bridge coverage for contiguous full-depth packets, FIFO
  occupancy high-water telemetry, and packet-atomic overflow rollback.
- Immediate fail-closed feed invalidation and bounded-book clearing when the
  no-`tready` CMAC packet buffer loses a packet.
- Same normalized parser output checked against generated reference vectors.
- First-beat parallel boundary scanner for MoldUDP64 sequence/message count and
  early ITCH message-length candidates.
- Multi-beat 512-bit descriptor frontend that carries packet byte offset across
  beats and emits message descriptors for downstream parallel field extraction.
- Parallel 512-bit event extractor that consumes descriptors plus a
  parameterized packet window and emits the same normalized event format as the
  golden parser.
- Integrated `market_parser_512_pipeline` path that emits normalized events
  from 512-bit input beats using the descriptor frontend, window buffer, and
  extractor.
- Staged coarse/fine field alignment in the integrated pipeline so parallel
  extraction no longer packs directly from a full dynamic packet window in one
  cycle.
- Cut-through regression proving the first mixed-packet event appears before
  packet end and remains stable while later 512-bit beats are accepted.
- `market_parser_512_pipeline_fifo` wrapper that queues normalized events
  independently from downstream consumer readiness.
- `market_parser_512_system` wrapper that ties the 512-bit parser path to an
  AXI-Lite management plane for pre-hardware software-style observability.
- SystemVerilog regression for mixed messages, output backpressure stability,
  bad-frame propagation, and truncated-packet/incomplete-window handling.
- Extraction-window sweep regression for 128-, 256-, and 512-byte packet-local
  windows.
- Event FIFO regression that stalls the consumer, queues two mixed-message
  packets, then drains and compares all 16 events against golden vectors.
- Back-to-back no-idle packet regression that drives repeated mixed packets
  while event readiness randomly stalls.
- FIFO-pressure regression that fills the event FIFO, offers another packet,
  and verifies event integrity plus nonzero backpressure accounting.
- Dense tiny-message regression that packs ten 12-byte System Event messages
  into a few 512-bit beats, including a descriptor whose payload crosses a beat
  boundary.
- AXI-Lite system regression covering enable/disable, readable counters,
  software-visible counter clear, sticky error flag clearing, FIFO status, and
  FIFO read-count behavior.
- cocotb regression covering the golden packet, repeated randomized mixed
  packets, and bad/truncated packet flag behavior.
- Verilator tooling hook for open-source linting.
- Vivado out-of-context synthesis script for `market_parser_512_system` or any
  selected parser top.
- Routed Vivado implementation harness for the full strategy path, closing the
  3.102 ns / 322 MHz U50-class 100G target.

## What Still Blocks True Sustained 100G Parsing

The byte-serial parser still remains the mature golden correctness path. The
new 512-bit parallel path is integrated, has an output event FIFO, and now emits
eligible events before packet end. That is a real cut-through architecture
milestone, and the repo now has back-to-back/FIFO-pressure stress coverage.
It is still not a proven sustained-worst-case 100G parser: it uses a
packet-local window store with a four-beat/256-byte default extraction window,
and the routed result is an implementation harness rather than a complete board
design with real CMAC IP and board constraints.

To make the parser itself sustained-line-rate capable, the next architecture
step is proving the integrated parallel path through implementation-style
checks:

1. Keep the U50/U55-class OOC result as the HFT reference timing target and use
   the 1.950 ns near miss as the next optional timing cleanup target.
2. Run the school Vivado matrix across U50/U55/Virtex UltraScale+ style parts.
3. Add event FIFO depth sweeps, sustained back-to-back maximum-size traffic,
   and 512-byte long-payload stress cases.
4. Integrate against a concrete 100G MAC/CMAC shell and board clocking model.
5. Repeat routed implementation timing with the actual CMAC IP boundary and
   board constraints.

## Honest Interview Summary

This repository is now ready to discuss as a 100G-facing parser architecture:
the interface boundary, buffering, counters, verification profile, multi-beat
descriptor frontend, parallel event extraction block, and integrated
cut-through 512-bit event pipeline are in place. The project also has a
pre-hardware AXI-Lite management wrapper, which makes it easier to explain how
software would control and observe the parser. The remaining production steps
are broader school-target timing comparison, deeper burst/payload stress, real
100G MAC integration, board-constrained implementation timing, and a separate
optional ZedBoard functional demo.
