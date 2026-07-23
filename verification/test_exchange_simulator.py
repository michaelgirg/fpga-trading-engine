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


if __name__ == "__main__":
    unittest.main()
