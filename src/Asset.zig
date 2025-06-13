/// 标的名称
name: []const u8 = "",
/// 最小交易单位
lot_size: f64 = 1,
/// 最小价格变动
tick: f64 = 0.0001,
/// 延迟时间 - 发送和接收
delay: struct {
    send: i64 = 0,
    receive: i64 = 0,
} = .{
    .send = 0,
    .receive = 0,
},
