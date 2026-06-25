# 100G Readiness Notes

## Current Status

The project now has a 512-bit AXI-stream-style ingress shell intended to sit
behind a 100G-capable MAC on appropriate hardware. The shell accepts one
512-bit beat per clock when its FIFO has space, tracks ingress counters, and
drains the packet stream into the reusable parser path.

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

## What Still Blocks True Sustained 100G Parsing

The parser behind the ingress shell is still byte-serial. That means the design
can accept short high-speed bursts into the FIFO, but a fully saturated 100G
stream would eventually backpressure the ingress unless the FIFO is large enough
for the burst profile.

To make the parser itself sustained-line-rate capable, the next architecture
step is expanding the parallel frontend:

1. Extend boundary scanning beyond the first beat and carry state across packet
   beats.
2. Track message offsets when an ITCH message starts in one lane and ends in a
   later lane or later beat.
3. Extract multiple candidate fields from a wide beat in parallel.
4. Queue normalized events independently from packet ingestion.
5. Prove timing at the selected 100G MAC user clock on the target FPGA.

## Honest Interview Summary

This repository is now ready to discuss as a 100G-facing parser architecture:
the interface boundary, buffering, counters, and verification profile are in
place. The remaining production step is replacing the serial parser backend
with a parallel wide-lane parser to sustain worst-case line rate.
