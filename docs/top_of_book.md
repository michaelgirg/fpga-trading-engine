# Top-Of-Book Engine

## Purpose

`market_parser_top_of_book` is the first trading-oriented block after the
normalized ITCH parser. It consumes 256-bit parser events, keeps a small
single-symbol order table, and emits a quote update when the best bid or ask
changes.

This moves the project beyond packet parsing:

```text
CMAC RX -> UDP/MoldUDP64 strip -> ITCH parser -> normalized events
    -> top-of-book engine -> quote updates / strategy inputs
```

## Scope

The current block is intentionally bounded:

- One configured `TARGET_STOCK_LOCATE`.
- Fixed-depth order table for FPGA-friendly verification and synthesis.
- Applies add, execute, cancel, delete, and replace events.
- Aggregates displayed shares at the best bid and ask price.
- Ignores malformed, unknown, wrong-symbol, and unsupported event types.

The normalized 256-bit event ABI remains stable. The production 512-bit parser
also carries `event_new_order_ref` as a 64-bit sideband for Replace messages.
The book uses the event record's order reference to find the original order,
then atomically installs the sideband reference with the replacement size and
price. Later execute, cancel, and delete messages therefore resolve the new
ITCH order reference exactly.

## Interface

Input is the parser's normalized event stream:

| Field | Source bits |
| :--- | :--- |
| Event kind | `event_data[7:0]` |
| Stock locate | `event_data[31:16]` |
| Timestamp | `event_data[95:48]` |
| Order reference | `event_data[159:96]` |
| Shares | `event_data[191:160]` |
| Price | `event_data[223:192]` |
| Side | `event_data[231:224]` |
| Flags | `event_data[239:232]` |

`event_new_order_ref` is zero for every event except Replace.

Output is an explicit quote update:

- `quote_bid_price`
- `quote_bid_shares`
- `quote_ask_price`
- `quote_ask_shares`
- `quote_timestamp`

The module uses ready/valid on both sides and stalls event input while a quote
update is pending or while the book is recomputing.

## Timing Architecture

The first version used a full combinational order-table scan to recompute best
bid and ask after each applied event. That simulated correctly, but synthesized
as a long comparator/adder chain. The current implementation is intentionally
iterative:

- One table entry is checked per cycle during order lookup.
- One table entry is checked per cycle during quote recompute.
- Event input is backpressured during lookup/recompute.

For the default 16-entry table this adds a small, deterministic multi-cycle
latency after applied events, but keeps the FPGA timing path short enough for
the 100G user-clock target.

On `xcu50-fsvh2104-2-e`, out-of-context Vivado synthesis closes the 3.102 ns /
322 MHz target with WNS `0.605 ns`, using 1413 LUTs and 3146 registers.

## Validation

`market_parser_top_of_book_tb` drives synthetic normalized events through add,
cancel, execute, delete, replace, wrong-symbol, and malformed-event cases. It
also proves that Replace retires the old order reference and that later events
resolve only the new reference.

`market_parser_100g_strategy_top` wires this block behind
`market_parser_100g_cmac_system`, giving the project a packet-to-quote
integration path.

The end-to-end strategy regression also replays three independent
Ethernet/IPv4/UDP/MoldUDP64 frames generated from the Python golden model.
Orders persist across frame boundaries, sequence numbers remain contiguous,
and an interleaved non-target symbol is accepted by the parser but ignored by
the configured single-symbol book. Every emitted quote and the final
accepted/applied/ignored/overflow counters are checked against the model.
