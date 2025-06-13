const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const ALLOC = @import("root.zig").ALLOC;
const Order = @import("order_book/order.zig").Order;

const EventTag = enum(u8) {
    new_order,
};

pub const EventType = union(EventTag) {
    /// 创建新订单事件
    new_order: Order,
};

pub const Event = struct {
    event: EventType,
    finish_time: i64,
    asset: u32 = 0, // 目标标的
};

pub const EventPool = struct {
    events: ArrayList(Event),
    // 最快完成的一个事件的完成时间
    fastest_finish_time: ?i64 = null,
    const Self = @This();

    pub fn init(allocator: ?std.mem.Allocator) Self {
        const alloc = if (allocator) |alloc| alloc else ALLOC;
        return EventPool{
            .events = ArrayList(Event).init(alloc),
        };
    }

    pub fn is_empty(self: *const Self) bool {
        return self.len() == 0;
    }

    pub fn len(self: *const Self) usize {
        return self.events.items.len;
    }

    pub fn deinit(self: Self) void {
        self.events.deinit();
    }

    pub fn addEvent(self: *Self, item: Event) !void {
        if (self.fastest_finish_time == null or item.finish_time < self.fastest_finish_time.?) {
            self.fastest_finish_time = item.finish_time;
        }
        try self.events.append(item);
    }

    pub fn findFastestFinishTime(self: *Self) void {
        var fastest_finish_time: i64 = std.math.maxInt(i64);
        for (self.events.items) |event| {
            if (event.finish_time < fastest_finish_time) {
                fastest_finish_time = event.finish_time;
            }
        }
        self.fastest_finish_time = fastest_finish_time;
    }

    pub fn gotoTime(self: *Self, until_time: ?i64) ?ArrayList(Event) {
        if (self.is_empty()) {
            return null;
        }
        const time = if (until_time) |time| time else self.fastest_finish_time.?;
        if (self.fastest_finish_time.? > time) {
            return null;
        }

        var processed_events: ArrayList(Event) = ArrayList(Event).init(ALLOC);
        var unprocessed_events: ArrayList(Event) = ArrayList(Event).init(ALLOC);
        for (self.events.items) |event| {
            if (event.finish_time <= time) {
                processed_events.append(event) catch unreachable;
            } else {
                unprocessed_events.append(event) catch unreachable;
            }
        }
        self.events.deinit();
        self.events = unprocessed_events;
        if (processed_events.items.len > 0) {
            self.findFastestFinishTime();
        }
        return processed_events;
    }
};

test "event" {
    var event_pool = EventPool.init(null);
    defer event_pool.deinit();
    try event_pool.addEvent(.{ .finish_time = 2, .event = .{ .new_order = .{ .order_id = 1 } } });
    try event_pool.addEvent(.{ .finish_time = 1, .event = .{ .new_order = .{ .order_id = 2 } } });
    try event_pool.addEvent(.{ .finish_time = 3, .event = .{ .new_order = .{ .order_id = 3 } } });
    try event_pool.addEvent(.{ .finish_time = 1, .event = .{ .new_order = .{ .order_id = 4 } } });
    const events = event_pool.gotoTime(null);
    defer events.?.deinit();
    std.debug.assert(events.?.items.len == 2);
    std.debug.assert(event_pool.len() == 2);
    std.debug.assert(event_pool.fastest_finish_time.? == 2);
}

comptime {
    std.testing.refAllDecls(@This());
}
