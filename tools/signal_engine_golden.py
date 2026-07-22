"""Golden model for the deterministic quote-to-order-intent boundary."""


SIDE_BUY = 0
SIDE_SELL = 1


class OrderIntent:
    __slots__ = ("stock_locate", "side", "price", "quantity", "timestamp")

    def __init__(self, stock_locate, side, price, quantity, timestamp):
        self.stock_locate = stock_locate
        self.side = side
        self.price = price
        self.quantity = quantity
        self.timestamp = timestamp


class SignalEngineModel:
    """Small, fail-closed reference model matching the synthesizable policy."""

    def __init__(self, stock_locates):
        if not stock_locates:
            raise ValueError("at least one stock locate is required")
        self.positions = dict((locate, 0) for locate in stock_locates)
        self.evaluated_quote_count = 0
        self.generated_intent_count = 0
        self.control_suppressed_count = 0
        self.market_suppressed_count = 0
        self.risk_suppressed_count = 0
        self.applied_fill_count = 0
        self.untracked_fill_count = 0

    def clear_positions(self):
        for locate in self.positions:
            self.positions[locate] = 0

    def apply_fill(self, stock_locate, side, quantity):
        if stock_locate not in self.positions:
            self.untracked_fill_count += 1
            return

        delta = quantity if side == SIDE_BUY else -quantity
        position = self.positions[stock_locate] + delta
        position = min(max(position, -0x80000000), 0x7FFFFFFF)
        self.positions[stock_locate] = position
        self.applied_fill_count += 1

    def evaluate(
        self,
        stock_locate,
        bid_price,
        bid_shares,
        ask_price,
        ask_shares,
        timestamp,
        feed_healthy,
        strategy_enable,
        kill_switch,
        max_spread_ticks,
        min_top_shares,
        imbalance_shift,
        order_quantity,
        max_abs_position,
    ):
        self.evaluated_quote_count += 1

        if (
            not feed_healthy
            or not strategy_enable
            or kill_switch
            or order_quantity == 0
            or max_abs_position == 0
        ):
            self.control_suppressed_count += 1
            return None

        market_valid = (
            stock_locate in self.positions
            and bid_price != 0
            and ask_price > bid_price
            and bid_shares != 0
            and ask_shares != 0
            and max_spread_ticks != 0
            and ask_price - bid_price <= max_spread_ticks
            and bid_shares >= min_top_shares
            and ask_shares >= min_top_shares
        )
        buy_signal = bid_shares > (ask_shares << imbalance_shift)
        sell_signal = ask_shares > (bid_shares << imbalance_shift)

        if not market_valid or (not buy_signal and not sell_signal):
            self.market_suppressed_count += 1
            return None

        position = self.positions[stock_locate]
        if buy_signal:
            if position + order_quantity > max_abs_position:
                self.risk_suppressed_count += 1
                return None
            intent = OrderIntent(
                stock_locate, SIDE_BUY, ask_price, order_quantity, timestamp
            )
        else:
            if position - order_quantity < -max_abs_position:
                self.risk_suppressed_count += 1
                return None
            intent = OrderIntent(
                stock_locate, SIDE_SELL, bid_price, order_quantity, timestamp
            )

        self.generated_intent_count += 1
        return intent
