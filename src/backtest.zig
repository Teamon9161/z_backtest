const std = @import("std");
const EventPool = @import("event.zig").EventPool;
const Event = @import("event.zig").Event;
const Order = @import("order/Order.zig");
const Asset = @import("Asset.zig");
const ArrayList = std.ArrayList;

const Local = struct {
    w: *World,

    pub fn newOrder(self: *Local, asset: u32, mut_order: Order) !void {
        var order = mut_order;
        const send_delay = self.w.assets[asset].delay.send;
        order.create_timestamp = self.w.time;
        try self.w.ex_ep.addEvent(.{
            .finish_time = self.w.time + send_delay,
            .event = .{ .new_order = order },
            .asset = asset,
        });
    }

    pub fn process_events(self: *Local, events: ?[]const Event) !void {
        _ = .{ self, events };
        return;
    }
};

const Exchange = struct {
    w: *World,
    pub fn process_events(self: *Exchange, events: ?[]const Event) !void {
        _ = .{ self, events };
        return;
    }
};

pub const Options = struct {
    assets: []const Asset,
    time: i64 = 0,
    allocator: ?std.mem.Allocator = null,
};

pub const World = struct {
    time: i64,
    assets: []const Asset,
    ex_ep: EventPool,
    local_ep: EventPool,
    _local: ?Local = null,
    _exchange: ?Exchange = null,

    pub fn init(opt: Options) World {
        const ex_ep = EventPool.init(opt.allocator);
        const local_ep = EventPool.init(opt.allocator);
        return World{
            .time = opt.time,
            .assets = opt.assets,
            .ex_ep = ex_ep,
            .local_ep = local_ep,
        };
    }

    pub fn local(self: *World) *Local {
        if (self._local == null) {
            self._local = Local{ .w = self };
        }
        return &self._local.?;
    }

    pub fn exchange(self: *World) *Exchange {
        if (self._exchange == null) {
            self._exchange = Exchange{ .w = self };
        }
        return &self._exchange.?;
    }

    pub fn gotoTime(self: *World, time: ?i64) void {
        const go_time = time orelse blk: {
            const ex_time = self.ex_ep.fastest_finish_time;
            const local_time = self.local_ep.fastest_finish_time;

            break :blk if (ex_time) |ex|
                if (local_time) |loc| @min(ex, loc) else ex
            else
                local_time;
        };
        if (go_time == null) return;
        const ex_events = self.ex_ep.gotoTime(go_time);
        const local_events = self.local_ep.gotoTime(go_time);
        defer if (ex_events) |*events| events.deinit();
        defer if (local_events) |*events| events.deinit();
        try self.local().process_events(if (local_events) |events| events.items else null);
        try self.exchange().process_events(if (ex_events) |events| events.items else null);
    }

    pub fn deinit(self: *World) void {
        self.ex_ep.deinit();
        self.local_ep.deinit();
    }
};

test "world base" {
    const asstes = [_]Asset{
        .{ .name = "BTC", .delay = .{ .send = 1, .receive = 2 } },
        .{ .name = "ETH", .delay = .{ .send = 1, .receive = 1 } },
    };
    var world = World.init(.{ .assets = &asstes });
    defer world.deinit();
    try world.local().newOrder(0, .{ .order_id = 1, .price = 10000, .qty = 1 });
    try world.local().newOrder(1, .{ .order_id = 2, .price = 10000, .qty = 1 });
    try world.local().newOrder(0, .{ .order_id = 3, .price = 10000, .qty = 1 });
    try world.local().newOrder(1, .{ .order_id = 4, .price = 10000, .qty = 1 });
    std.debug.assert(world.ex_ep.len() == 4);
    world.gotoTime(null);
    std.debug.assert(world.ex_ep.len() == 0);
    std.debug.assert(world.local_ep.len() == 0);
}

comptime {
    std.testing.refAllDecls(@This());
}
