# 100G Readiness Notes

## Current Status

The project now has a 512-bit AXI-stream-style ingress shell intended to sit
behind a 100G-capable MAC on appropriate hardware. It also has an integrated
512-bit packet-buffered parallel path that connects descriptor generation,
two-beat packet-window buffering, normalized event extraction, and an output
event FIFO. The current pre-hardware top level also exposes AXI-Lite
control/status registers for parser enable, counters, FIFO status, bad-frame
counting, and sticky error flags.

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
- Parallel 512-bit event extractor that consumes descriptors plus a two-beat
  packet window and emits the same normalized event format as the golden parser.
- Integrated `market_parser_512_pipeline` path that emits normalized events
  from 512-bit input beats using the descriptor frontend, window buffer, and
  extractor.
- `market_parser_512_pipeline_fifo` wrapper that queues normalized events
  independently from downstream consumer readiness.
- `market_parser_512_system` wrapper that ties the 512-bit parser path to an
  AXI-Lite management plane for pre-hardware software-style observability.
- SystemVerilog regression for mixed messages, output backpressure stability,
  bad-frame propagation, and truncated-packet/incomplete-window handling.
- Event FIFO regression that stalls the consumer, queues two mixed-message
  packets, then drains and compares all 16 events against golden vectors.
- AXI-Lite system regression covering enable/disable, readable counters,
  software-visible counter clear, sticky error flag clearing, FIFO status, and
  FIFO read-count behavior.
- Optional cocotb and Verilator tooling hooks for Python randomized verification
  and open-source linting.

## What Still Blocks True Sustained 100G Parsing

The byte-serial parser still remains the mature golden correctness path. The
new 512-bit parallel path is integrated and has an output event FIFO, but it is
still packet-buffered: it captures a packet, drains descriptors, then emits
events into the FIFO. That is a real architecture milestone, but it is not yet
a cut-through parser that sustains worst-case 100G while overlapping packet
ingress and event egress.

To make the parser itself sustained-line-rate capable, the next architecture
step is expanding the integrated parallel path:

1. Allow descriptor/window extraction and event emission to overlap packet
   ingestion.
2. Add deeper event FIFO buffering and full packet-to-event backpressure
   accounting.
3. Expand beyond a two-beat extraction window for very large messages.
4. Prove timing at the selected 100G MAC user clock on the target FPGA.

## Honest Interview Summary

This repository is now ready to discuss as a 100G-facing parser architecture:
the interface boundary, buffering, counters, verification profile, multi-beat
descriptor frontend, parallel event extraction block, and integrated
packet-buffered 512-bit event pipeline are in place. The project also has a
pre-hardware AXI-Lite management wrapper, which makes it easier to explain how
software would control and observe the parser. The remaining production step is
making that pipeline cut-through and proving timing.
