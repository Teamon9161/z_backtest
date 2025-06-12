const std = @import("std");
const HashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const order_module = @import("../order.zig");
const Order = order_module.Order;
const OrderPrice = order_module.OrderPrice;
const OrderRead = order_module.OrderRead;
const Queue = @import("../models/queue.zig").Queue;
const OrderQueue = @import("../prelude.zig").OrderQueue;

/// Level接口 - 使用comptime多态性
pub fn LevelInterface(comptime T: type) type {
    return struct {
        /// 检查是否为空
        pub fn isEmpty(self: *const T) bool {
            return self.isEmpty();
        }

        /// 获取总数量
        pub fn totalSize(self: *const T) f64 {
            return self.totalSize();
        }

        /// 获取所有订单
        pub fn getOrders(self: *const T) []const Order {
            return self.getOrders();
        }

        /// 添加订单
        pub fn addOrder(self: *T, new_order: Order) !void {
            return self.addOrder(new_order);
        }

        /// 移除订单
        pub fn removeOrder(self: *T, order_id: u64) void {
            self.removeOrder(order_id);
        }

        /// 消费订单
        pub fn consumeOrder(self: *T, order_id: u64, size: f64) !void {
            return self.consumeOrder(order_id, size);
        }

        /// 取消订单
        pub fn cancelOrder(self: *T, order_id: u64) !Order {
            return self.cancelOrder(order_id);
        }

        /// 获取订单（只读）
        pub fn getOrder(self: *const T, order_id: u64) ?*const Order {
            return self.getOrder(order_id);
        }

        /// 获取订单（可变）
        pub fn getOrderMut(self: *T, order_id: u64) ?*Order {
            return self.getOrderMut(order_id);
        }

        /// 消费指定数量
        pub fn consume(self: *T, size: f64, price: OrderPrice) !ArrayList(OrderRead) {
            return self.consume(size, price);
        }

        /// 处理成交
        pub fn onTrade(
            self: *T,
            trade_size: f64,
            price: OrderPrice,
            queue_impl: anytype,
            order_queue: anytype,
            order_map: *HashMap(u64, struct { is_buy: bool, price: OrderPrice }),
            lot_size: f64,
        ) !f64 {
            return self.onTrade(
                trade_size,
                price,
                queue_impl,
                order_queue,
                order_map,
                lot_size,
            );
        }
    };
}

/// 快照级别 - 包含市场数据和策略订单
pub const SnapLevel = struct {
    /// 市场真实挂单总量
    size: f64,
    /// 策略订单列表
    orders: ArrayList(Order),
    /// 内存分配器
    allocator: Allocator,

    /// 创建新的空级别
    pub fn init(allocator: Allocator) SnapLevel {
        return .{
            .size = 0,
            .orders = ArrayList(Order).init(allocator),
            .allocator = allocator,
        };
    }

    /// 创建指定大小的级别
    pub fn initWithSize(allocator: Allocator, size: f64) SnapLevel {
        return .{
            .size = size,
            .orders = ArrayList(Order).init(allocator),
            .allocator = allocator,
        };
    }

    /// 清理资源
    pub fn deinit(self: *SnapLevel) void {
        self.orders.deinit();
    }

    /// 检查是否为空
    pub fn isEmpty(self: *const SnapLevel) bool {
        return (self.size == 0) and (self.orders.items.len == 0);
    }

    /// 获取总数量
    pub fn totalSize(self: *const SnapLevel) f64 {
        var sum: f64 = self.size;
        for (self.orders.items) |current_order| {
            sum += current_order.leavesSize();
        }
        return sum;
    }

    /// 获取所有订单
    pub fn getOrders(self: *const SnapLevel) []const Order {
        return self.orders.items;
    }

    /// 添加订单
    pub fn addOrder(self: *SnapLevel, new_order: Order) !void {
        try self.orders.append(new_order);
    }

    /// 移除订单
    pub fn removeOrder(self: *SnapLevel, order_id: u64) void {
        var i: usize = 0;
        while (i < self.orders.items.len) : (i += 1) {
            if (self.orders.items[i].order_id == order_id) {
                _ = self.orders.swapRemove(i);
                break;
            }
        }
    }

    /// 消费订单
    pub fn consumeOrder(self: *SnapLevel, order_id: u64, size: f64) !void {
        var i: usize = 0;
        while (i < self.orders.items.len) : (i += 1) {
            if (self.orders.items[i].order_id == order_id) {
                var current_order = &self.orders.items[i];
                if (current_order.leavesSize() < size) {
                    return error.InsufficientSize;
                }
                try current_order.fill(size, current_order.price);
                if (current_order.leavesSize() == 0) {
                    _ = self.orders.swapRemove(i);
                }
                return;
            }
        }
        return error.OrderNotFound;
    }

    /// 取消订单
    pub fn cancelOrder(self: *SnapLevel, order_id: u64) !Order {
        var i: usize = 0;
        while (i < self.orders.items.len) : (i += 1) {
            if (self.orders.items[i].order_id == order_id) {
                var cancelled_order = self.orders.swapRemove(i);
                try cancelled_order.cancel();
                return cancelled_order;
            }
        }
        return error.OrderNotFound;
    }

    /// 获取订单（只读）
    pub fn getOrder(self: *const SnapLevel, order_id: u64) ?*const Order {
        for (self.orders.items) |*current_order| {
            if (current_order.order_id == order_id) {
                return current_order;
            }
        }
        return null;
    }

    /// 获取订单（可变）
    pub fn getOrderMut(self: *SnapLevel, order_id: u64) ?*Order {
        for (self.orders.items) |*current_order| {
            if (current_order.order_id == order_id) {
                return current_order;
            }
        }
        return null;
    }

    /// 消费指定数量
    pub fn consume(self: *SnapLevel, size: f64, price: OrderPrice) !ArrayList(OrderRead) {
        // 优先消耗市场真实挂单避免自成交
        const real_fill_size = @min(self.size, size);
        self.size -= real_fill_size;

        // 可能导致自成交的剩余数量
        var remain_size = size - real_fill_size;
        var filled_orders = ArrayList(OrderRead).init(self.allocator);

        var i: usize = 0;
        while (i < self.orders.items.len) {
            var current_order = &self.orders.items[i];
            const fill_qty = @min(current_order.leavesSize(), remain_size);

            if (fill_qty > 0) {
                try current_order.fill(fill_qty, price);
                remain_size -= fill_qty;
                try filled_orders.append(current_order.toOrderRead());

                if (current_order.leavesSize() <= 0) {
                    _ = self.orders.swapRemove(i);
                    continue; // swapRemove后不增加i
                }
            }
            i += 1;
        }

        if (remain_size > 0) {
            return error.InsufficientSize;
        }

        return filled_orders;
    }

    /// 处理成交
    pub fn onTrade(
        self: *SnapLevel,
        trade_size: f64,
        price: OrderPrice,
        queue_impl: anytype,
        order_queue: anytype,
        order_map: *HashMap(u64, struct { is_buy: bool, price: OrderPrice }),
        lot_size: f64,
    ) !f64 {
        var remaining_size = trade_size;
        var i: usize = 0;

        while (i < self.orders.items.len) {
            var current_order = &self.orders.items[i];
            queue_impl.trade(current_order, remaining_size);
            const filled_size = queue_impl.filledSize(current_order, lot_size);

            if (filled_size > 0) {
                const exec_size = @min(@min(filled_size, remaining_size), current_order.leavesSize());
                remaining_size -= exec_size;
                try current_order.fill(exec_size, current_order.price);
                try order_queue.append(current_order.toOrderRead());
            }

            if (current_order.leavesSize() > 0) {
                i += 1;
            } else {
                _ = order_map.remove(current_order.order_id);
                _ = self.orders.swapRemove(i);
                // swapRemove后不增加i
            }
        }

        if (remaining_size > 0) {
            const exec_size = @min(remaining_size, self.totalSize());
            remaining_size -= exec_size;

            var filled_orders = try self.consume(exec_size, price);
            defer filled_orders.deinit();

            if (filled_orders.items.len > 0) {
                try order_queue.appendSlice(filled_orders.items);
            }
        }

        return remaining_size;
    }

    /// 获取接口
    pub const Interface = LevelInterface(SnapLevel);
};
