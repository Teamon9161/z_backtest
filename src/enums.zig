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
