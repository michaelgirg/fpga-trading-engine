"""Helpers for synthetic Nasdaq ITCH/MoldUDP64 test packets.

This is not an exchange feed client. It only creates small deterministic
packets for simulation and reference checks.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


SESSION = b"SIM0000001"

EVENT_UNKNOWN = 0
EVENT_SYSTEM = 1
EVENT_DIRECTORY = 2
EVENT_ADD = 3
EVENT_EXECUTE = 4
EVENT_CANCEL = 5
EVENT_DELETE = 6
EVENT_REPLACE = 7
EVENT_TRADE = 8

FLAG_GAP = 0x01
FLAG_MALFORMED = 0x02
FLAG_UNKNOWN = 0x04


@dataclass(frozen=True)
class ParsedEvent:
    event_kind: int
    msg_type: int
    stock_locate: int = 0
    tracking_number: int = 0
    timestamp: int = 0
    order_ref: int = 0
    shares: int = 0
    price: int = 0
    side: int = 0
    flags: int = 0

    def pack_u256(self) -> int:
        value = 0
        value |= self.event_kind & 0xFF
        value |= (self.msg_type & 0xFF) << 8
        value |= (self.stock_locate & 0xFFFF) << 16
        value |= (self.tracking_number & 0xFFFF) << 32
        value |= (self.timestamp & 0xFFFFFFFFFFFF) << 48
        value |= (self.order_ref & 0xFFFFFFFFFFFFFFFF) << 96
        value |= (self.shares & 0xFFFFFFFF) << 160
        value |= (self.price & 0xFFFFFFFF) << 192
        value |= (self.side & 0xFF) << 224
        value |= (self.flags & 0xFF) << 232
        return value


def _u16(value: int) -> bytes:
    return value.to_bytes(2, "big")


def _u32(value: int) -> bytes:
    return value.to_bytes(4, "big")


def _u48(value: int) -> bytes:
    return value.to_bytes(6, "big")


def _u64(value: int) -> bytes:
    return value.to_bytes(8, "big")


def mold_packet(sequence: int, messages: Iterable[bytes], session: bytes = SESSION) -> bytes:
    messages = list(messages)
    if len(session) != 10:
        raise ValueError("MoldUDP64 session must be exactly 10 bytes")
    header = session + _u64(sequence) + _u16(len(messages))
    payload = b"".join(_u16(len(msg)) + msg for msg in messages)
    return header + payload


def heartbeat(sequence: int, session: bytes = SESSION) -> bytes:
    return session + _u64(sequence) + _u16(0)


def itch_system_event(
    stock_locate: int = 1,
    tracking_number: int = 2,
    timestamp: int = 0x10,
    event_code: bytes = b"O",
) -> bytes:
    return b"S" + _u16(stock_locate) + _u16(tracking_number) + _u48(timestamp) + event_code


def itch_add_order(
    stock_locate: int = 0x1234,
    tracking_number: int = 0x5678,
    timestamp: int = 0x010203040506,
    order_ref: int = 0x1111222233334444,
    side: bytes = b"B",
    shares: int = 100,
    stock: bytes = b"ABCD    ",
    price: int = 1234500,
) -> bytes:
    if len(side) != 1:
        raise ValueError("side must be one byte")
    if len(stock) != 8:
        raise ValueError("stock must be eight bytes")
    return (
        b"A"
        + _u16(stock_locate)
        + _u16(tracking_number)
        + _u48(timestamp)
        + _u64(order_ref)
        + side
        + _u32(shares)
        + stock
        + _u32(price)
    )


def classify_msg(msg_type: int) -> int:
    if msg_type == ord("S"):
        return EVENT_SYSTEM
    if msg_type == ord("R"):
        return EVENT_DIRECTORY
    if msg_type in (ord("A"), ord("F")):
        return EVENT_ADD
    if msg_type in (ord("E"), ord("C")):
        return EVENT_EXECUTE
    if msg_type == ord("X"):
        return EVENT_CANCEL
    if msg_type == ord("D"):
        return EVENT_DELETE
    if msg_type == ord("U"):
        return EVENT_REPLACE
    if msg_type in (ord("P"), ord("Q")):
        return EVENT_TRADE
    return EVENT_UNKNOWN


def parse_itch_message(msg: bytes, flags: int = 0) -> ParsedEvent:
    msg_type = msg[0]
    event_kind = classify_msg(msg_type)
    if event_kind == EVENT_UNKNOWN:
        flags |= FLAG_UNKNOWN

    stock_locate = int.from_bytes(msg[1:3], "big") if len(msg) >= 3 else 0
    tracking_number = int.from_bytes(msg[3:5], "big") if len(msg) >= 5 else 0
    timestamp = int.from_bytes(msg[5:11], "big") if len(msg) >= 11 else 0
    order_ref = int.from_bytes(msg[11:19], "big") if len(msg) >= 19 else 0
    side = 0
    shares = 0
    price = 0

    if msg_type in (ord("A"), ord("F"), ord("P")) and len(msg) >= 36:
        side = msg[19]
        shares = int.from_bytes(msg[20:24], "big")
        price = int.from_bytes(msg[32:36], "big")
    elif msg_type in (ord("E"), ord("C"), ord("X")) and len(msg) >= 23:
        shares = int.from_bytes(msg[19:23], "big")
        if msg_type == ord("C") and len(msg) >= 36:
            price = int.from_bytes(msg[32:36], "big")
    elif msg_type == ord("U") and len(msg) >= 35:
        shares = int.from_bytes(msg[27:31], "big")
        price = int.from_bytes(msg[31:35], "big")
    elif msg_type == ord("Q") and len(msg) >= 36:
        price = int.from_bytes(msg[32:36], "big")

    return ParsedEvent(
        event_kind=event_kind,
        msg_type=msg_type,
        stock_locate=stock_locate,
        tracking_number=tracking_number,
        timestamp=timestamp,
        order_ref=order_ref,
        shares=shares,
        price=price,
        side=side,
        flags=flags,
    )


def parse_mold_packet(packet: bytes, expected_sequence: int | None = None) -> tuple[list[ParsedEvent], int]:
    if len(packet) < 20:
        raise ValueError("packet is shorter than the MoldUDP64 header")

    sequence = int.from_bytes(packet[10:18], "big")
    message_count = int.from_bytes(packet[18:20], "big")
    if message_count in (0, 0xFFFF):
        return [], sequence

    flags = 0
    if expected_sequence is not None and sequence != expected_sequence:
        flags |= FLAG_GAP

    offset = 20
    events = []
    for _ in range(message_count):
        if offset + 2 > len(packet):
            raise ValueError("truncated message length")
        msg_len = int.from_bytes(packet[offset : offset + 2], "big")
        offset += 2
        msg = packet[offset : offset + msg_len]
        if len(msg) != msg_len:
            raise ValueError("truncated message payload")
        events.append(parse_itch_message(msg, flags))
        offset += msg_len

    return events, sequence + message_count
