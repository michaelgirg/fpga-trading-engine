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

## U50 OOC Results

Vivado 2024.2 out-of-context synthesis on `xcu50-fsvh2104-2-e` closes the
3.102 ns / 322 MHz 100G user-clock target for both synthesis boundaries. The
complete packet-to-quote top also closes through 2.650 ns / 377.4 MHz:

| Top | Period | Frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `market_parser_multi_symbol_top_of_book` | `3.102 ns` | 322 MHz | `0.605 ns` | `0.000 ns` | `1719 / 871680 (0.20%)` | `3242 / 1743360 (0.19%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `3.102 ns` | 322 MHz | `0.456 ns` | `0.000 ns` | `29797 / 871680 (3.42%)` | `33444 / 1743360 (1.92%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `2.750 ns` | 364 MHz | `0.104 ns` | `0.000 ns` | `29999 / 871680 (3.44%)` | `33444 / 1743360 (1.92%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `2.650 ns` | 377 MHz | `0.004 ns` | `0.000 ns` | `30001 / 871680 (3.44%)` | `33444 / 1743360 (1.92%)` | Meets |
| `market_parser_100g_multi_strategy_top` | `2.600 ns` | 385 MHz | `-0.046 ns` | `-0.139 ns` | `30001 / 871680 (3.44%)` | `33444 / 1743360 (1.92%)` | Near miss |
| `market_parser_100g_multi_strategy_top` | `2.550 ns` | 392 MHz | `-0.096 ns` | `-92.369 ns` | `30001 / 871680 (3.44%)` | `33444 / 1743360 (1.92%)` | Does not close |
| `market_parser_100g_multi_strategy_top` | `2.500 ns` | 400 MHz | `-0.146 ns` | `-293.451 ns` | `30001 / 871680 (3.44%)` | `33444 / 1743360 (1.92%)` | Does not close |

The 2.650 ns result is a measured pass but has only 4 ps of setup margin;
2.750 ns / 363.6 MHz is the stronger high-frequency operating point. All
builds use zero BRAM tiles and zero DSPs. These are source-level OOC results
and do not require or claim a generated CMAC IP license.
