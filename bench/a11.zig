//! The reader-writer spin guard, the timing span and the stack scrub against their hand-written
//! forms, each operation through an explicit non-inline call that keeps it inside the measured
//! boundary.
const std = @import("std");
const ab = @import("ab");
const a = @import("aegis");
const c = @import("a11");
const Io = std.Io;

const iterations = 5_000_000;
const names = [_][]const u8{ "spin_rw_read", "spin_rw_write", "timing_span", "scrub_stack" };

noinline fn measure(comptime wrapped: bool, comptime name: []const u8, io: Io, count: usize) error{}!f64 {
    var accumulator: u64 = 0;
    var owner: if (wrapped) a.SpinRwGuarded(u64) else c.DirectSpinRw = if (wrapped) .init(1) else .{ .data = 1 };
    const material: [32]u8 = @splat(7);
    const start = Io.Clock.awake.now(io);
    for (0..count) |i| {
        if (comptime std.mem.eql(u8, name, "spin_rw_read")) {
            accumulator +%= @call(.never_inline, c.spinRead, .{ wrapped, &owner });
        } else if (comptime std.mem.eql(u8, name, "spin_rw_write")) {
            @call(.never_inline, c.spinWrite, .{ wrapped, &owner, i });
        } else if (comptime std.mem.eql(u8, name, "timing_span")) {
            accumulator +%= @call(.never_inline, c.timingSpan, .{ wrapped, &material });
        } else @call(.never_inline, c.scrub, .{wrapped});
    }
    const elapsed = start.durationTo(Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(accumulator);
    std.mem.doNotOptimizeAway(&owner);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}

pub fn main(init: std.process.Init) !void {
    try ab.run(&names, measure, init, iterations);
}
