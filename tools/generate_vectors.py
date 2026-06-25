"""Generate deterministic market-parser smoke-test vectors."""

from __future__ import annotations

from pathlib import Path

from itch_packets import itch_add_order, itch_system_event, mold_packet, parse_mold_packet


OUT_DIR = Path(__file__).resolve().parents[1] / "verification" / "vectors"


def write_hex_bytes(path: Path, data: bytes) -> None:
    path.write_text("\n".join(f"{byte:02x}" for byte in data) + "\n", encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    pkt0 = mold_packet(1, [itch_add_order()])
    events0, next_seq = parse_mold_packet(pkt0)

    pkt1 = mold_packet(3, [itch_system_event()])
    events1, _ = parse_mold_packet(pkt1, expected_sequence=next_seq)

    write_hex_bytes(OUT_DIR / "add_order_packet.hex", pkt0)
    write_hex_bytes(OUT_DIR / "gap_system_event_packet.hex", pkt1)

    expected = [*events0, *events1]
    lines = [f"{event.pack_u256():064x}" for event in expected]
    (OUT_DIR / "expected_events.hex").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote {OUT_DIR}")


if __name__ == "__main__":
    main()
