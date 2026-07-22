import os
import sys
import unittest


TOOLS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tools")
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

from signal_engine_golden import SIDE_BUY, SIDE_SELL, SignalEngineModel


class SignalEngineGoldenTest(unittest.TestCase):
    def setUp(self):
        self.model = SignalEngineModel([0x1111, 0x2222])
        self.config = dict(
            feed_healthy=True,
            strategy_enable=True,
            kill_switch=False,
            max_spread_ticks=5,
            min_top_shares=50,
            imbalance_shift=1,
            order_quantity=10,
            max_abs_position=100,
        )

    def evaluate(self, bid_shares, ask_shares, **overrides):
        values = dict(self.config)
        values.update(overrides)
        return self.model.evaluate(
            0x1111, 100, bid_shares, 102, ask_shares, 123, **values
        )

    def test_buy_sell_and_risk_limits(self):
        intent = self.evaluate(400, 100)
        self.assertEqual((intent.side, intent.price), (SIDE_BUY, 102))

        self.model.apply_fill(0x1111, SIDE_BUY, 95)
        self.assertIsNone(self.evaluate(400, 100))
        self.assertEqual(self.model.risk_suppressed_count, 1)

        intent = self.evaluate(100, 400)
        self.assertEqual((intent.side, intent.price), (SIDE_SELL, 100))

    def test_fail_closed_and_market_filters(self):
        self.assertIsNone(self.evaluate(400, 100, strategy_enable=False))
        self.assertIsNone(self.evaluate(400, 100, feed_healthy=False))
        self.assertIsNone(self.evaluate(100, 100))
        self.assertEqual(self.model.control_suppressed_count, 2)
        self.assertEqual(self.model.market_suppressed_count, 1)

    def test_fill_accounting_and_clear(self):
        self.model.apply_fill(0x1111, SIDE_BUY, 25)
        self.model.apply_fill(0x9999, SIDE_SELL, 5)
        self.assertEqual(self.model.positions[0x1111], 25)
        self.assertEqual(self.model.applied_fill_count, 1)
        self.assertEqual(self.model.untracked_fill_count, 1)
        self.model.clear_positions()
        self.assertEqual(self.model.positions[0x1111], 0)


if __name__ == "__main__":
    unittest.main()
