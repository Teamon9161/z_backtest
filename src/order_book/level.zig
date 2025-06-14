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
                sum += current_order.leavesQty();
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
                if (orders.items[i].order_id == order_id) {
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
    const Self = @This();

    pub fn init(price: f64, allocator: Allocator) Self {
        return .{
            .price = price,
            .orders = ArrayList(Order).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.orders.deinit();
    }

    pub fn totalQty(self: *const Self) f64 {
        var sum: f64 = 0;
        for (self.orders.items) |order| {
            sum += order.leavesQty();
        }
        return sum;
    }

    pub fn addOrder(self: *Self, new_order: Order) !void {
        try self.orders.append(new_order);
    }

    pub fn cancelOrder(self: *Self, order_id: u64) !Order {
        var i: usize = 0;
        while (i < self.orders.items.len) : (i += 1) {
            if (self.orders.items[i].order_id == order_id) {
                var order = self.orders.swapRemove(i);
                order.status = .canceled;
                return order;
            }
        }
        return error.OrderNotFound;
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
