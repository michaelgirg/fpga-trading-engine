"""Golden single-symbol top-of-book model for generated replay checks."""

from typing import Iterable, List, Optional

from itch_packets import (
    EVENT_ADD,
    EVENT_CANCEL,
    EVENT_DELETE,
    EVENT_EXECUTE,
    EVENT_REPLACE,
    ParsedEvent,
)


class QuoteUpdate:
    __slots__ = (
        "stock_locate",
        "bid_price",
        "bid_shares",
        "ask_price",
        "ask_shares",
        "timestamp",
    )

    def __init__(
        self,
        stock_locate: int,
        bid_price: int,
        bid_shares: int,
        ask_price: int,
        ask_shares: int,
        timestamp: int,
    ) -> None:
        self.stock_locate = stock_locate
        self.bid_price = bid_price
        self.bid_shares = bid_shares
        self.ask_price = ask_price
        self.ask_shares = ask_shares
        self.timestamp = timestamp

    def pack_u192(self) -> int:
        value = 0
        value |= self.stock_locate & 0xFFFF
        value |= (self.bid_price & 0xFFFFFFFF) << 16
        value |= (self.bid_shares & 0xFFFFFFFF) << 48
        value |= (self.ask_price & 0xFFFFFFFF) << 80
        value |= (self.ask_shares & 0xFFFFFFFF) << 112
        value |= (self.timestamp & 0xFFFFFFFFFFFF) << 144
        return value


class OrderEntry:
    __slots__ = ("stock_locate", "order_ref", "side", "shares", "price")

    def __init__(self, stock_locate: int, order_ref: int, side: int, shares: int, price: int) -> None:
        self.stock_locate = stock_locate
        self.order_ref = order_ref
        self.side = side
        self.shares = shares
        self.price = price


class TopOfBookModel:
    def __init__(self, target_stock_locate: int, table_depth: int = 16) -> None:
        self.target_stock_locate = target_stock_locate
        self.table_depth = table_depth
        self.orders = []  # type: List[OrderEntry]
        self.best_bid_price = 0
        self.best_bid_shares = 0
        self.best_ask_price = 0
        self.best_ask_shares = 0
        self.accepted_event_count = 0
        self.applied_event_count = 0
        self.ignored_event_count = 0
        self.table_overflow_count = 0
        self.quote_update_count = 0

    def apply(self, event: ParsedEvent) -> Optional[QuoteUpdate]:
        self.accepted_event_count += 1

        if event.stock_locate != self.target_stock_locate or event.flags != 0:
            self.ignored_event_count += 1
            return None

        applied = False
        ignored = False
        overflow = False
        existing = self._find_order(event.order_ref)

        if event.event_kind == EVENT_ADD:
            if event.side in (ord("B"), ord("S")) and event.shares != 0 and event.price != 0:
                if existing is not None:
                    existing.side = event.side
                    existing.shares = event.shares
                    existing.price = event.price
                    applied = True
                elif len(self.orders) < self.table_depth:
                    self.orders.append(
                        OrderEntry(
                            event.stock_locate,
                            event.order_ref,
                            event.side,
                            event.shares,
                            event.price,
                        )
                    )
                    applied = True
                else:
                    overflow = True
            else:
                ignored = True
        elif event.event_kind in (EVENT_EXECUTE, EVENT_CANCEL):
            if existing is not None and event.shares != 0:
                if event.shares >= existing.shares:
                    self.orders.remove(existing)
                else:
                    existing.shares -= event.shares
                applied = True
            else:
                ignored = True
        elif event.event_kind == EVENT_DELETE:
            if existing is not None:
                self.orders.remove(existing)
                applied = True
            else:
                ignored = True
        elif event.event_kind == EVENT_REPLACE:
            if existing is not None and event.shares != 0 and event.price != 0:
                existing.shares = event.shares
                existing.price = event.price
                applied = True
            else:
                ignored = True
        else:
            ignored = True

        if overflow:
            self.table_overflow_count += 1
            self.ignored_event_count += 1
            return None

        if ignored:
            self.ignored_event_count += 1
            return None

        if not applied:
            return None

        self.applied_event_count += 1
        bid_price, bid_shares, ask_price, ask_shares = self._compute_best()
        if (
            bid_price != self.best_bid_price
            or bid_shares != self.best_bid_shares
            or ask_price != self.best_ask_price
            or ask_shares != self.best_ask_shares
        ):
            self.best_bid_price = bid_price
            self.best_bid_shares = bid_shares
            self.best_ask_price = ask_price
            self.best_ask_shares = ask_shares
            self.quote_update_count += 1
            return QuoteUpdate(
                self.target_stock_locate,
                bid_price,
                bid_shares,
                ask_price,
                ask_shares,
                event.timestamp,
            )

        return None

    def replay(self, events: Iterable[ParsedEvent]) -> List[QuoteUpdate]:
        quotes = []
        for event in events:
            quote = self.apply(event)
            if quote is not None:
                quotes.append(quote)
        return quotes

    def _find_order(self, order_ref: int) -> Optional[OrderEntry]:
        for order in self.orders:
            if order.order_ref == order_ref and order.stock_locate == self.target_stock_locate:
                return order
        return None

    def _compute_best(self):
        bid_price = 0
        bid_shares = 0
        ask_price = 0
        ask_shares = 0

        for order in self.orders:
            if order.stock_locate != self.target_stock_locate or order.price == 0:
                continue

            if order.side == ord("B"):
                if order.price > bid_price:
                    bid_price = order.price
                    bid_shares = order.shares
                elif order.price == bid_price:
                    bid_shares += order.shares
            elif order.side == ord("S"):
                if ask_price == 0 or order.price < ask_price:
                    ask_price = order.price
                    ask_shares = order.shares
                elif order.price == ask_price:
                    ask_shares += order.shares

        return bid_price, bid_shares, ask_price, ask_shares
