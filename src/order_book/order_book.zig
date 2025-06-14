const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

const Order = @import("order.zig").Order;
const Side = @import("order.zig").Side;
const SnapLevel = @import("level.zig").SnapLevel;
const OrderLevel = @import("level.zig").OrderLevel;

pub const BookOption = struct {
    tick_size: f64 = 0.0001,
    lot_size: f64 = 1,
};

/// 单侧的订单簿
pub fn SideBook(comptime Level: type, comptime side: Side) type {
    return struct {
        allocator: Allocator,
        price_map: HashMap(u64, *Level),
        levels: ArrayList(*Level),
        tick_size: f64,
        lot_size: f64 = 1,

        const Self = @This();

        pub fn init(allocator: Allocator, opt: BookOption) Self {
            return .{
                .allocator = allocator,
                .price_map = HashMap(u64, *Level).init(allocator),
                .levels = ArrayList(*Level).init(allocator),
                .tick_size = opt.tick_size,
                .lot_size = opt.lot_size,
            };
        }

        pub fn deinit(self: *Self) void {
            var iterator = self.price_map.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            self.price_map.deinit();
            self.levels.deinit();
        }

        pub fn bestPrice(self: *const Self, nth: u32) ?f64 {
            if (nth >= self.levels.items.len) return null;
            return self.levels.items[nth].price;
        }

        pub fn bestQty(self: *const Self, nth: u32) ?f64 {
            if (nth >= self.levels.items.len) return null;
            return self.levels.items[nth].totalQty();
        }

        pub fn getLevel(self: *Self, price: f64) !*Level {
            const price_int = self.priceToInt(price);
            // 先尝试从映射中获取
            if (self.price_map.get(price_int)) |level| {
                return level;
            }
            // 创建新的价格层级
            const level = try self.allocator.create(Level);
            level.* = Level.init(price, self.allocator);

            // 添加到映射
            try self.price_map.put(price_int, level);

            // 添加到有序数组并排序
            switch (side) {
                .buy => {
                    try self.levels.append(level);
                    // 买单按价格从高到低排序
                    std.sort.heap(*Level, self.levels.items, {}, struct {
                        fn lessThan(_: void, lhs: *Level, rhs: *Level) bool {
                            return lhs.price > rhs.price;
                        }
                    }.lessThan);
                },
                .sell => {
                    try self.levels.append(level);
                    // 卖单按价格从低到高排序
                    std.sort.heap(*Level, self.levels.items, {}, struct {
                        fn lessThan(_: void, lhs: *Level, rhs: *Level) bool {
                            return lhs.price < rhs.price;
                        }
                    }.lessThan);
                },
                .none => return error.InvalidSide,
            }

            return level;
        }

        /// 往订单簿中添加订单，注意这里并不检查订单的方向
        /// 调用的时候需要确保订单方向匹配
        pub fn addOrder(self: *Self, order: Order) !void {
            const level = try self.getLevel(order.price);
            try level.addOrder(order);
        }

        /// 获得深度(前N档)
        pub fn getDepth(self: *const Self, depth: u32) []const *Level {
            const count = @min(depth, self.levels.items.len);
            return self.levels.items[0..count];
        }

        /// 将浮点价格转换为整数 (避免浮点精度问题)
        fn priceToInt(self: *const Self, price: f64) u64 {
            return @intFromFloat(@round(price / self.tick_size));
        }

        /// 将整数价格转换为浮点
        fn intToPrice(self: *const Self, price_int: u64) f64 {
            return @as(f64, @floatFromInt(price_int)) * self.tick_size;
        }

        /// 根据 tick_size 四舍五入价格
        fn roundPrice(self: *const Self, price: f64) f64 {
            return @round(price / self.tick_size) * self.tick_size;
        }

        /// 根据 lot_size 四舍五入数量
        fn roundQty(self: *const Self, qty: f64) f64 {
            return if (self.lot_size < 1) @round(qty / self.lot_size) * self.lot_size else qty;
        }

        pub fn debugPrint(self: *const Self) void {
            switch (side) {
                .buy => {
                    for (self.levels.items) |level| {
                        std.debug.print("  {d} @ {d}\n", .{ self.roundPrice(level.price), self.roundQty(level.totalQty()) });
                    }
                },
                .sell => {
                    // 对于sell side需要逆序打印
                    var i: usize = self.levels.items.len;
                    while (i > 0) : (i -= 1) {
                        const level = self.levels.items[i - 1];
                        std.debug.print("  {d} @ {d}\n", .{ self.roundPrice(level.price), self.roundQty(level.totalQty()) });
                    }
                },
                .none => {},
            }
        }
    };
}

test "side bid book" {
    var book = SideBook(OrderLevel, .buy).init(std.testing.allocator, .{});
    defer book.deinit();
    try book.addOrder(.{ .price = 100, .qty = 100 });
    try std.testing.expectEqual(book.bestPrice(0), 100);
    try std.testing.expectEqual(book.bestQty(0), 100);
    try book.addOrder(.{ .price = 100, .qty = 200 });
    try std.testing.expectEqual(book.bestPrice(0), 100);
    try std.testing.expectEqual(book.bestQty(0), 300);
    try std.testing.expectEqual(book.bestPrice(1), null);
    try std.testing.expectEqual(book.bestQty(1), null);
    try book.addOrder(.{ .price = 99, .qty = 200 });
    try std.testing.expectEqual(book.bestPrice(0), 100);
    try book.addOrder(.{ .price = 101, .qty = 200 });
    try std.testing.expectEqual(book.bestPrice(0), 101);
    try std.testing.expectEqual(book.bestPrice(2), 99);
}

test "side ask book" {
    var book = SideBook(OrderLevel, .sell).init(std.testing.allocator, .{});
    defer book.deinit();
    try book.addOrder(.{ .price = 100, .qty = 100, .side = .sell });
    try std.testing.expectEqual(book.bestPrice(0), 100);
    try std.testing.expectEqual(book.bestQty(0), 100);
    try book.addOrder(.{ .price = 100, .qty = 200, .side = .sell });
    try std.testing.expectEqual(book.bestPrice(0), 100);
    try std.testing.expectEqual(book.bestQty(0), 300);
    try std.testing.expectEqual(book.bestPrice(1), null);
    try std.testing.expectEqual(book.bestQty(1), null);
    try book.addOrder(.{ .price = 101, .qty = 200, .side = .sell });
    try std.testing.expectEqual(book.bestPrice(0), 100);
    try book.addOrder(.{ .price = 98, .qty = 200, .side = .sell });
    try std.testing.expectEqual(book.bestPrice(0), 98);
    try std.testing.expectEqual(book.bestPrice(2), 101);
}

pub fn OrderBook(comptime Level: type) type {
    return struct {
        allocator: Allocator,
        bid_book: SideBook(Level, .buy),
        ask_book: SideBook(Level, .sell),
        /// 价格精度 (tick size)
        tick_size: f64,
        /// 数量精度 (lot size)
        lot_size: f64,
        const Self = @This();

        pub fn init(allocator: Allocator, opt: BookOption) Self {
            return .{
                .allocator = allocator,
                .bid_book = SideBook(Level, .buy).init(allocator, opt),
                .ask_book = SideBook(Level, .sell).init(allocator, opt),
                .tick_size = opt.tick_size,
                .lot_size = opt.lot_size,
            };
        }

        pub fn deinit(self: *Self) void {
            self.bid_book.deinit();
            self.ask_book.deinit();
        }

        pub fn bid(self: *const Self, nth: u32) ?f64 {
            return self.bid_book.bestPrice(nth);
        }

        pub fn ask(self: *const Self, nth: u32) ?f64 {
            return self.ask_book.bestPrice(nth);
        }

        pub fn bidQty(self: *const Self, nth: u32) ?f64 {
            return self.bid_book.bestQty(nth);
        }

        pub fn askQty(self: *const Self, nth: u32) ?f64 {
            return self.ask_book.bestQty(nth);
        }

        pub fn getBidDepth(self: *const Self, depth: u32) []const *Level {
            return self.bid_book.getDepth(depth);
        }

        pub fn getAskDepth(self: *const Self, depth: u32) []const *Level {
            return self.ask_book.getDepth(depth);
        }

        pub fn addOrder(self: *Self, order: Order) !void {
            switch (order.side) {
                .buy => try self.bid_book.addOrder(order),
                .sell => try self.ask_book.addOrder(order),
                .none => return error.InvalidSide,
            }
        }

        /// 获取盘口买卖价差
        pub fn getSpread(self: *const Self) ?f64 {
            const best_bid = self.bid(0);
            const best_ask = self.ask(0);

            if (best_bid != null and best_ask != null) {
                return best_ask.? - best_bid.?;
            }

            return null;
        }

        /// 获取中间价
        pub fn getMidPrice(self: *const Self) ?f64 {
            const best_bid = self.bid(0);
            const best_ask = self.ask(0);
            if (best_bid != null and best_ask != null) {
                return (best_bid.? + best_ask.?) * 0.5;
            }

            return null;
        }

        pub fn debugPrint(self: *const Self) void {
            std.debug.print("=== OrderBook ===\n", .{});
            self.ask_book.debugPrint();
            // 打印价差信息
            if (self.getSpread()) |spread| {
                const rounded_spread = self.bid_book.roundPrice(spread);
                std.debug.print("--- Spread: {d} ---\n", .{rounded_spread});
            } else {
                std.debug.print("--- No Spread ---\n", .{});
            }

            self.bid_book.debugPrint();

            std.debug.print("=================\n", .{});
        }
    };
}

test "order book" {
    const equal = std.testing.expectEqual;
    var book = OrderBook(OrderLevel).init(std.testing.allocator, .{});
    defer book.deinit();
    try book.addOrder(.{ .price = 100, .qty = 100, .side = .buy });
    try book.addOrder(.{ .price = 100, .qty = 200, .side = .buy });
    try book.addOrder(.{ .price = 99, .qty = 200, .side = .buy });
    try book.addOrder(.{ .price = 101, .qty = 200, .side = .buy });
    try book.addOrder(.{ .price = 103, .qty = 200, .side = .sell });
    try book.addOrder(.{ .price = 105, .qty = 200, .side = .sell });
    try equal(book.bid(0), 101);
    try equal(book.bidQty(1), 300);
    try equal(book.ask(0), 103);
    try equal(book.askQty(0), 200);
    try equal(book.ask(1), 105);
    try equal(book.getSpread(), 2);
    try equal(book.getMidPrice(), 102);
    book.debugPrint();
}
