# Redundant A/B Feed Merge

## Scope

`market_parser_100g_ab_multi_strategy_top` accepts two independent 512-bit
source-only CMAC RX AXIS streams. Each input first passes through a complete-
packet buffer because the generated CMAC receive interface has no `tready`.
An explicit one-beat register slice after each BRAM-backed buffer isolates the
buffer read path from sequence classification without reducing stream
throughput.
`market_parser_moldudp64_ab_arbiter` then produces one ordered raw-Ethernet
stream for the existing UDP, MoldUDP64, ITCH, feed-guard, and multi-symbol book
pipeline.

This is a source-level redundant-feed boundary. It does not instantiate two
encrypted CMAC cores, transceivers, or board pin constraints.

## Selection Rules

- The first valid packet establishes the expected MoldUDP64 sequence.
- A packet at the expected sequence may be selected from either source.
- When both sources present the same expected sequence and message count, one
  packet is forwarded and the other is discarded as an exact replay.
- Packets below the expected sequence are discarded as stale duplicates.
- A packet above the expected sequence waits up to `AB_MAX_SKEW_CYCLES` for the
  missing packet on the other source.
- An unrecovered gap latches `ab_merge_fault` and stops forwarding until
  `feed_recover` rearms the merger.
- Matching sequence numbers with different message counts latch a metadata-
  divergence fault.
- Selection remains on one source through `tlast`; downstream backpressure
  cannot interleave packets.

The exact-replay guard also covers message-count zero heartbeats and
message-count `0xFFFF` end-of-session markers, whose sequence does not advance.
The merger compares sequence/count metadata, not complete packet payloads.

## Session Handling

A and B may use different ten-byte MoldUDP64 session identifiers. The selected
first beat is rewritten with `MERGED_SESSION_ID` before reaching the parser.
Per-source session changes remain visible through
`ab_session_change_a_count` and `ab_session_change_b_count`, while ordinary A/B
failover does not trigger the downstream single-session feed guard.

## Telemetry

The top exposes per-source CMAC accepted, overflow, dropped-beat, occupancy,
high-watermark, and buffered-packet counters. Merge telemetry includes selected
and duplicate packets by source, malformed packets, active source, failovers,
gaps, divergence, expected sequence, and per-source session changes.

Either CMAC buffer overflow or an arbiter fault enters the existing fail-closed
feed-health path. The downstream inactivity watchdog counts only packets
selected into the merged stream, not redundant arrivals.

## Verification

`market_parser_moldudp64_ab_arbiter_tb` covers duplicate delivery, source
failover, bounded skew, downstream backpressure, malformed headers, gap timeout,
operator rearm, heartbeat/end-of-session replay suppression, and metadata
divergence.

`market_parser_100g_ab_multi_strategy_top_tb` replays the checked-in three-
packet multi-symbol Ethernet vectors across A and B. The feeds use different
physical session IDs; three unique packets produce all eight expected golden
top-of-book quotes exactly once, with two source failovers and no merge,
overflow, gap, divergence, or downstream session fault.

On `xcu50-fsvh2104-2-e`, the complete dual-feed source-level top closes OOC at
2.750 ns / 363.6 MHz with WNS `+0.009 ns`, TNS `0.000 ns`, WHS `+0.036 ns`, and
THS `0.000 ns`. It uses 28,096 LUTs, 27,625 registers, 17 BRAM tiles, and zero
DSPs. The 2.500 ns / 400 MHz stress point has WNS `-0.241 ns` and TNS
`-6.674 ns`. These are OOC source-level results, not routed or hardware claims.
