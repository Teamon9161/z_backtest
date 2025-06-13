pub const Side = enum(i8) {
    buy = 1,
    sell = -1,
    none = 0,
};

pub const Status = enum(u8) {
    none = 0,
    new = 1,
    expired = 2,
    filled = 3,
    canceled = 4,
    partially_filled = 5,
    rejected = 6,
    unsupported = 255,
};

pub const TimeInForce = enum(u8) {
    /// Good 'Til Canceled
    gtc = 0,
    /// Post-only
    gtx = 1,
    /// Fill or Kill
    fok = 2,
    /// Immediate or Cancel
    ioc = 3,
};

pub const OrderType = enum(u8) {
    limit = 0,
    market = 1,
};

pub const Order = struct {
    order_id: u64 = 0,
    price: f64 = 0,
    qty: f64 = 0,
    side: Side = .buy,
    exec_qty: f64 = 0, // 累计被成交的数量
    current_exec_qty: f64 = 0, // 最近一次成交的成交量
    exec_amt: f64 = 0,
    type: OrderType = .limit,
    create_timestamp: i64 = 0,
    // cancel_timestamp: i64 = 0,
    time_in_force: TimeInForce = .gtc,
    req: Status = .new,
    /// 剩余未成交的数量
    pub fn leavesQty(self: *const Order) f64 {
        return self.qty - self.exec_qty;
    }
};
