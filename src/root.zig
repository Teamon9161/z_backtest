//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const builtin = @import("builtin");
pub const World = @import("world.zig").World;

// OrderBook 模块导出
pub const OrderBook = @import("order_book/order_book.zig").OrderBook;
pub const Order = @import("order_book/order.zig").Order;
pub const SnapLevel = @import("order_book/level.zig").SnapLevel;

// 类型导出
pub const Side = @import("order_book/order.zig").Side;
pub const Status = @import("order_book/order.zig").Status;
pub const OrderType = @import("order_book/order.zig").OrderType;
pub const TimeInForce = @import("order_book/order.zig").TimeInForce;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const ALLOC = if (@import("builtin").is_test)
    std.testing.allocator
else switch (builtin.mode) {
    .Debug, .ReleaseSafe => debug_allocator.allocator(),
    .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
};

comptime {
    std.testing.refAllDecls(@This());
}
