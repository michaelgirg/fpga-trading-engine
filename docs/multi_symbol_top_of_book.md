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

The current output is a single ordered quote stream. Backpressure on that
stream blocks new book events, so no quote can be overtaken by a later symbol.

## Verification

The direct book-bank test interleaves three symbols and covers independent bid
and ask state, exact Replace semantics, untracked and malformed events,
aggregate counters, and output stability under backpressure.

The end-to-end test replays three generated Ethernet frames and compares every
quote to `MultiSymbolTopOfBookModel`. The replay contains 11 ITCH events, eight
applied updates, three ignored events, one untracked symbol, and eight expected
quote updates. No CMAC IP or CMAC license is required for this source-level
simulation path.
