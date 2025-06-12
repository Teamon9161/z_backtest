const enums = @import("../enums.zig");
const Side = enums.Side;
const Status = enums.Status;
const TimeInForce = enums.TimeInForce;
const OrderType = enums.OrderType;

order_id: u64 = 0,
price: f64 = 0,
qty: f64 = 0,
side: Side = .buy,
exec_qty: f64 = 0,
current_exec_qty: f64 = 0,
exec_amt: f64 = 0,
type: OrderType = .limit,
create_timestamp: i64 = 0,
// cancel_timestamp: i64 = 0,
time_in_force: TimeInForce = .gtc,
req: Status = .new,
