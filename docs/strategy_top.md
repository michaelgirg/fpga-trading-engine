# Strategy Top

## Purpose

`market_parser_100g_strategy_top` connects the packet-facing receive path to
the first trading-oriented state block:

```text
512-bit CMAC RX stream
    -> Ethernet/IPv4/UDP payload strip
    -> MoldUDP64 / ITCH parser
    -> normalized 256-bit events
    -> single-symbol top-of-book engine
    -> quote update stream
```

The parser pipeline remains the high-frequency timing headline because it
closes 2.000 ns / 500 MHz out of context on the U50-class target. The
strategy-facing system target is the 3.102 ns / 322 MHz 100G user-clock class,
where a 512-bit datapath has enough raw width for 100G Ethernet.

## Interface

The wrapper accepts the same raw CMAC-style AXI4-Stream RX interface as
`market_parser_100g_cmac_system` and keeps its AXI-Lite status/control
passthrough. It adds explicit quote outputs from `market_parser_top_of_book`:

- `quote_valid` / `quote_ready`
- `quote_stock_locate`
- `quote_bid_price` / `quote_bid_shares`
- `quote_ask_price` / `quote_ask_shares`
- `quote_timestamp`

It also exposes parser-side counters and book-side counters so simulation and
future software can distinguish packet ingress health from strategy-state
updates.

## Validation

`market_parser_100g_strategy_top_tb` builds a real Ethernet/IPv4/UDP frame
containing a MoldUDP64 payload with three ITCH Add Order messages. The test
drives the raw 512-bit frame into the top and checks the resulting bid/ask
quote stream plus CMAC and book counters.

The current smoke case proves:

- accepted raw feed frame count increments once;
- one MoldUDP64 payload packet reaches the parser;
- three normalized Add Order events reach the book;
- three quote updates are emitted for initial bid, initial ask, and better bid;
- no ingress drops, parser header errors, ignored book events, or table
  overflows occur.

## Vivado Timing Result

School Vivado 2024.2 OOC synthesis closes `market_parser_100g_strategy_top` on
the U50-class `xcu50-fsvh2104-2-e` part at the 3.102 ns / 322 MHz 100G
user-clock target. After adding a one-deep register slice between the UDP
payload stripper and parser system, the combined packet-to-book path also
closes at 2.750 ns / 364 MHz and is within 29 ps at 2.500 ns / 400 MHz:

| Period | Approx. frequency | WNS | TNS | LUTs | Registers | Status |
| ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `3.102 ns` | 322 MHz | `0.573 ns` | `0.000 ns` | `23081 / 871680 (2.65%)` | `21875 / 1743360 (1.25%)` | Meets |
| `2.750 ns` | 364 MHz | `0.221 ns` | `0.000 ns` | `23280 / 871680 (2.67%)` | `21881 / 1743360 (1.26%)` | Meets |
| `2.500 ns` | 400 MHz | `-0.029 ns` | `-0.069 ns` | `23288 / 871680 (2.67%)` | `21881 / 1743360 (1.26%)` | Near miss |
| `2.250 ns` | 444 MHz | `-0.587 ns` | `-6.716 ns` | `23268 / 871680 (2.67%)` | `21295 / 1743360 (1.22%)` | Does not close |
| `2.100 ns` | 476 MHz | `-0.737 ns` | `-568.394 ns` | `23268 / 871680 (2.67%)` | `21295 / 1743360 (1.22%)` | Does not close |
| `2.000 ns` | 500 MHz | `-0.837 ns` | `-1011.505 ns` | `23268 / 871680 (2.67%)` | `21295 / 1743360 (1.22%)` | Does not close |

This is the current packet-to-book timing milestone: a raw 100G-style feed
frame can be stripped, parsed into normalized ITCH events, and applied to the
single-symbol book with margin beyond the target CMAC user-clock class.

## Next Timing Check

The 2.500 ns row is now only a 29 ps near miss, so it is the next diagnostic
point. Pull the worst setup path from that report before changing RTL again.
The 2.000 ns parser-core result remains a parser pipeline headline, not a
requirement for this full packet-to-book shell.
