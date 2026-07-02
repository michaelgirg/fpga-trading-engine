"""Generate deterministic market-parser smoke-test vectors."""

from pathlib import Path

from itch_packets import (
    end_session,
    heartbeat,
    itch_add_order,
    itch_order_cancel,
    itch_order_delete,
    itch_order_executed,
    itch_order_replace,
    itch_trade,
    itch_system_event,
    itch_unknown,
    mold_packet,
    parse_mold_packet,
    truncated_payload_packet,
)
from top_of_book_golden import TopOfBookModel


OUT_DIR = Path(__file__).resolve().parents[1] / "verification" / "vectors"
FEED_UDP_PORT = 5000
TARGET_STOCK_LOCATE = 0x1234


def write_hex_bytes(path: Path, data: bytes) -> None:
    path.write_text("\n".join(f"{byte:02x}" for byte in data) + "\n", encoding="utf-8")


def write_hex_words(path: Path, words, width: int) -> None:
    hex_digits = width // 4
    path.write_text("\n".join(f"{word:0{hex_digits}x}" for word in words) + "\n", encoding="utf-8")


def u16(value: int) -> bytes:
    return value.to_bytes(2, "big")


def build_raw_udp_frame(payload: bytes, dst_port: int = FEED_UDP_PORT) -> bytes:
    ip_total_length = 20 + 8 + len(payload)
    udp_length = 8 + len(payload)
    eth = bytes(
        [
            0x01,
            0x02,
            0x03,
            0x04,
            0x05,
            0x06,
            0x0A,
            0x0B,
            0x0C,
            0x0D,
            0x0E,
            0x0F,
            0x08,
            0x00,
        ]
    )
    ipv4 = bytes(
        [
            0x45,
            0x00,
        ]
    ) + u16(ip_total_length) + bytes(
        [
            0x00,
            0x01,
            0x40,
            0x00,
            0x40,
            0x11,
            0x00,
            0x00,
            0x0A,
            0x00,
            0x00,
            0x01,
            0xEF,
            0xC0,
            0x00,
            0x01,
        ]
    )
    udp = bytes([0x9C, 0x40]) + u16(dst_port) + u16(udp_length) + bytes([0x00, 0x00])
    return eth + ipv4 + udp + payload


def build_top_book_replay_messages():
    target = TARGET_STOCK_LOCATE
    wrong = 0x9999
    stock = b"TEST    "
    return [
        itch_add_order(stock_locate=target, tracking_number=1, timestamp=1, order_ref=1, side=b"B", shares=10, stock=stock, price=1000),
        itch_add_order(stock_locate=target, tracking_number=2, timestamp=2, order_ref=2, side=b"S", shares=7, stock=stock, price=1050),
        itch_add_order(stock_locate=target, tracking_number=3, timestamp=3, order_ref=3, side=b"B", shares=6, stock=stock, price=990),
        itch_add_order(stock_locate=target, tracking_number=4, timestamp=4, order_ref=4, side=b"B", shares=4, stock=stock, price=1000),
        itch_order_executed(stock_locate=target, tracking_number=5, timestamp=5, order_ref=1, shares=5),
        itch_order_cancel(stock_locate=target, tracking_number=6, timestamp=6, order_ref=3, canceled_shares=6),
        itch_add_order(stock_locate=target, tracking_number=7, timestamp=7, order_ref=5, side=b"S", shares=3, stock=stock, price=1040),
        itch_order_delete(stock_locate=target, tracking_number=8, timestamp=8, order_ref=2),
        itch_order_replace(stock_locate=target, tracking_number=9, timestamp=9, original_order_ref=4, new_order_ref=40, shares=4, price=1060),
        itch_order_cancel(stock_locate=target, tracking_number=10, timestamp=10, order_ref=4, canceled_shares=4),
        itch_order_executed(stock_locate=target, tracking_number=11, timestamp=11, order_ref=5, shares=3),
        itch_add_order(stock_locate=wrong, tracking_number=12, timestamp=12, order_ref=100, side=b"B", shares=100, stock=stock, price=2000),
        itch_trade(stock_locate=target, tracking_number=13, timestamp=13, order_ref=200, side=b"S", shares=20, stock=stock, price=1030),
        itch_unknown(stock_locate=target, tracking_number=14, timestamp=14),
        itch_order_delete(stock_locate=target, tracking_number=15, timestamp=15, order_ref=1),
    ]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    pkt0 = mold_packet(1, [itch_add_order()])
    events0, next_seq = parse_mold_packet(pkt0)

    pkt1 = mold_packet(3, [itch_system_event()])
    events1, _ = parse_mold_packet(pkt1, expected_sequence=next_seq)

    mixed_messages = [
        itch_add_order(msg_type=b"F", order_ref=0x7777000000000001, shares=101, price=1010100),
        itch_order_executed(msg_type=b"E"),
        itch_order_executed(msg_type=b"C", shares=76, price=555600),
        itch_order_cancel(),
        itch_order_delete(),
        itch_order_replace(),
        itch_trade(),
        itch_unknown(),
    ]
    pkt2 = mold_packet(5, mixed_messages)
    events2, next_seq = parse_mold_packet(pkt2, expected_sequence=5)

    pkt3 = truncated_payload_packet(next_seq)
    pkt4 = heartbeat(next_seq + 1)
    pkt5 = end_session(next_seq + 1)

    write_hex_bytes(OUT_DIR / "add_order_packet.hex", pkt0)
    write_hex_bytes(OUT_DIR / "gap_system_event_packet.hex", pkt1)
    write_hex_bytes(OUT_DIR / "mixed_messages_packet.hex", pkt2)
    write_hex_bytes(OUT_DIR / "truncated_packet.hex", pkt3)
    write_hex_bytes(OUT_DIR / "heartbeat_packet.hex", pkt4)
    write_hex_bytes(OUT_DIR / "end_session_packet.hex", pkt5)

    expected = [*events0, *events1, *events2]
    lines = [f"{event.pack_u256():064x}" for event in expected]
    (OUT_DIR / "expected_events.hex").write_text("\n".join(lines) + "\n", encoding="utf-8")

    replay_messages = build_top_book_replay_messages()
    replay_payload = mold_packet(100, replay_messages)
    replay_events, _ = parse_mold_packet(replay_payload, expected_sequence=100)
    book_model = TopOfBookModel(TARGET_STOCK_LOCATE, table_depth=8)
    replay_quotes = book_model.replay(replay_events)
    replay_raw = build_raw_udp_frame(replay_payload)

    write_hex_bytes(OUT_DIR / "top_book_replay_raw_packet.hex", replay_raw)
    write_hex_words(
        OUT_DIR / "top_book_replay_expected_quotes.hex",
        [quote.pack_u192() for quote in replay_quotes],
        192,
    )
    (OUT_DIR / "top_book_replay_meta.svh").write_text(
        "\n".join(
            [
                f"localparam int TOP_BOOK_REPLAY_RAW_PACKET_BYTES = {len(replay_raw)};",
                f"localparam int TOP_BOOK_REPLAY_EXPECTED_RAW_BEATS = {(len(replay_raw) + 63) // 64};",
                f"localparam int TOP_BOOK_REPLAY_EXPECTED_EVENTS = {len(replay_events)};",
                f"localparam int TOP_BOOK_REPLAY_EXPECTED_QUOTES = {len(replay_quotes)};",
                f"localparam int TOP_BOOK_REPLAY_EXPECTED_APPLIED = {book_model.applied_event_count};",
                f"localparam int TOP_BOOK_REPLAY_EXPECTED_IGNORED = {book_model.ignored_event_count};",
                f"localparam int TOP_BOOK_REPLAY_EXPECTED_OVERFLOW = {book_model.table_overflow_count};",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"Wrote {OUT_DIR}")


if __name__ == "__main__":
    main()
