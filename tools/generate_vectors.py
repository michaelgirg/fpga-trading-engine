"""Generate deterministic market-parser smoke-test vectors."""

from __future__ import annotations

from pathlib import Path

from itch_packets import (
    itch_add_order,
    itch_order_cancel,
    itch_order_delete,
    itch_order_executed,
    itch_order_replace,
    itch_system_event,
    itch_trade,
    itch_unknown,
    mold_packet,
    parse_mold_packet,
    truncated_payload_packet,
)


OUT_DIR = Path(__file__).resolve().parents[1] / "verification" / "vectors"


def write_hex_bytes(path: Path, data: bytes) -> None:
    path.write_text("\n".join(f"{byte:02x}" for byte in data) + "\n", encoding="utf-8")


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

    write_hex_bytes(OUT_DIR / "add_order_packet.hex", pkt0)
    write_hex_bytes(OUT_DIR / "gap_system_event_packet.hex", pkt1)
    write_hex_bytes(OUT_DIR / "mixed_messages_packet.hex", pkt2)
    write_hex_bytes(OUT_DIR / "truncated_packet.hex", pkt3)

    expected = [*events0, *events1, *events2]
    lines = [f"{event.pack_u256():064x}" for event in expected]
    (OUT_DIR / "expected_events.hex").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote {OUT_DIR}")


if __name__ == "__main__":
    main()
