# Project Pitch

## One-Sentence Summary

This project is a SystemVerilog FPGA market-data parser for Nasdaq
MoldUDP64/ITCH, built as a simulation-first feed-handler core with a path toward
ZedBoard demonstration and 100G-capable frontend architecture.

## Interview Pitch

I built a production-shaped FPGA market parser rather than a toy decoder. The
core accepts MoldUDP64 packet frames, tracks sequence numbers, detects gaps and
malformed packets, splits ITCH messages by length, and emits normalized 256-bit
events. I verified it with generated protocol vectors, randomized output
backpressure, malformed/truncated packet tests, and Questa regression reports.

To make it relevant to low-latency trading hardware, I kept the parser core
transport-independent and added wider frontend profiles. The repo now includes
a 512-bit MAC-facing ingress shell, a multi-beat 512-bit descriptor frontend
that tracks ITCH message boundaries across packet beats, and a parallel
extractor that packs descriptor-selected fields into normalized events. I then
wired those blocks into a cut-through 512-bit event pipeline and verified it
against the same golden event vectors, including a test where the first event
appears before packet end while later beats continue arriving. I also added an
event FIFO boundary and an AXI-Lite control/status block so software can enable
the parser, read counters, clear sticky error flags, and observe FIFO state.
The verification suite now includes no-idle back-to-back packet stress,
FIFO-pressure checks, and cocotb randomized repeated-packet and malformed-frame
tests.
That does not pretend to be a finished 100G trading NIC; it shows the right
interface boundary, buffering, observability, and parallel parsing stages needed
for one.

## Strong Resume Bullet

Built a SystemVerilog FPGA market-data parser for Nasdaq MoldUDP64/ITCH with
sequence tracking, gap/error detection, normalized event output, AXI-stream-style
interfaces, generated reference vectors, randomized backpressure verification,
cycle-level latency reports, AXI-Lite control/status registers, and 512-bit
100G-facing descriptor/event-extraction frontend blocks integrated into a
cut-through parallel event pipeline with queued normalized-event output,
back-to-back packet stress, FIFO-pressure accounting, and cocotb randomized
checks.

## What To Emphasize

- Clean hardware interfaces: valid/ready input and output paths.
- Protocol awareness: MoldUDP64 sequence/message count and ITCH message lengths.
- Verification discipline: self-checking testbenches, generated vectors,
  randomized backpressure, FIFO pressure, bad packet cases, cocotb checks, and
  zero-warning Questa regressions.
- Production mindset: counters, sticky error flags, implemented AXI-Lite
  register map, and honest documentation of what is and is not line-rate.
- Growth path: byte-serial golden parser first, then wide frontend descriptors,
  then parallel field extraction, then integrated cut-through event pipeline,
  then sustained-line-rate timing and burst proof.

## Honest Limits

The byte-serial parser remains the mature golden correctness path. The 512-bit
parallel path is now cut-through within a packet and uses a four-beat/256-byte
default packet-local extraction window, but it has not been timing-closed on
real 100G hardware. The next production step is larger-window sweeps and timing
closure.
