"""Deterministic exchange-side model for order-lifecycle verification."""

import heapq
import random
from collections import deque


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
        self._ready_events = deque()

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

    def step(self, event_ready=True, max_events=None):
        """Advance one cycle and transfer due events through a ready boundary."""
        if max_events is not None and max_events < 0:
            raise ValueError("max_events must be nonnegative")
        self.cycle += 1
        while self._scheduled_events and self._scheduled_events[0][0] <= self.cycle:
            _, _, event = heapq.heappop(self._scheduled_events)
            self._ready_events.append(event)

        if not event_ready:
            return []

        due = []
        while self._ready_events and (
            max_events is None or len(due) < max_events
        ):
            event = self._ready_events.popleft()
            self._apply_event(event)
            due.append(event)
        return due

    def advance(self, cycles, event_ready=True, max_events=None):
        """Advance multiple cycles and return events in time/sequence order."""
        if cycles < 0:
            raise ValueError("cycles must be nonnegative")
        events = []
        for _ in range(cycles):
            events.extend(
                self.step(event_ready=event_ready, max_events=max_events)
            )
        return events

    @property
    def pending_event_count(self):
        return len(self._scheduled_events) + len(self._ready_events)

    @property
    def idle(self):
        return self.pending_event_count == 0


class AdversarialExchangeSimulator(DeterministicExchangeSimulator):
    """Seeded venue model with jitter, rejects, partial fills, and backpressure."""

    def __init__(
        self,
        seed=1,
        ack_latency_range=(1, 8),
        fill_latency_range=(1, 12),
        cancel_latency_range=(1, 8),
        reject_probability=0.1,
        max_fill_slices=4,
        auto_fill=True,
    ):
        ranges = (
            ack_latency_range,
            fill_latency_range,
            cancel_latency_range,
        )
        if any(len(value) != 2 or value[0] < 1 or value[1] < value[0]
               for value in ranges):
            raise ValueError("latency ranges must be positive (minimum, maximum)")
        if reject_probability < 0.0 or reject_probability > 1.0:
            raise ValueError("reject_probability must be between zero and one")
        if max_fill_slices < 1:
            raise ValueError("max_fill_slices must be positive")

        super(AdversarialExchangeSimulator, self).__init__(
            ack_latency=ack_latency_range[0],
            fill_latency=fill_latency_range[0],
            cancel_latency=cancel_latency_range[0],
            auto_fill=False,
        )
        self.random = random.Random(seed)
        self.ack_latency_range = ack_latency_range
        self.fill_latency_range = fill_latency_range
        self.cancel_latency_range = cancel_latency_range
        self.reject_probability = reject_probability
        self.max_fill_slices = max_fill_slices
        self.adversarial_auto_fill = auto_fill

    def _delay(self, bounds):
        return self.random.randint(bounds[0], bounds[1])

    def _fill_quantities(self, quantity):
        slices = self.random.randint(1, min(self.max_fill_slices, quantity))
        quantities = []
        remaining = quantity
        for index in range(slices - 1):
            remaining_slices = slices - index - 1
            fill = self.random.randint(1, remaining - remaining_slices)
            quantities.append(fill)
            remaining -= fill
        quantities.append(remaining)
        return quantities

    def submit(self, command):
        self.command_count += 1

        if command.command_type == COMMAND_NEW:
            invalid = (
                command.order_id == 0
                or command.quantity <= 0
                or command.order_id in self.orders
                or command.order_id in self.reject_order_ids
            )
            if invalid or self.random.random() < self.reject_probability:
                self._schedule(
                    self.cycle + self._delay(self.ack_latency_range),
                    EVENT_REJECT,
                    command.order_id,
                )
                return False

            order = SimOrder(command)
            self.orders[command.order_id] = order
            ack_cycle = self.cycle + self._delay(self.ack_latency_range)
            self._schedule(ack_cycle, EVENT_ACK, command.order_id)

            if self.adversarial_auto_fill:
                fill_cycle = ack_cycle
                for quantity in self._fill_quantities(order.quantity):
                    fill_cycle += self._delay(self.fill_latency_range)
                    self._schedule(
                        fill_cycle,
                        EVENT_FILL,
                        command.order_id,
                        price=command.price,
                        quantity=quantity,
                    )
            return True

        if command.command_type == COMMAND_CANCEL:
            order = self.orders.get(command.order_id)
            if order is None or order.state not in ("pending", "live"):
                return False
            order.state = "cancel_pending"
            self._schedule(
                self.cycle + self._delay(self.cancel_latency_range),
                EVENT_CANCEL_ACK,
                command.order_id,
            )
            return True

        raise ValueError("unknown command type: %r" % (command.command_type,))
