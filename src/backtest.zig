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
};

const Exchange = struct {
    w: *World,
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
    local: Local,
    exchange: Exchange,

    pub fn init(opt: Options) World {
        const ex_ep = EventPool.init(opt.allocator);
        const local_ep = EventPool.init(opt.allocator);
        var self = World{
            .time = opt.time,
            .assets = opt.assets,
            .ex_ep = ex_ep,
            .local_ep = local_ep,
            .local = undefined,
            .exchange = undefined,
        };
        self.local = Local{ .w = &self };
        self.exchange = Exchange{ .w = &self };
        return self;
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
    // defer world.deinit();
    try world.local.newOrder(0, .{ .order_id = 1, .price = 10000, .qty = 1 });
    // world.local.newOrder(1, .{ .order_id = 2, .price = 10000, .qty = 1 });
    // world.local.newOrder(0, .{ .order_id = 3, .price = 10000, .qty = 1 });
    // world.local.newOrder(1, .{ .order_id = 4, .price = 10000, .qty = 1 });
    // std.debug.assert(world.ex_ep.len() == 4);
}

comptime {
    std.testing.refAllDecls(@This());
}
