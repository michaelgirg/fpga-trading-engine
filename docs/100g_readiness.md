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

This is the right integration boundary for future hardware such as a board with
a 100G Ethernet MAC. It is not a claim that the current byte-serial parser can
sustain worst-case 100G traffic indefinitely.

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
- AXI-Lite system regression covering enable/disable, readable counters,
  software-visible counter clear, sticky error flag clearing, FIFO status, and
  FIFO read-count behavior.
- cocotb regression covering the golden packet, repeated randomized mixed
  packets, and bad/truncated packet flag behavior.
- Verilator tooling hook for open-source linting.
- Vivado out-of-context synthesis script for `market_parser_512_system` or any
  selected parser top.

## What Still Blocks True Sustained 100G Parsing

The byte-serial parser still remains the mature golden correctness path. The
new 512-bit parallel path is integrated, has an output event FIFO, and now emits
eligible events before packet end. That is a real cut-through architecture
milestone, and the repo now has back-to-back/FIFO-pressure stress coverage.
It is still not a proven sustained-worst-case 100G parser: it uses a
packet-local window store with a four-beat/256-byte default extraction window,
and has not been through implementation timing closure.

To make the parser itself sustained-line-rate capable, the next architecture
step is proving the integrated parallel path through implementation-style
checks:

1. Run Vivado OOC synthesis and inspect timing/resource reports.
2. Add deeper event FIFO buffering and more burst-depth sweeps.
3. Add 512-byte long-payload stress cases.
4. Prove timing at the selected 100G MAC user clock on the target FPGA.

## Honest Interview Summary

This repository is now ready to discuss as a 100G-facing parser architecture:
the interface boundary, buffering, counters, verification profile, multi-beat
descriptor frontend, parallel event extraction block, and integrated
cut-through 512-bit event pipeline are in place. The project also has a
pre-hardware AXI-Lite management wrapper, which makes it easier to explain how
software would control and observe the parser. The remaining production steps
are OOC report review, deeper burst/payload stress, and timing closure.
