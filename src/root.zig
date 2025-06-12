//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const builtin = @import("builtin");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub const ALLOC = if (@import("builtin").is_test)
    std.testing.allocator
else switch (builtin.mode) {
    .Debug, .ReleaseSafe => debug_allocator.allocator(),
    .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
};

// pub const test_allocator = if (@import("builtin").is_test) std.testing.allocator else null;

comptime {
    std.testing.refAllDecls(@This());
}
