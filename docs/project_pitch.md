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
extractor that packs descriptor-selected fields into normalized events. That
does not pretend to be a finished 100G trading NIC; it shows the right interface
boundary, buffering, observability, and early parallel parsing stages needed for
one.

## Strong Resume Bullet

Built a SystemVerilog FPGA market-data parser for Nasdaq MoldUDP64/ITCH with
sequence tracking, gap/error detection, normalized event output, AXI-stream-style
interfaces, generated reference vectors, randomized backpressure verification,
cycle-level latency reports, and 512-bit 100G-facing descriptor/event-extraction
frontend blocks.

## What To Emphasize

- Clean hardware interfaces: valid/ready input and output paths.
- Protocol awareness: MoldUDP64 sequence/message count and ITCH message lengths.
- Verification discipline: self-checking testbenches, generated vectors, bad
  packet cases, and zero-warning Questa regressions.
- Production mindset: counters, sticky error flags, register-map planning, and
  honest documentation of what is and is not line-rate.
- Growth path: byte-serial golden parser first, then wide frontend descriptors,
  then parallel field extraction, then a streaming parallel event pipeline.

## Honest Limits

The byte-serial parser remains the integrated golden correctness path. The
512-bit frontend and extractor now discover message descriptors and produce
golden-compatible events in focused tests, but they are not yet connected as one
streaming parallel event pipeline. That integration is the next production step.
