//! The gaps the adoptions found after the first batch, rounds 2 to 4: ordered positions, contracts that end
//! control flow, owners released through Io, wide clock representations, lock reads, saturating clocks, id
//! relations, uncancelable ordered waits, conversions that cannot fail, budget reads and control accounting,
//! container capacity and atomic cells of distinct domains.
const std = @import("std");
const shake = @import("shakedown");
const a = @import("../root.zig");
const Io = std.Io;
const t = std.testing;

test "A8 Index equality and order follow the positions and carry the domain" {
    const I = a.handle.Index(struct {}, u16);
    const values = [_]u32{ 0, 0, 0, 0, 0 };
    const low = try I.from(1, values.len);
    const mid = try I.from(3, values.len);
    const high = try I.from(4, values.len);
    try t.expect(mid.eql(try I.from(3, values.len)));
    try t.expect(!mid.eql(high));
    try t.expectEqual(std.math.Order.lt, low.compare(mid));
    try t.expectEqual(std.math.Order.gt, high.compare(mid));
    try t.expectEqual(std.math.Order.eq, mid.compare(mid));
    var shuffled = [_]I{ high, low, mid };
    std.mem.sort(I, &shuffled, {}, struct {
        fn before(_: void, x: I, y: I) bool {
            return x.compare(y) == .lt;
        }
    }.before);
    try t.expectEqualSlices(u16, &.{ 1, 3, 4 }, &.{ shuffled[0].raw(), shuffled[1].raw(), shuffled[2].raw() });
}

test "A3 never ends control flow where a value is wanted and costs nothing on the paths that run" {
    comptime std.debug.assert(@typeInfo(@TypeOf(a.assert.never)).@"fn".return_type.? == noreturn);
    const Slot = enum { file, directory, other };
    const code = struct {
        fn of(slot: Slot) u8 {
            return switch (slot) {
                .file => 1,
                .directory => 2,
                .other => a.assert.never("only files and directories arrive here"),
            };
        }
    };
    try t.expectEqual(@as(u8, 1), code.of(.file));
    try t.expectEqual(@as(u8, 2), code.of(.directory));
    const maybe: ?u8 = 7;
    try t.expectEqual(@as(u8, 7), maybe orelse a.assert.never("a value was promised"));
}

const Log = struct { closed: usize = 0, io_seen: ?*anyopaque = null };
const Handle = struct {
    descriptor: u32,
    log: *Log,
    fn close(self: *Handle, io: Io) void {
        self.log.closed += 1;
        self.log.io_seen = io.userdata;
    }
    fn plain(self: *Handle) void {
        self.log.closed += 1;
    }
    pub fn moveInto(self: *Handle, destination: *Handle) void {
        destination.* = self.*;
        self.descriptor = 0;
    }
};
const Closing = a.own.OwnedIo(Handle, Handle.close);

test "A7 OwnedIo releases through the Io of the releaser, once, and a moved or taken owner owes nothing" {
    var clock: shake.Clock = .init(t.io, .{});
    const io = clock.io();
    var log: Log = .{};
    {
        var owner = Closing.init(.{ .descriptor = 7, .log = &log });
        try t.expectEqual(@as(u32, 7), owner.borrow().descriptor);
        owner.borrowMut().descriptor = 8;
        owner.deinit(io);
    }
    try t.expectEqual(@as(usize, 1), log.closed);
    try t.expectEqual(io.userdata, log.io_seen);

    log = .{};
    var source = Closing.init(.{ .descriptor = 9, .log = &log });
    var destination: Closing = undefined;
    source.moveInto(&destination);
    try t.expectEqual(@as(usize, 0), log.closed);
    try t.expectEqual(@as(u32, 9), destination.borrow().descriptor);
    destination.deinit(io);
    try t.expectEqual(@as(usize, 1), log.closed);

    log = .{};
    var taken = Closing.init(.{ .descriptor = 3, .log = &log });
    var raw: Handle = undefined;
    taken.take(&raw);
    try t.expectEqual(@as(usize, 0), log.closed);
    try t.expectEqual(@as(u32, 3), raw.descriptor);

    log = .{};
    var by_move: Handle = .{ .descriptor = 5, .log = &log };
    var owner = Closing.initFrom(&by_move);
    try t.expectEqual(@as(u32, 0), by_move.descriptor);
    owner.deinit(io);
    try t.expectEqual(@as(usize, 1), log.closed);
}

test "A7 OwnedIo and Owned are the same size and OwnedIo takes no Io until it is released" {
    const Plain = a.own.Owned(Handle, Handle.plain);
    try t.expectEqual(@sizeOf(Plain), @sizeOf(Closing));
    try t.expectEqual(@alignOf(Plain), @alignOf(Closing));
    comptime std.debug.assert(@TypeOf(Closing.deinit) == fn (*Closing, Io) void);
    comptime std.debug.assert(@TypeOf(Plain.deinit) == fn (*Plain) void);
    var log: Log = .{};
    var plain = Plain.init(.{ .descriptor = 1, .log = &log });
    plain.deinit();
    try t.expectEqual(@as(usize, 1), log.closed);
}

test "A3 durations and instants hold std's i96 nanoseconds exactly" {
    const U = a.units;
    const D = U.Duration(.nanosecond, i96);
    const T = U.Instant(.awake, .nanosecond, i96);
    comptime std.debug.assert(D.ToIoDurationError == error{} and D.FromIoDurationError == error{});
    comptime std.debug.assert(T.ToTimestampError == error{} and T.FromTimestampError == error{});
    comptime std.debug.assert(@TypeOf(D.fromIoDuration(.zero, .exact)) == D);
    comptime std.debug.assert(@TypeOf(D.fromRaw(0).toIoDuration()) == Io.Duration);
    comptime std.debug.assert(@sizeOf(D) == @sizeOf(i96) and @alignOf(D) == @alignOf(i96));
    for ([_]i96{ std.math.minInt(i96), -1, 0, 1, std.math.maxInt(i96) }) |nanoseconds| {
        const span = D.fromIoDuration(.fromNanoseconds(nanoseconds), .exact);
        try t.expectEqual(nanoseconds, span.raw());
        try t.expectEqual(Io.Duration.fromNanoseconds(nanoseconds), span.toIoDuration());
        const stamp: Io.Timestamp = .fromNanoseconds(nanoseconds);
        const instant = T.fromTimestamp(stamp, .exact);
        try t.expectEqual(nanoseconds, instant.raw());
        try t.expectEqual(stamp, instant.toTimestamp());
        try t.expectEqual(Io.Clock.awake, instant.toIoTimestamp().clock);
    }
    // Arithmetic is still checked at the width's own bounds.
    try t.expectError(error.Overflow, D.fromRaw(std.math.maxInt(i96)).add(D.fromRaw(1)));
    try t.expectError(error.Underflow, D.fromRaw(std.math.minInt(i96)).sub(D.fromRaw(1)));
    try t.expectError(error.Overflow, T.fromRaw(std.math.maxInt(i96)).add(D.fromRaw(1)));
    try t.expectEqual(@as(i96, 2), (try T.fromRaw(1).durationTo(T.fromRaw(3))).raw());
    try t.expectEqual(std.math.Order.lt, T.fromRaw(-5).compare(T.fromRaw(5)));
    // A coarser unit converts through the same checked scale.
    const seconds = try D.fromRaw(3 * std.time.ns_per_s).convert(.second, i96, .exact);
    try t.expectEqual(@as(i96, 3), seconds.raw());
}

test "A3 whole-byte widths other than a power of two round-trip their bytes in both endians" {
    const U = a.units;
    inline for (.{ i24, u40, i96, u96, i128 }) |Repr| {
        const D = U.Duration(.millisecond, Repr);
        const high = D.fromRaw(std.math.maxInt(Repr));
        const low = D.fromRaw(std.math.minInt(Repr));
        comptime std.debug.assert(@typeInfo(@TypeOf(high.encode(.little))).array.len == @bitSizeOf(Repr) / 8);
        inline for (.{ std.builtin.Endian.little, std.builtin.Endian.big }) |endian| {
            try t.expectEqual(high, D.decode(high.encode(endian), endian));
            try t.expectEqual(low, D.decode(low.encode(endian), endian));
        }
        try t.expect(high.compare(low) == .gt);
    }
}
