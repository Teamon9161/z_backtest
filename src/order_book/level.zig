const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Order = @import("order.zig").Order;

/// 快照级别 - 包含市场数据和策略订单
pub const SnapLevel = struct {
    /// 价格 (可选，用于OrderBook场景)
    price: ?f64 = null,
    /// 市场真实挂单总量
    qty: f64,
    /// 策略订单列表
    orders: ?ArrayList(Order) = null,
    /// 内存分配器
    allocator: Allocator,
    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self.initWithQty(0, allocator);
    }

    pub fn initWithQty(qty: f64, allocator: Allocator) Self {
        return .{
            .qty = qty,
            .orders = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        if (self.orders) |orders| {
            orders.deinit();
        }
    }

    /// 检查是否为空
    pub fn isEmpty(self: *const Self) bool {
        return (self.qty == 0) and (self.orders == null or self.orders.?.items.len == 0);
    }

    /// 获取总数量
    pub fn totalQty(self: *const Self) f64 {
        var sum: f64 = self.qty;
        if (self.orders) |orders| {
            for (orders.items) |current_order| {
                sum += current_order.remainQty();
            }
        }
        return sum;
    }

    /// 获取所有策略订单
    pub fn getOrders(self: *const Self) ?[]const Order {
        return if (self.orders) |orders| orders.items else null;
    }

    /// 添加订单
    pub fn addOrder(self: *Self, new_order: Order) !void {
        if (self.orders) |*orders| {
            try orders.append(new_order);
        } else {
            self.orders = ArrayList(Order).init(self.allocator);
            try self.orders.?.append(new_order);
        }
    }

    /// 取消订单
    pub fn cancelOrder(self: *SnapLevel, order_id: u64) !Order {
        if (self.orders) |*orders| {
            var i: usize = 0;
            while (i < orders.items.len) : (i += 1) {
                if (orders.items[i].id == order_id) {
                    var order = orders.swapRemove(i);
                    order.status = .canceled;
                    return order;
                }
            }
        }
        return error.OrderNotFound;
    }
};

test "snap level" {
    const alloc = std.testing.allocator;
    const level = SnapLevel.init(alloc);
    defer level.deinit();
    try std.testing.expect(level.isEmpty());
    try std.testing.expectEqual(level.totalQty(), 0);
}

/// 只由Order组成的价格挡位
pub const OrderLevel = struct {
    price: f64,
    orders: ArrayList(Order),
    allocator: Allocator,
    const Self = @This();

    pub fn init(price: f64, allocator: Allocator) Self {
        return .{
            .price = price,
            .orders = ArrayList(Order).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.orders.deinit();
    }

    pub fn totalQty(self: *const Self) f64 {
        var sum: f64 = 0;
        for (self.orders.items) |order| {
            sum += order.remainQty();
        }
        return sum;
    }

    pub fn addOrder(self: *Self, new_order: Order) !void {
        try self.orders.append(new_order);
    }

    pub fn cancelOrder(self: *Self, order_id: u64) !Order {
        var i: usize = 0;
        while (i < self.orders.items.len) : (i += 1) {
            if (self.orders.items[i].id == order_id) {
                var order = self.orders.orderedRemove(i);
                order.status = .canceled;
                return order;
            }
        }
        return error.OrderNotFound;
    }

    /// 尝试撮合订单，注意必须保证订单的价格可以和当前挡位的价格匹配
    /// 返回值的第一个元素表示订单是否击穿该level，第二个元素表示匹配的订单列表
    pub fn matchOrder(self: *Self, order_: Order) !struct { bool, ArrayList(Order) } {
        var order = order_;
        var matched_orders = try ArrayList(Order).initCapacity(self.allocator, 2);
        var remain_orders = try ArrayList(Order).initCapacity(self.allocator, self.orders.items.len);

        for (self.orders.items) |*current_order| {
            const remain_qty = order.remainQty();
            const current_remain_qty = current_order.remainQty();
            if (remain_qty == 0) {
                try remain_orders.append(current_order.*);
                continue;
            }
            if (current_remain_qty >= remain_qty) {
                // 订单已经被吃下
                const exec_qty = remain_qty;
                current_order.exec_qty += exec_qty;
                current_order.current_exec_price = self.price;
                current_order.current_exec_qty = exec_qty; // 重置当前成交量
                current_order.current_is_maker = true;
                current_order.status = if (current_remain_qty == remain_qty) .filled else .partially_filled;
                order.exec_qty += exec_qty;
                // 被匹配的订单的当前成交量使用累计，当订单被置于订单簿中时，当前成交量会被重置
                order.current_exec_qty += exec_qty;
                order.current_exec_price = self.price;
                order.status = .filled;
                try matched_orders.append(current_order.clone());
                try remain_orders.append(current_order.*);
            } else {
                // 订单还需要接着被匹配
                const exec_qty = current_remain_qty;
                current_order.exec_qty += exec_qty;
                current_order.current_exec_qty = exec_qty; // 重置当前成交量
                current_order.current_exec_price = self.price;
                current_order.current_is_maker = true;
                current_order.status = .filled;
                order.exec_qty += exec_qty;
                order.current_exec_qty += exec_qty;
                order.current_exec_price = self.price;
                order.status = .partially_filled;
                try matched_orders.append(current_order.*);
            }
        }
        try matched_orders.append(order);

        self.orders.deinit();
        self.orders = remain_orders;
        return .{ order.remainQty() > 0, matched_orders };
    }
};

test "order level match order" {
    const alloc = std.testing.allocator;
    var level = OrderLevel.init(100, alloc);
    defer level.deinit();
    try level.addOrder(.{ .price = 100, .qty = 3, .id = 1 });
    try level.addOrder(.{ .price = 100, .qty = 2, .id = 2 });
    const matched_orders = (try level.matchOrder(.{ .price = 98, .side = .sell, .qty = 4, .id = 3 }))[1];
    defer matched_orders.deinit();
    try std.testing.expectEqual(matched_orders.items.len, 3);
    try std.testing.expectEqual(level.orders.items.len, 1);
    try std.testing.expectEqual(level.totalQty(), 1);
}

comptime {
    std.testing.refAllDecls(@This());
}
