import os
import sys
import unittest


TOOLS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tools")
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

from exchange_simulator import (
    COMMAND_CANCEL,
    COMMAND_NEW,
    EVENT_ACK,
    EVENT_CANCEL_ACK,
    EVENT_FILL,
    EVENT_REJECT,
    AdversarialExchangeSimulator,
    OrderCommand,
    DeterministicExchangeSimulator,
)


class ExchangeSimulatorTest(unittest.TestCase):
    def new_command(self, order_id, quantity=10):
        return OrderCommand(
            COMMAND_NEW,
            order_id,
            0x1111,
            0,
            101,
            quantity,
            timestamp=1234,
        )

    def test_ack_and_partial_fill_schedule(self):
        exchange = DeterministicExchangeSimulator(
            ack_latency=2,
            fill_latency=3,
            partial_fill_quantity=4,
        )
        self.assertTrue(exchange.submit(self.new_command(1, quantity=10)))
        self.assertEqual(exchange.step(), [])
        events = exchange.step()
        self.assertEqual([event.event_type for event in events], [EVENT_ACK])
        self.assertEqual(exchange.orders[1].state, "live")

        events = exchange.advance(3)
        self.assertEqual(
            [(event.event_type, event.quantity) for event in events],
            [(EVENT_FILL, 4)],
        )
        self.assertEqual(exchange.orders[1].leaves_quantity, 6)

        events = exchange.advance(3)
        self.assertEqual(
            [(event.event_type, event.quantity) for event in events],
            [(EVENT_FILL, 6)],
        )
        self.assertNotIn(1, exchange.orders)

    def test_reject_policy(self):
        exchange = DeterministicExchangeSimulator(reject_order_ids=[7])
        self.assertFalse(exchange.submit(self.new_command(7)))
        events = exchange.advance(2)
        self.assertEqual([event.event_type for event in events], [EVENT_REJECT])
        self.assertNotIn(7, exchange.orders)

    def test_cancel_acknowledgment(self):
        exchange = DeterministicExchangeSimulator(
            ack_latency=1,
            cancel_latency=2,
            auto_fill=False,
        )
        command = self.new_command(9)
        self.assertTrue(exchange.submit(command))
        self.assertEqual(exchange.step()[0].event_type, EVENT_ACK)

        cancel = OrderCommand(
            COMMAND_CANCEL,
            command.order_id,
            command.stock_locate,
            command.side,
            command.price,
            command.quantity,
        )
        self.assertTrue(exchange.submit(cancel))
        self.assertEqual(exchange.orders[9].state, "cancel_pending")
        events = exchange.advance(2)
        self.assertEqual([event.event_type for event in events], [EVENT_CANCEL_ACK])
        self.assertNotIn(9, exchange.orders)

    def test_invalid_commands_fail_closed(self):
        exchange = DeterministicExchangeSimulator(auto_fill=False)
        self.assertFalse(exchange.submit(self.new_command(0)))
        unknown_cancel = OrderCommand(
            COMMAND_CANCEL, 123, 0x1111, 0, 101, 10
        )
        self.assertFalse(exchange.submit(unknown_cancel))
        with self.assertRaises(ValueError):
            exchange.submit(OrderCommand(99, 1, 0x1111, 0, 101, 10))

    def test_response_backpressure_preserves_order(self):
        exchange = DeterministicExchangeSimulator(
            ack_latency=1,
            fill_latency=1,
            partial_fill_quantity=4,
        )
        self.assertTrue(exchange.submit(self.new_command(31, quantity=10)))
        self.assertEqual(exchange.step(event_ready=False), [])
        self.assertEqual(exchange.orders[31].state, "pending")
        self.assertEqual(exchange.advance(5, event_ready=False), [])
        self.assertGreaterEqual(exchange.pending_event_count, 3)

        events = []
        while not exchange.idle:
            events.extend(exchange.step(event_ready=True, max_events=1))
        self.assertEqual(
            [event.event_type for event in events],
            [EVENT_ACK, EVENT_FILL, EVENT_FILL],
        )
        self.assertEqual([event.quantity for event in events[1:]], [4, 6])
        self.assertNotIn(31, exchange.orders)

    def test_seeded_adversarial_replay_is_reproducible(self):
        first = AdversarialExchangeSimulator(seed=77, reject_probability=0.2)
        second = AdversarialExchangeSimulator(seed=77, reject_probability=0.2)
        first_accepts = []
        second_accepts = []
        for order_id in range(1, 41):
            command = self.new_command(order_id, quantity=1 + order_id % 17)
            first_accepts.append(first.submit(command))
            second_accepts.append(second.submit(command))
            first.step(event_ready=(order_id % 3 != 0), max_events=1)
            second.step(event_ready=(order_id % 3 != 0), max_events=1)
        self.assertEqual(first_accepts, second_accepts)

        first_events = []
        second_events = []
        while not first.idle or not second.idle:
            first_events.extend(first.step(max_events=1))
            second_events.extend(second.step(max_events=1))
        first_trace = [
            (event.event_type, event.order_id, event.quantity, event.cycle)
            for event in first_events
        ]
        second_trace = [
            (event.event_type, event.order_id, event.quantity, event.cycle)
            for event in second_events
        ]
        self.assertEqual(first_trace, second_trace)

    def test_adversarial_replay_conserves_every_share(self):
        for seed in (1, 7, 77, 991, 20260725):
            exchange = AdversarialExchangeSimulator(
                seed=seed,
                ack_latency_range=(1, 13),
                fill_latency_range=(1, 17),
                reject_probability=0.15,
                max_fill_slices=6,
            )
            accepted = {}
            rejected = set()
            delivered = []

            for order_id in range(1, 301):
                quantity = 1 + (((order_id + seed) * 37) % 1000)
                command = self.new_command(order_id, quantity=quantity)
                if exchange.submit(command):
                    accepted[order_id] = quantity
                else:
                    rejected.add(order_id)
                delivered.extend(
                    exchange.step(
                        event_ready=(order_id % 5 not in (0, 1)),
                        max_events=1,
                    )
                )

            cycles = 0
            while not exchange.idle and cycles < 10000:
                delivered.extend(
                    exchange.step(
                        event_ready=(cycles % 7 != 0), max_events=1
                    )
                )
                cycles += 1
            self.assertTrue(exchange.idle, "seed %d did not drain" % seed)

            acknowledgments = set()
            observed_rejects = set()
            filled = {}
            due_cycles = []
            for event in delivered:
                due_cycles.append(event.cycle)
                if event.event_type == EVENT_ACK:
                    self.assertNotIn(event.order_id, acknowledgments)
                    acknowledgments.add(event.order_id)
                elif event.event_type == EVENT_REJECT:
                    observed_rejects.add(event.order_id)
                elif event.event_type == EVENT_FILL:
                    filled[event.order_id] = (
                        filled.get(event.order_id, 0) + event.quantity
                    )

            self.assertEqual(acknowledgments, set(accepted))
            self.assertEqual(observed_rejects, rejected)
            self.assertEqual(filled, accepted)
            self.assertEqual(exchange.orders, {})
            self.assertEqual(due_cycles, sorted(due_cycles))

    def test_adversarial_cancel_replay_under_backpressure(self):
        exchange = AdversarialExchangeSimulator(
            seed=5150,
            ack_latency_range=(1, 9),
            cancel_latency_range=(1, 11),
            reject_probability=0.0,
            auto_fill=False,
        )
        order_ids = set(range(1, 121))
        for order_id in sorted(order_ids):
            self.assertTrue(exchange.submit(self.new_command(order_id)))
            exchange.step(event_ready=(order_id % 4 != 0), max_events=1)

        while not exchange.idle:
            exchange.step(event_ready=True, max_events=1)
        self.assertEqual(set(exchange.orders), order_ids)
        self.assertTrue(
            all(order.state == "live" for order in exchange.orders.values())
        )

        delivered = []
        for order_id in sorted(order_ids):
            order = exchange.orders[order_id]
            cancel = OrderCommand(
                COMMAND_CANCEL,
                order_id,
                order.stock_locate,
                order.side,
                order.price,
                order.leaves_quantity,
            )
            self.assertTrue(exchange.submit(cancel))
            delivered.extend(
                exchange.step(
                    event_ready=(order_id % 6 not in (0, 1)), max_events=1
                )
            )

        cycles = 0
        while not exchange.idle and cycles < 5000:
            delivered.extend(
                exchange.step(event_ready=(cycles % 5 != 0), max_events=1)
            )
            cycles += 1
        cancel_ids = [
            event.order_id
            for event in delivered
            if event.event_type == EVENT_CANCEL_ACK
        ]
        self.assertTrue(exchange.idle)
        self.assertEqual(set(cancel_ids), order_ids)
        self.assertEqual(len(cancel_ids), len(order_ids))
        self.assertEqual(exchange.orders, {})


if __name__ == "__main__":
    unittest.main()
