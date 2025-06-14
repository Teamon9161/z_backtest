const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

const Order = @import("order.zig").Order;
const Side = @import("order.zig").Side;
const SnapLevel = @import("level.zig").SnapLevel;

/// 简单的OrderBook实现
/// 使用HashMap + 有序数组的组合方式
pub const SimpleOrderBook = struct {
    allocator: Allocator,
    /// 价格到层级的快速映射 (O(1)查找)
    price_map: HashMap(u64, *SnapLevel), // 使用整数价格避免浮点精度问题
    /// 买单价格层级 (从高到低排序)
    bid_levels: ArrayList(*SnapLevel),
    /// 卖单价格层级 (从低到高排序)
    ask_levels: ArrayList(*SnapLevel),
    /// 价格精度 (tick size)
    tick_size: f64,

    const Self = @This();

    pub fn init(allocator: Allocator, tick_size: f64) Self {
        return Self{
            .allocator = allocator,
            .price_map = HashMap(u64, *SnapLevel).init(allocator),
            .bid_levels = ArrayList(*SnapLevel).init(allocator),
            .ask_levels = ArrayList(*SnapLevel).init(allocator),
            .tick_size = tick_size,
        };
    }

    pub fn deinit(self: *Self) void {
        // 清理所有价格层级
        var iterator = self.price_map.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }

        self.price_map.deinit();
        self.bid_levels.deinit();
        self.ask_levels.deinit();
    }

    /// 将浮点价格转换为整数 (避免浮点精度问题)
    fn priceToInt(self: *const Self, price: f64) u64 {
        return @intFromFloat(@round(price / self.tick_size));
    }

    /// 将整数价格转换为浮点
    fn intToPrice(self: *const Self, price_int: u64) f64 {
        return @as(f64, @floatFromInt(price_int)) * self.tick_size;
    }

    /// 获取或创建价格层级
    fn getOrCreateLevel(self: *Self, price: f64, side: Side) !*SnapLevel {
        const price_int = self.priceToInt(price);

        // 先尝试从映射中获取
        if (self.price_map.get(price_int)) |level| {
            return level;
        }

        // 创建新的价格层级
        const level = try self.allocator.create(SnapLevel);
        level.* = SnapLevel.init(self.allocator);
        level.price = price; // 设置价格

        // 添加到映射
        try self.price_map.put(price_int, level);

        // 添加到有序数组并排序
        switch (side) {
            .buy => {
                try self.bid_levels.append(level);
                // 买单按价格从高到低排序
                std.sort.heap(*SnapLevel, self.bid_levels.items, {}, struct {
                    fn lessThan(_: void, lhs: *SnapLevel, rhs: *SnapLevel) bool {
                        return lhs.price.? > rhs.price.?;
                    }
                }.lessThan);
            },
            .sell => {
                try self.ask_levels.append(level);
                // 卖单按价格从低到高排序
                std.sort.heap(*SnapLevel, self.ask_levels.items, {}, struct {
                    fn lessThan(_: void, lhs: *SnapLevel, rhs: *SnapLevel) bool {
                        return lhs.price.? < rhs.price.?;
                    }
                }.lessThan);
            },
            .none => return error.InvalidSide,
        }

        return level;
    }

    /// 移除空的价格层级
    fn removeEmptyLevel(self: *Self, price: f64, side: Side) void {
        const price_int = self.priceToInt(price);

        if (self.price_map.get(price_int)) |level| {
            if (!level.isEmpty()) return;

            // 从映射中移除
            _ = self.price_map.remove(price_int);

            // 从有序数组中移除
            const target_list = switch (side) {
                .buy => &self.bid_levels,
                .sell => &self.ask_levels,
                .none => return,
            };

            for (target_list.items, 0..) |item_level, i| {
                if (item_level == level) {
                    _ = target_list.swapRemove(i);
                    break;
                }
            }

            // 清理内存
            level.deinit();
            self.allocator.destroy(level);
        }
    }

    /// 添加订单
    pub fn addOrder(self: *Self, order: Order) !void {
        const level = try self.getOrCreateLevel(order.price, order.side);
        try level.addOrder(order);
    }

    /// 取消订单
    pub fn cancelOrder(self: *Self, order_id: u64, price: f64, side: Side) bool {
        const price_int = self.priceToInt(price);

        if (self.price_map.get(price_int)) |level| {
            const removed = level.removeOrder(order_id);

            // 如果层级为空，移除它
            if (level.isEmpty()) {
                self.removeEmptyLevel(price, side);
            }

            return removed;
        }

        return false;
    }

    /// 更新市场数据
    pub fn updateMarketData(self: *Self, price: f64, qty: f64, side: Side) !void {
        if (qty <= 0) {
            // 删除价格层级
            self.removeEmptyLevel(price, side);
        } else {
            // 更新或创建价格层级
            const level = try self.getOrCreateLevel(price, side);
            level.qty = qty;
        }
    }

    /// 获取最优买价
    pub fn getBestBid(self: *const Self) ?struct { price: f64, qty: f64 } {
        if (self.bid_levels.items.len == 0) return null;

        const best_level = self.bid_levels.items[0];
        return .{
            .price = best_level.price.?,
            .qty = best_level.totalQty(),
        };
    }

    /// 获取最优卖价
    pub fn getBestAsk(self: *const Self) ?struct { price: f64, qty: f64 } {
        if (self.ask_levels.items.len == 0) return null;

        const best_level = self.ask_levels.items[0];
        return .{
            .price = best_level.price.?,
            .qty = best_level.totalQty(),
        };
    }

    /// 获取买单深度 (前N档)
    pub fn getBidDepth(self: *const Self, levels: usize) []const *SnapLevel {
        const count = @min(levels, self.bid_levels.items.len);
        return self.bid_levels.items[0..count];
    }

    /// 获取卖单深度 (前N档)
    pub fn getAskDepth(self: *const Self, levels: usize) []const *SnapLevel {
        const count = @min(levels, self.ask_levels.items.len);
        return self.ask_levels.items[0..count];
    }

    /// 获取价差
    pub fn getSpread(self: *const Self) ?f64 {
        const best_bid = self.getBestBid();
        const best_ask = self.getBestAsk();

        if (best_bid != null and best_ask != null) {
            return best_ask.?.price - best_bid.?.price;
        }

        return null;
    }

    /// 获取中间价
    pub fn getMidPrice(self: *const Self) ?f64 {
        const best_bid = self.getBestBid();
        const best_ask = self.getBestAsk();

        if (best_bid != null and best_ask != null) {
            return (best_bid.?.price + best_ask.?.price) / 2.0;
        }

        return null;
    }

    /// 打印订单簿状态 (调试用)
    pub fn debugPrint(self: *const Self) void {
        std.debug.print("=== OrderBook ===\n", .{});

        std.debug.print("Asks (sell orders):\n", .{});
        // 卖单从高到低显示 (显示时反转)
        var i = self.ask_levels.items.len;
        while (i > 0) {
            i -= 1;
            const level = self.ask_levels.items[i];
            std.debug.print("  {d:.4} | {d:.2}\n", .{ level.price.?, level.totalQty() });
        }

        const spread = self.getSpread();
        if (spread) |s| {
            std.debug.print("--- Spread: {d:.4} ---\n", .{s});
        } else {
            std.debug.print("--- No Spread ---\n", .{});
        }

        std.debug.print("Bids (buy orders):\n", .{});
        for (self.bid_levels.items) |level| {
            std.debug.print("  {d:.4} | {d:.2}\n", .{ level.price.?, level.totalQty() });
        }

        std.debug.print("=================\n", .{});
    }
};

// 测试
test "simple orderbook basic operations" {
    const allocator = std.testing.allocator;

    var book = SimpleOrderBook.init(allocator, 0.01);
    defer book.deinit();

    // 添加买单
    const buy_order = Order{
        .order_id = 1,
        .price = 100.0,
        .qty = 10.0,
        .side = .buy,
    };

    try book.addOrder(buy_order);

    // 检查最优买价
    const best_bid = book.getBestBid();
    try std.testing.expect(best_bid != null);
    try std.testing.expectEqual(@as(f64, 100.0), best_bid.?.price);
    try std.testing.expectEqual(@as(f64, 10.0), best_bid.?.qty);

    // 添加卖单
    const sell_order = Order{
        .order_id = 2,
        .price = 100.5,
        .qty = 5.0,
        .side = .sell,
    };

    try book.addOrder(sell_order);

    // 检查最优卖价
    const best_ask = book.getBestAsk();
    try std.testing.expect(best_ask != null);
    try std.testing.expectEqual(@as(f64, 100.5), best_ask.?.price);

    // 检查价差
    const spread = book.getSpread();
    try std.testing.expect(spread != null);
    try std.testing.expectEqual(@as(f64, 0.5), spread.?);
}

test "simple orderbook market data" {
    const allocator = std.testing.allocator;

    var book = SimpleOrderBook.init(allocator, 0.01);
    defer book.deinit();

    // 更新市场数据
    try book.updateMarketData(99.95, 100.0, .buy);
    try book.updateMarketData(100.05, 150.0, .sell);

    // 检查市场数据
    const best_bid = book.getBestBid();
    const best_ask = book.getBestAsk();

    try std.testing.expect(best_bid != null);
    try std.testing.expect(best_ask != null);
    try std.testing.expectEqual(@as(f64, 99.95), best_bid.?.price);
    try std.testing.expectEqual(@as(f64, 100.0), best_bid.?.qty);
    try std.testing.expectEqual(@as(f64, 100.05), best_ask.?.price);
    try std.testing.expectEqual(@as(f64, 150.0), best_ask.?.qty);
}

test "simple orderbook depth" {
    const allocator = std.testing.allocator;

    var book = SimpleOrderBook.init(allocator, 0.01);
    defer book.deinit();

    // 添加多档买单
    try book.updateMarketData(100.0, 100.0, .buy);
    try book.updateMarketData(99.9, 200.0, .buy);
    try book.updateMarketData(99.8, 150.0, .buy);

    // 添加多档卖单
    try book.updateMarketData(100.1, 120.0, .sell);
    try book.updateMarketData(100.2, 180.0, .sell);

    // 获取深度
    const bid_depth = book.getBidDepth(3);
    const ask_depth = book.getAskDepth(2);

    try std.testing.expectEqual(@as(usize, 3), bid_depth.len);
    try std.testing.expectEqual(@as(usize, 2), ask_depth.len);

    // 验证排序 (买单从高到低)
    try std.testing.expectEqual(@as(f64, 100.0), bid_depth[0].price);
    try std.testing.expectEqual(@as(f64, 99.9), bid_depth[1].price);
    try std.testing.expectEqual(@as(f64, 99.8), bid_depth[2].price);

    // 验证排序 (卖单从低到高)
    try std.testing.expectEqual(@as(f64, 100.1), ask_depth[0].price);
    try std.testing.expectEqual(@as(f64, 100.2), ask_depth[1].price);
}

comptime {
    std.testing.refAllDecls(@This());
}
