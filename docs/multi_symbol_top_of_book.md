# Multi-Symbol Top Of Book

## Architecture

`market_parser_multi_symbol_top_of_book` scales the verified iterative book as
a bounded bank. `SYMBOL_LOCATES` defines the tracked stock-locate values and
each symbol owns an independent fixed-depth order table. The router accepts one
normalized event at a time, selects the matching book, and merges quote updates
onto one ready/valid output while preserving event order.

This structure keeps order lookup local to one small table. It uses more state
than a shared table, but avoids a large cross-symbol associative search on the
clock-critical path and makes symbol capacity explicit at synthesis time.

The production 512-bit parser carries the original order reference in the
stable 256-bit event record and the replacement reference in the 64-bit
`event_new_order_ref` sideband. Replace updates both the order reference and
price/size state atomically in the selected book.

## Integration

`market_parser_100g_multi_strategy_top` connects the book bank behind the raw
Ethernet/IPv4/UDP/MoldUDP64/ITCH ingress path. Its default configuration tracks
four symbols; both symbol count and packed locate list are parameters. Events
for unconfigured locates are consumed and counted without changing a book.

`market_parser_100g_cmac_axis_multi_strategy_top` adds the production-shaped
source-only CMAC RX boundary. It packet-buffers the no-`tready` 512-bit AXIS
stream before handing complete frames to the guarded multi-symbol path. This
wrapper contains no generated vendor IP and is the source-level synthesis and
routed-implementation boundary used while board/IP licensing is handled
separately.

The current output is a single ordered quote stream. Backpressure on that
stream blocks new book events, so no quote can be overtaken by a later symbol.

### Feed Integrity

The 512-bit frontend tracks the next expected MoldUDP64 sequence and marks
every normalized event from a discontinuous packet with `FLAG_GAP`. The
multi-symbol strategy top treats that flag as a feed-integrity fault. The
CMAC-facing wrapper also raises the same fail-closed guard immediately when its
no-`tready` packet buffer overflows. Either cause clears all bounded book state,
suppresses quote output, and consumes later events without updating a book.
`feed_healthy`,
`feed_gap_count`, and `feed_suppressed_event_count` expose the guard state and
history.

The guard rearms when the external `feed_recover` input is asserted or software
writes one to `CONTROL[2]` through AXI-Lite. `FEED_STATUS`, `FEED_GAP_COUNT`,
and `FEED_SUPPRESSED_EVENT_COUNT` expose the same guard state to software.
Fault-history counters persist across recovery; the existing counter-clear
control establishes new software-visible baselines.

## Verification

The direct book-bank test interleaves three symbols and covers independent bid
and ask state, exact Replace semantics, untracked and malformed events,
aggregate counters, and output stability under backpressure.

The end-to-end test drives the source-only CMAC AXIS interface without
backpressure, replays three generated Ethernet frames, and compares every quote
to `MultiSymbolTopOfBookModel`. The replay contains 11 ITCH events, eight
applied updates, three ignored events, one untracked symbol, and eight expected
quote updates. It verifies zero bridge overflow or dropped beats, then replays
a stale sequence, checks the AXI-Lite health/counter registers, performs
software recovery, and proves that a correctly resequenced packet produces the
expected quotes. It then forces a 17-beat packet into the 16-beat bridge and
checks atomic rollback, immediate feed invalidation, book clearing, cause
telemetry, and recovery with preserved history. No CMAC IP license is required
for this simulation path.

## U50 OOC Results

Vivado 2024.2 out-of-context synthesis on `xcu50-fsvh2104-2-e` closes the
3.102 ns / 322 MHz 100G user-clock target for both synthesis boundaries. After
registering balanced UDP `tkeep` counts, the complete packet-to-quote top with
fail-closed sequence-gap handling also closes 2.500 ns / 400 MHz:

| Top | Period | Frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `market_parser_multi_symbol_top_of_book` | `3.102 ns` | 322 MHz | `0.605 ns` | `0.000 ns` | `1719 / 871680 (0.20%)` | `3242 / 1743360 (0.19%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `3.102 ns` | 322 MHz | `0.700 ns` | `0.000 ns` | `29556 / 871680 (3.39%)` | `33585 / 1743360 (1.93%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `2.500 ns` | 400 MHz | `0.098 ns` | `0.000 ns` | `29760 / 871680 (3.41%)` | `33591 / 1743360 (1.93%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `2.400 ns` | 417 MHz | `-0.002 ns` | `-0.012 ns` | `29773 / 871680 (3.42%)` | `33591 / 1743360 (1.93%)` | Near miss |
| `market_parser_100g_multi_strategy_top` | `2.350 ns` | 426 MHz | `-0.052 ns` | `-0.262 ns` | `29764 / 871680 (3.41%)` | `33590 / 1743360 (1.93%)` | Does not close |
| `market_parser_100g_cmac_axis_multi_strategy_top` | `3.102 ns` | 322 MHz | `0.668 ns` | `0.000 ns` | `30023 / 871680 (3.44%)` | `33891 / 1743360 (1.94%)` | Meets |
| `market_parser_100g_cmac_axis_multi_strategy_top` | `2.750 ns` | 364 MHz | `0.348 ns` | `0.000 ns` | `30269 / 871680 (3.47%)` | `33787 / 1743360 (1.94%)` | Meets |
| `market_parser_100g_cmac_axis_multi_strategy_top` | `2.500 ns` | 400 MHz | `0.066 ns` | `0.000 ns` | `30227 / 871680 (3.47%)` | `33887 / 1743360 (1.94%)` | Meets |

The unbridged guarded top has 98 ps of setup margin at 2.500 ns, while the
source-only CMAC packet bridge and telemetry boundary has 66 ps. Both are
measured 400 MHz operating points with zero BRAM tiles and zero DSPs. These are
source-level OOC results and do not depend on generated CMAC IP. The unbridged
guarded design misses 2.400 ns / 416.7 MHz by only 2 ps.
