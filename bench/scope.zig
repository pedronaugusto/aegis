//! Scope tables, scopes and references against their hand-written forms, and checked reads against plain pointers.
//! Reads are timed inline, as they are used; the other operations through explicit non-inline calls, which
//! keep each one inside the measured boundary.
const std = @import("std");
const ab = @import("ab");
const c = @import("scope");
const Io = std.Io;

const iterations = 20_000_000;
const names = [_][]const u8{ "get", "get_unchecked", "make", "reborrow", "cycle" };

noinline fn measure(comptime wrapped: bool, comptime name: []const u8, io: Io, count: usize) error{}!f64 {
    var accumulator: u64 = 0;
    var slots: [4]if (wrapped) c.Table.Slot else c.DirectSlot = undefined;
    var table: c.Tab(wrapped) = undefined;
    if (wrapped) table = .init(&slots) else if (@sizeOf(c.DirectTable) != 0) {
        for (&slots, 0..) |*slot, i| slot.* = .{ .next = if (i + 1 < slots.len) i + 1 else std.math.maxInt(usize) };
        table = .{ .slots = &slots, .free_head = 0, .used_up = 0, .open_count = 0 };
    }
    var values: [64]u64 = undefined;
    for (&values, 0..) |*value, i| value.* = i;
    var scope: c.Sco(wrapped) = undefined;
    _ = c.open(wrapped, &table, &scope);
    var refs: [64]c.Reference(wrapped) = undefined;
    for (&refs, &values) |*reference, *value| c.make(wrapped, &scope, value, reference);
    var plain: [64]*u64 = undefined;
    for (&plain, &values) |*pointer, *value| pointer.* = value;
    var moved: c.Reference(wrapped) = undefined;
    const start = Io.Clock.awake.now(io);
    for (0..count) |i| {
        if (comptime std.mem.eql(u8, name, "get")) {
            accumulator +%= c.get(wrapped, &refs[i & 63]).*;
        } else if (comptime std.mem.eql(u8, name, "get_unchecked")) {
            accumulator +%= if (wrapped) c.get(true, &refs[i & 63]).* else plain[i & 63].*;
        } else if (comptime std.mem.eql(u8, name, "make")) {
            @call(.never_inline, c.make, .{ wrapped, &scope, &values[i & 63], &moved });
            std.mem.doNotOptimizeAway(&moved);
        } else if (comptime std.mem.eql(u8, name, "reborrow")) {
            @call(.never_inline, c.reborrow, .{ wrapped, &scope, &refs[i & 63], &moved });
            std.mem.doNotOptimizeAway(&moved);
        } else accumulator +%= @call(.never_inline, c.cycle, .{ wrapped, &table, &values[i & 63] });
    }
    const elapsed = start.durationTo(Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(accumulator);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}

pub fn main(init: std.process.Init) !void {
    try ab.run(&names, measure, init, iterations);
}
