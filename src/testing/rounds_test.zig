//! The gaps the adoptions found after the first batch, rounds 2 to 4: ordered positions, contracts that end
//! control flow, owners released through Io, wide clock representations, lock reads, saturating clocks, id
//! relations, uncancelable ordered waits, conversions that cannot fail, budget reads and control accounting,
//! container capacity and atomic cells of distinct domains.
const std = @import("std");
const builtin = @import("builtin");
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

test "A6 isHeld reads a lock without taking it, for the spin guard, the blocking guard and an ordered one" {
    var spin = a.Guarded(u32).init(1);
    try t.expect(!spin.isHeld());
    var held = spin.acquire();
    try t.expect(spin.isHeld());
    try t.expect(spin.tryAcquire() == null);
    held.deinit();
    try t.expect(!spin.isHeld());
    // Reading did not take the lock: it is still free to take.
    held = spin.tryAcquire().?;
    held.deinit();

    var blocking = a.BlockingGuarded(u32).init(2);
    try t.expect(!blocking.isHeld());
    var guard = try blocking.acquire(t.io);
    try t.expect(blocking.isHeld());
    guard.deinit(t.io);
    try t.expect(!blocking.isHeld());

    const O = a.Order(&.{.{ .name = "root" }});
    var ordered = O.Ordered(a.Guarded(u32), 0).init(.init(3));
    try t.expect(!ordered.isHeld());
    try t.expect(!ordered.base.isHeld());
}

fn holdWhile(owner: *a.Guarded(u32), held: *std.atomic.Value(bool), release: *std.atomic.Value(bool)) void {
    var guard = owner.acquire();
    held.store(true, .release);
    while (!release.load(.acquire)) std.atomic.spinLoopHint();
    guard.deinit();
}

test "A6 isHeld sees another task's hold and its release" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var owner = a.Guarded(u32).init(0);
    var held: std.atomic.Value(bool) = .init(false);
    var release: std.atomic.Value(bool) = .init(false);
    var group: Io.Group = .init;
    defer group.cancel(t.io);
    try group.concurrent(t.io, holdWhile, .{ &owner, &held, &release });
    while (!held.load(.acquire)) std.atomic.spinLoopHint();
    try t.expect(owner.isHeld());
    release.store(true, .release);
    try group.await(t.io);
    try t.expect(!owner.isHeld());
}

fn saturatingProperty(_: void, case: *shake.Case) anyerror!void {
    const U = a.units;
    inline for (.{ i8, u8, i16, u16 }) |Repr| {
        const D = U.Duration(.millisecond, Repr);
        const T = U.Instant(.awake, .millisecond, Repr);
        const x = shake.gen.int(case.source, Repr);
        const y = shake.gen.int(case.source, Repr);
        const low: i64 = std.math.minInt(Repr);
        const high: i64 = std.math.maxInt(Repr);
        const sum = std.math.clamp(@as(i64, x) + @as(i64, y), low, high);
        const difference = std.math.clamp(@as(i64, x) - @as(i64, y), low, high);
        const product = std.math.clamp(@as(i64, x) * @as(i64, y), low, high);
        try t.expectEqual(sum, @as(i64, D.fromRaw(x).saturatingAdd(D.fromRaw(y)).raw()));
        try t.expectEqual(difference, @as(i64, D.fromRaw(x).saturatingSub(D.fromRaw(y)).raw()));
        try t.expectEqual(product, @as(i64, D.fromRaw(x).saturatingMul(y).raw()));
        try t.expectEqual(sum, @as(i64, T.fromRaw(x).saturatingAdd(D.fromRaw(y)).raw()));
        try t.expectEqual(difference, @as(i64, T.fromRaw(x).saturatingSub(D.fromRaw(y)).raw()));
        // The span from x to y is y - x, clamped.
        try t.expectEqual(std.math.clamp(@as(i64, y) - @as(i64, x), low, high), @as(i64, T.fromRaw(x).saturatingDurationTo(T.fromRaw(y)).raw()));
        // Where the checked form succeeds, the saturating form agrees with it.
        if (T.fromRaw(x).durationTo(T.fromRaw(y))) |span| {
            try t.expectEqual(span, T.fromRaw(x).saturatingDurationTo(T.fromRaw(y)));
        } else |_| {}
    }
}

test "A3 saturating durations and instants clamp at the representation's bounds and agree with the checked forms" {
    try shake.check(t.allocator, {}, saturatingProperty, .{ .cases = 1024, .seed = 0xa3b });
    const D = a.units.Duration(.nanosecond, i96);
    const T = a.units.Instant(.awake, .nanosecond, i96);
    try t.expectEqual(@as(i96, std.math.maxInt(i96)), D.fromRaw(std.math.maxInt(i96)).saturatingAdd(D.fromRaw(1)).raw());
    try t.expectEqual(@as(i96, std.math.minInt(i96)), T.fromRaw(std.math.minInt(i96)).saturatingSub(D.fromRaw(1)).raw());
    try t.expectEqual(@as(i96, std.math.maxInt(i96)), T.fromRaw(std.math.minInt(i96)).saturatingDurationTo(T.fromRaw(std.math.maxInt(i96))).raw());
}

test "A3 a clock that steps back gives a zero span saturating and an error checked" {
    const Awake = a.units.Instant(.awake, .nanosecond, u64);
    const Span = a.units.Duration(.nanosecond, u64);
    const earlier = Awake.fromRaw(1_000);
    const later = Awake.fromRaw(1_750);
    try t.expectEqual(Span.fromRaw(750), earlier.saturatingDurationTo(later));
    try t.expectEqual(Span.fromRaw(750), try earlier.durationTo(later));
    // Read in the wrong order the span is zero, where the checked form reports it.
    try t.expectEqual(Span.fromRaw(0), later.saturatingDurationTo(earlier));
    try t.expectError(error.Underflow, later.durationTo(earlier));
    try t.expectEqual(Span.fromRaw(0), later.saturatingDurationTo(later));
    try t.expectEqual(Awake.fromRaw(0), earlier.saturatingSub(Span.fromRaw(5_000)));
    try t.expectEqual(Awake.fromRaw(std.math.maxInt(u64)), later.saturatingAdd(Span.fromRaw(std.math.maxInt(u64))));
}

const Seq = a.id.Id(struct {}, u64);
const Record = struct {};
const Records = a.units.Count(Record, u64);
const Position = struct {
    pub const Step = Records;
};
const Numbered = a.id.Id(Position, u64);
const Port = a.id.NonZero(struct {}, u16);

test "A3 ids step, advance, retreat and measure distance without wrapping" {
    const first = Seq.fromRaw(0);
    try t.expectEqual(@as(u64, 1), (try first.successor()).raw());
    try t.expectError(error.IdUnderflow, first.predecessor());
    try t.expectEqual(@as(u64, 4), (try Seq.fromRaw(5).predecessor()).raw());
    const last = Seq.fromRaw(std.math.maxInt(u64));
    try t.expectError(error.IdExhausted, last.successor());
    try t.expectEqual(@as(u64, std.math.maxInt(u64) - 1), (try last.predecessor()).raw());
    comptime std.debug.assert(Seq.Step == a.units.Count(Seq.Domain, u64));
    try t.expectEqual(@as(u64, 15), (try Seq.fromRaw(10).advance(.fromRaw(5))).raw());
    try t.expectError(error.IdExhausted, last.advance(.fromRaw(1)));
    try t.expectEqual(@as(u64, std.math.maxInt(u64)), (try Seq.fromRaw(std.math.maxInt(u64) - 3).advance(.fromRaw(3))).raw());
    try t.expectEqual(@as(u64, 5), (try Seq.fromRaw(10).retreat(.fromRaw(5))).raw());
    try t.expectEqual(@as(u64, 0), (try Seq.fromRaw(10).retreat(.fromRaw(10))).raw());
    try t.expectError(error.IdUnderflow, Seq.fromRaw(10).retreat(.fromRaw(11)));
    try t.expectEqual(@as(u64, 7), (try Seq.fromRaw(3).distanceTo(Seq.fromRaw(10))).raw());
    try t.expectEqual(@as(u64, 0), (try Seq.fromRaw(3).distanceTo(Seq.fromRaw(3))).raw());
    try t.expectError(error.Backwards, Seq.fromRaw(10).distanceTo(Seq.fromRaw(3)));
    try t.expectEqual(@as(u64, std.math.maxInt(u64)), (try first.distanceTo(last)).raw());
}

test "A3 a NonZero id never steps onto zero and a tag can name the counts its ids are moved by" {
    const one = try Port.fromRaw(1);
    try t.expectError(error.IdUnderflow, one.predecessor());
    try t.expectError(error.IdUnderflow, one.retreat(.fromRaw(1)));
    try t.expectEqual(@as(u16, 1), (try (try Port.fromRaw(3)).retreat(.fromRaw(2))).raw());
    try t.expectError(error.IdExhausted, (try Port.fromRaw(std.math.maxInt(u16))).successor());
    try t.expectEqual(@as(u16, 9), (try one.advance(.fromRaw(8))).raw());

    // The sequence number of a journal moves by counts of records, and by nothing else.
    comptime std.debug.assert(Numbered.Step == Records);
    comptime std.debug.assert(Seq.Step != Records);
    const at = Numbered.fromRaw(100);
    try t.expectEqual(@as(u64, 130), (try at.advance(Records.fromRaw(30))).raw());
    try t.expectEqual(Records.fromRaw(30), try at.distanceTo(try at.advance(Records.fromRaw(30))));
}

fn idProperty(_: void, case: *shake.Case) anyerror!void {
    inline for (.{ u8, u16, u64 }) |Repr| {
        const I = a.id.Id(struct {}, Repr);
        const x = shake.gen.int(case.source, Repr);
        const n = shake.gen.int(case.source, Repr);
        const wide: u128 = @as(u128, x) + @as(u128, n);
        if (x < n) {
            try t.expectError(error.IdUnderflow, I.fromRaw(x).retreat(.fromRaw(n)));
            try t.expectError(error.Backwards, I.fromRaw(n).distanceTo(I.fromRaw(x)));
        } else {
            try t.expectEqual(@as(u128, x - n), (try I.fromRaw(x).retreat(.fromRaw(n))).raw());
            try t.expectEqual(@as(u128, x - n), (try I.fromRaw(n).distanceTo(I.fromRaw(x))).raw());
        }
        if (wide > std.math.maxInt(Repr)) {
            try t.expectError(error.IdExhausted, I.fromRaw(x).advance(.fromRaw(n)));
        } else {
            const moved = try I.fromRaw(x).advance(.fromRaw(n));
            try t.expectEqual(wide, moved.raw());
            // Moving on and measuring back, or moving back and measuring on, close the loop.
            try t.expectEqual(n, (try I.fromRaw(x).distanceTo(moved)).raw());
            try t.expectEqual(x, (try moved.retreat(.fromRaw(n))).raw());
            try t.expectEqual(moved, try I.fromRaw(x).advance(.fromRaw(n)));
        }
    }
}

test "A3 id relations match a wide oracle and close the loop between advance, retreat and distance" {
    try shake.check(t.allocator, {}, idProperty, .{ .cases = 1024, .seed = 0xa3c });
}
