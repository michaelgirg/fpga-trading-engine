"""Deterministic exchange-side model for order-lifecycle verification."""

import heapq


COMMAND_NEW = 0
COMMAND_CANCEL = 1

EVENT_ACK = 0
EVENT_REJECT = 1
EVENT_FILL = 2
EVENT_CANCEL_ACK = 3

SIDE_BUY = 0
SIDE_SELL = 1


class OrderCommand:
    __slots__ = (
        "command_type",
        "order_id",
        "stock_locate",
        "side",
        "price",
        "quantity",
        "timestamp",
    )

    def __init__(
        self,
        command_type,
        order_id,
        stock_locate,
        side,
        price,
        quantity,
        timestamp=0,
    ):
        self.command_type = command_type
        self.order_id = order_id
        self.stock_locate = stock_locate
        self.side = side
        self.price = price
        self.quantity = quantity
        self.timestamp = timestamp


class ExchangeEvent:
    __slots__ = ("event_type", "order_id", "price", "quantity", "cycle")

    def __init__(self, event_type, order_id, price=0, quantity=0, cycle=0):
        self.event_type = event_type
        self.order_id = order_id
        self.price = price
        self.quantity = quantity
        self.cycle = cycle


class SimOrder:
    __slots__ = (
        "order_id",
        "stock_locate",
        "side",
        "price",
        "quantity",
        "leaves_quantity",
        "state",
    )

    def __init__(self, command):
        self.order_id = command.order_id
        self.stock_locate = command.stock_locate
        self.side = command.side
        self.price = command.price
        self.quantity = command.quantity
        self.leaves_quantity = command.quantity
        self.state = "pending"


class DeterministicExchangeSimulator:
    """Cycle-driven venue model with deterministic response scheduling."""

    def __init__(
        self,
        ack_latency=2,
        fill_latency=2,
        cancel_latency=2,
        auto_fill=True,
        partial_fill_quantity=None,
        reject_order_ids=None,
    ):
        if ack_latency < 1 or fill_latency < 1 or cancel_latency < 1:
            raise ValueError("all exchange latencies must be positive")
        self.ack_latency = ack_latency
        self.fill_latency = fill_latency
        self.cancel_latency = cancel_latency
        self.auto_fill = auto_fill
        self.partial_fill_quantity = partial_fill_quantity
        self.reject_order_ids = set(reject_order_ids or [])
        self.cycle = 0
        self.orders = {}
        self.command_count = 0
        self._event_sequence = 0
        self._scheduled_events = []

    def _schedule(self, due_cycle, event_type, order_id, price=0, quantity=0):
        event = ExchangeEvent(
            event_type, order_id, price=price, quantity=quantity, cycle=due_cycle
        )
        heapq.heappush(
            self._scheduled_events,
            (due_cycle, self._event_sequence, event),
        )
        self._event_sequence += 1

    def submit(self, command):
        """Accept a gateway command and schedule its deterministic response."""
        self.command_count += 1

        if command.command_type == COMMAND_NEW:
            if (
                command.order_id == 0
                or command.quantity <= 0
                or command.order_id in self.orders
                or command.order_id in self.reject_order_ids
            ):
                self._schedule(
                    self.cycle + self.ack_latency,
                    EVENT_REJECT,
                    command.order_id,
                )
                return False

            order = SimOrder(command)
            self.orders[command.order_id] = order
            ack_cycle = self.cycle + self.ack_latency
            self._schedule(ack_cycle, EVENT_ACK, command.order_id)

            if self.auto_fill:
                first_fill = order.quantity
                if self.partial_fill_quantity is not None:
                    first_fill = min(self.partial_fill_quantity, order.quantity)
                self._schedule(
                    ack_cycle + self.fill_latency,
                    EVENT_FILL,
                    command.order_id,
                    price=command.price,
                    quantity=first_fill,
                )
                remaining = order.quantity - first_fill
                if remaining:
                    self._schedule(
                        ack_cycle + 2 * self.fill_latency,
                        EVENT_FILL,
                        command.order_id,
                        price=command.price,
                        quantity=remaining,
                    )
            return True

        if command.command_type == COMMAND_CANCEL:
            order = self.orders.get(command.order_id)
            if order is None or order.state not in ("pending", "live"):
                return False
            order.state = "cancel_pending"
            self._schedule(
                self.cycle + self.cancel_latency,
                EVENT_CANCEL_ACK,
                command.order_id,
            )
            return True

        raise ValueError("unknown command type: %r" % (command.command_type,))

    def _apply_event(self, event):
        order = self.orders.get(event.order_id)
        if event.event_type == EVENT_ACK:
            if order is not None and order.state == "pending":
                order.state = "live"
        elif event.event_type == EVENT_REJECT:
            self.orders.pop(event.order_id, None)
        elif event.event_type == EVENT_FILL:
            if order is not None:
                applied = min(event.quantity, order.leaves_quantity)
                order.leaves_quantity -= applied
                if order.leaves_quantity == 0:
                    self.orders.pop(event.order_id, None)
        elif event.event_type == EVENT_CANCEL_ACK:
            self.orders.pop(event.order_id, None)

    def step(self):
        """Advance one cycle and return every event due on that cycle."""
        self.cycle += 1
        due = []
        while self._scheduled_events and self._scheduled_events[0][0] <= self.cycle:
            _, _, event = heapq.heappop(self._scheduled_events)
            self._apply_event(event)
            due.append(event)
        return due

    def advance(self, cycles):
        """Advance multiple cycles and return events in time/sequence order."""
        if cycles < 0:
            raise ValueError("cycles must be nonnegative")
        events = []
        for _ in range(cycles):
            events.extend(self.step())
        return events
