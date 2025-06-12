name: []const u8 = "",
lot_size: f64 = 1,
tick: f64 = 0.0001,
delay: struct {
    send: i64 = 0,
    receive: i64 = 0,
} = .{
    .send = 0,
    .receive = 0,
},
