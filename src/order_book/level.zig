const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Order = @import("order.zig").Order;

/// 快照级别 - 包含市场数据和策略订单
pub const SnapLevel = struct {
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
        if (self.orders) |orders| {
            try orders.append(new_order);
        } else {
            self.orders = try ArrayList(Order).init(self.allocator);
            try self.orders.?.append(new_order);
        }
    }

    // /// 直接移除订单, 没有任何回报
    // pub fn removeOrder(self: *SnapLevel, order_id: u64) void {
    //     if (self.orders) |orders| {
    //         var i: usize = 0;
    //         while (i < orders.items.len) : (i += 1) {
    //             if (orders.items[i].order_id == order_id) {
    //                 _ = orders.swapRemove(i);
    //                 break;
    //             }
    //         }
    //     }
    // }
};

test "snap level" {
    const alloc = std.testing.allocator;
    const level = SnapLevel.init(alloc);
    defer level.deinit();
    try std.testing.expect(level.isEmpty());
    try std.testing.expectEqual(level.totalQty(), 0);
}

comptime {
    std.testing.refAllDecls(@This());
}
