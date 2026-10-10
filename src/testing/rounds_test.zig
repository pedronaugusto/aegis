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
        inline for (.{ std.lang.Endian.little, std.lang.Endian.big }) |endian| {
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

test "A6 native isHeld sees another task's hold and its release" {
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

fn ErrorsOf(comptime Result: type) type {
    return switch (@typeInfo(Result)) {
        .error_union => |info| info.error_set,
        else => error{},
    };
}

test "A3 a cast that cannot fail carries no error and the portable usize rule holds on every target" {
    const cast = a.int.cast;
    // Widening and the identity are plain values.
    comptime std.debug.assert(@TypeOf(cast(u64, @as(u32, 1))) == u64);
    comptime std.debug.assert(@TypeOf(cast(i16, @as(u8, 1))) == i16);
    comptime std.debug.assert(@TypeOf(cast(u32, @as(u32, 1))) == u32);
    // Narrowing and sign loss keep the one error.
    comptime std.debug.assert(@TypeOf(cast(u8, @as(u16, 1))) == a.int.CastError!u8);
    comptime std.debug.assert(@TypeOf(cast(u64, @as(i64, 1))) == a.int.CastError!u64);
    // usize is at least 32 and at most 64 bits: what holds on all of them holds here.
    comptime std.debug.assert(@TypeOf(cast(usize, @as(u32, 1))) == usize);
    comptime std.debug.assert(@TypeOf(cast(usize, @as(u16, 1))) == usize);
    comptime std.debug.assert(@TypeOf(cast(u64, @as(usize, 1))) == u64);
    comptime std.debug.assert(@TypeOf(cast(isize, @as(i32, 1))) == isize);
    comptime std.debug.assert(@TypeOf(cast(i64, @as(isize, 1))) == i64);
    // What fits only on a wide target keeps its check on all of them, so portable code compiles everywhere.
    comptime std.debug.assert(@TypeOf(cast(usize, @as(u64, 1))) == a.int.CastError!usize);
    comptime std.debug.assert(@TypeOf(cast(u32, @as(usize, 1))) == a.int.CastError!u32);
    comptime std.debug.assert(@TypeOf(cast(isize, @as(u32, 1))) == a.int.CastError!isize);
    comptime std.debug.assert(@TypeOf(cast(usize, @as(i8, 1))) == a.int.CastError!usize);
    comptime std.debug.assert(@TypeOf(cast(usize, @as(usize, 1))) == usize);
    // A comptime-known source is checked against the target range, as before.
    comptime std.debug.assert(@TypeOf(cast(u8, 255)) == a.int.CastError!u8);
    try t.expectEqual(@as(u64, 4_000_000_000), cast(u64, @as(u32, 4_000_000_000)));
    try t.expectEqual(@as(usize, 7), cast(usize, @as(u32, 7)));
    try t.expectEqual(@as(i16, -128), cast(i16, @as(i8, -128)));
}

test "A3 unit conversions carry the errors they can have and none where every value converts" {
    const U = a.units;
    const Tag = struct {};
    comptime std.debug.assert(@TypeOf(U.Count(Tag, u16).fromRaw(1).convert(u32)) == U.Count(Tag, u32));
    comptime std.debug.assert(@TypeOf(U.Count(Tag, u32).fromRaw(1).convert(usize)) == U.Count(Tag, usize));
    comptime std.debug.assert(@TypeOf(U.Count(Tag, u64).fromRaw(1).convert(usize)) == a.int.CastError!U.Count(Tag, usize));
    comptime std.debug.assert(@TypeOf(U.Bytes(u32).fromRaw(1).convert(u64)) == U.Bytes(u64));
    comptime std.debug.assert(@TypeOf(U.Bytes(u64).fromRaw(1).convert(u32)) == a.int.CastError!U.Bytes(u32));
    comptime std.debug.assert(@TypeOf(U.Bits(i8).fromRaw(1).convert(i16)) == U.Bits(i16));
    comptime std.debug.assert(@TypeOf(U.Bits(i16).fromRaw(1).convert(u16)) == a.int.CastError!U.Bits(u16));
    // A unit conversion: finer into a wide enough representation cannot fail, coarser can be inexact only,
    // finer into the same width can overflow only, and both together keep both.
    const Ms = U.Duration(.millisecond, i32);
    comptime std.debug.assert(@TypeOf(Ms.fromRaw(1).convert(.nanosecond, i64, .exact)) == U.Duration(.nanosecond, i64));
    comptime std.debug.assert(ErrorsOf(@TypeOf(Ms.fromRaw(1).convert(.nanosecond, i32, .exact))) == error{Overflow});
    comptime std.debug.assert(ErrorsOf(@TypeOf(Ms.fromRaw(1).convert(.second, i32, .exact))) == error{Inexact});
    comptime std.debug.assert(ErrorsOf(@TypeOf(Ms.fromRaw(1).convert(.second, i16, .exact))) == error{ Overflow, Inexact });
    comptime std.debug.assert(@TypeOf(U.Instant(.real, .second, u32).fromRaw(1).convert(.millisecond, u64, .exact)) == U.Instant(.real, .millisecond, u64));
    comptime std.debug.assert(ErrorsOf(@TypeOf(U.Instant(.real, .second, u32).fromRaw(1).convert(.millisecond, u32, .exact))) == error{Overflow});
    // Rounding down or up always has an answer, so only an exact conversion can be inexact.
    comptime std.debug.assert(@TypeOf(Ms.fromRaw(1).convert(.second, i32, .down)) == U.Duration(.second, i32));
    comptime std.debug.assert(@TypeOf(Ms.fromRaw(1).convert(.second, i32, .up)) == U.Duration(.second, i32));
    comptime std.debug.assert(ErrorsOf(@TypeOf(Ms.fromRaw(1).convert(.second, i16, .down))) == error{Overflow});
    comptime std.debug.assert(@TypeOf(U.Duration(.nanosecond, u64).fromRaw(1).convert(.day, u32, .down)) == U.Duration(.day, u32));
    comptime std.debug.assert(@TypeOf(U.Duration(.nanosecond, i128).fromIoDuration(.zero, .exact)) == U.Duration(.nanosecond, i128));
    comptime std.debug.assert(@TypeOf(U.Duration(.second, i128).fromIoDuration(.zero, .down)) == U.Duration(.second, i128));
    comptime std.debug.assert(ErrorsOf(@TypeOf(U.Duration(.second, i64).fromIoDuration(.zero, .down))) == error{Overflow});
    comptime std.debug.assert(ErrorsOf(@TypeOf(U.Duration(.second, i128).fromIoDuration(.zero, .exact))) == error{Inexact});
    comptime std.debug.assert(@TypeOf(U.Instant(.awake, .second, i128).fromTimestamp(.zero, .up)) == U.Instant(.awake, .second, i128));
    comptime std.debug.assert(ErrorsOf(@TypeOf(U.Instant(.awake, .second, i128).fromIoTimestamp(.{ .raw = .zero, .clock = .awake }, .down))) == error{ClockMismatch});
    try t.expectEqual(@as(i64, 2_147_483_647_000_000), Ms.fromRaw(std.math.maxInt(i32)).convert(.nanosecond, i64, .exact).raw());
    try t.expectEqual(@as(i64, -1), Ms.fromRaw(-1).convert(.millisecond, i64, .exact).raw());
}

fn convertProperty(_: void, case: *shake.Case) anyerror!void {
    @setEvalBranchQuota(100_000);
    const U = a.units;
    const rows = .{
        .{ U.Unit.nanosecond, U.Unit.microsecond },
        .{ U.Unit.millisecond, U.Unit.nanosecond },
        .{ U.Unit.second, U.Unit.minute },
        .{ U.Unit.day, U.Unit.second },
    };
    inline for (.{ i32, u64 }) |Source| {
        const value = shake.gen.int(case.source, Source);
        inline for (.{ i16, u32, i64 }) |Target| {
            inline for (rows) |row| {
                const from, const to = row;
                const numerator = from.nanoseconds();
                const denominator = to.nanoseconds();
                inline for (.{ .down, .up, .exact }) |rounding| {
                    const product = @as(i256, value) * numerator;
                    const floor = @divFloor(product, denominator);
                    const exact = @mod(product, denominator) == 0;
                    const expected = if (rounding == .up) floor + @intFromBool(!exact) else floor;
                    const fits = expected >= std.math.minInt(Target) and expected <= std.math.maxInt(Target);
                    const lifted: anyerror!U.Duration(to, Target) = U.Duration(from, Source).fromRaw(value).convert(to, Target, rounding);
                    const lifted_instant: anyerror!U.Instant(.awake, to, Target) = U.Instant(.awake, from, Source).fromRaw(value).convert(to, Target, rounding);
                    // An unsigned target never takes a negative value, and that is reported before inexactness.
                    if (@typeInfo(Target).int.signedness == .unsigned and value < 0) {
                        try t.expectError(error.Overflow, lifted);
                        try t.expectError(error.Overflow, lifted_instant);
                    } else if (rounding == .exact and !exact) {
                        try t.expectError(error.Inexact, lifted);
                        try t.expectError(error.Inexact, lifted_instant);
                    } else if (!fits) {
                        try t.expectError(error.Overflow, lifted);
                        try t.expectError(error.Overflow, lifted_instant);
                    } else {
                        try t.expectEqual(expected, @as(i256, (try lifted).raw()));
                        try t.expectEqual(expected, @as(i256, (try lifted_instant).raw()));
                    }
                }
            }
        }
    }
}

test "A3 unit conversions match a wide oracle across units, widths and roundings" {
    try shake.check(t.allocator, {}, convertProperty, .{ .cases = 512, .seed = 0xa3d });
}

const Drain = struct {
    owner: a.BlockingGuarded(u32) = .init(0),
    changed: a.Condition = .initLimit(4),
    started: Io.Event = .unset,
    done: Io.Event = .unset,
    fn drain(self: *Drain, io: Io) a.Condition.UncancelableWaitError!u32 {
        var held = self.owner.acquireUncancelable(io);
        defer held.deinit(io);
        self.started.set(io);
        // A cleanup path: it waits for the state change however it was asked to stop.
        while (held.value().* == 0) try self.changed.waitUncancelable(io, &held, .none);
        return held.value().*;
    }
    fn cancelIt(io: Io, future: *Io.Future(a.Condition.UncancelableWaitError!u32), done: *Io.Event) a.Condition.UncancelableWaitError!u32 {
        defer done.set(io);
        return future.cancel(io);
    }
    fn main(self: *Drain, io: Io) !void {
        var waiter = try io.concurrent(drain, .{ self, io });
        try self.started.wait(io);
        var canceler = try io.concurrent(cancelIt, .{ io, &waiter, &self.done });
        // The request is out while the waiter is parked; neither it nor spurious wakes end the wait.
        try io.sleep(.fromMilliseconds(5), .awake);
        var held = self.owner.acquireUncancelable(io);
        held.value().* = 7;
        self.changed.signal(io);
        held.deinit(io);
        try t.expectEqual(@as(u32, 7), try canceler.await(io));
        try t.expectEqual(@as(usize, 0), self.changed.count);
    }
};

test "A6 Condition waitUncancelable is not ended by a cancellation request and returns on the signal" {
    for (0..8) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .executor = .threads, .seed = seed, .yield_per_million = 250000, .spurious_wake_per_million = 300000 });
        defer sim.deinit();
        var state: Drain = .{};
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(Drain.main, .{ &state, sim.io() }));
    }
}

const DrainTimeout = struct {
    owner: a.BlockingGuarded(u32) = .init(0),
    changed: a.Condition = .initLimit(1),
    fn main(self: *DrainTimeout, io: Io) !void {
        var held = self.owner.acquireUncancelable(io);
        defer held.deinit(io);
        const deadline = (Io.Timeout{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } }).toDeadline(io);
        try t.expectError(error.Timeout, self.changed.waitUncancelable(io, &held, deadline));
        // The guard is held on every return, and the registration is gone.
        try t.expect(self.owner.tryAcquire() == null);
        try t.expectEqual(@as(usize, 0), self.changed.count);
    }
};

test "A6 Condition waitUncancelable still ends at its deadline and at the waiter ceiling, with the guard held" {
    for (0..4) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .executor = .threads, .seed = seed, .spurious_wake_per_million = 300000 });
        defer sim.deinit();
        var state: DrainTimeout = .{};
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(DrainTimeout.main, .{ &state, sim.io() }));
    }
    var owner = a.BlockingGuarded(u32).init(1);
    var changed = a.Condition.initLimit(0);
    var held = owner.acquireUncancelable(t.io);
    defer held.deinit(t.io);
    try t.expectError(error.WaiterLimit, changed.waitUncancelable(t.io, &held, .none));
    try t.expect(owner.tryAcquire() == null);
}

const Rank = a.Order(&.{ .{ .name = "outer" }, .{ .name = "inner", .after = &.{0} } });
const Outer = Rank.Ordered(a.BlockingGuarded(u32), 0);
const Inner = Rank.Ordered(a.BlockingGuarded(u32), 1);

const OrderedCleanup = struct {
    outer: Outer = .init(.init(0)),
    started: Io.Event = .unset,
    fn waiter(self: *OrderedCleanup, io: Io) u32 {
        var context: Rank.Context = .{};
        var held = self.outer.acquireOrderedUncancelable(io, &context);
        defer held.deinit(io);
        self.started.set(io);
        held.value().* += 1;
        return held.value().*;
    }
    fn cancelIt(io: Io, future: *Io.Future(u32)) u32 {
        return future.cancel(io);
    }
    fn main(self: *OrderedCleanup, io: Io) !void {
        var context: Rank.Context = .{};
        var first = try self.outer.acquireOrdered(io, &context);
        var waiter_future = try io.concurrent(waiter, .{ self, io });
        var canceler = try io.concurrent(cancelIt, .{ io, &waiter_future });
        try io.sleep(.fromMilliseconds(5), .awake);
        first.value().* = 10;
        first.deinit(io);
        // The request reached the parked waiter, and it still took the lock.
        try t.expectEqual(@as(u32, 11), canceler.await(io));
    }
};

test "A6 ordered uncancelable acquire takes the lock under a cancellation request and keeps the rank discipline" {
    for (0..8) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .executor = .threads, .seed = seed, .yield_per_million = 250000 });
        defer sim.deinit();
        var state: OrderedCleanup = .{};
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(OrderedCleanup.main, .{ &state, sim.io() }));
    }
    // The ranks still order: inner may be taken under outer, and the context pops in order.
    var outer: Outer = .init(.init(1));
    var inner: Inner = .init(.init(2));
    var context: Rank.Context = .{};
    var a_guard = outer.acquireOrderedUncancelable(t.io, &context);
    try context.check(&inner, 1);
    var b_guard = inner.acquireOrderedUncancelable(t.io, &context);
    try t.expectEqual(@as(u32, 2), b_guard.value().*);
    b_guard.deinit(t.io);
    a_guard.deinit(t.io);
    try t.expect(outer.isHeld() == false);
}

fn drop(_: *u32) void {}

test "A7 bounded containers read their capacity and fullness exactly where the next element is refused" {
    var array = a.bounded.Array(u32, 2).init;
    try t.expectEqual(@as(usize, 2), array.capacity());
    try t.expect(!array.isFull());
    var value: u32 = 1;
    try array.append(&value);
    try t.expect(!array.isFull());
    try array.append(&value);
    try t.expect(array.isFull());
    try t.expectError(error.Full, array.append(&value));
    var out: u32 = 0;
    try array.pop(&out);
    try t.expect(!array.isFull());
    var empty = a.bounded.Array(u32, 0).init;
    try t.expectEqual(@as(usize, 0), empty.capacity());
    try t.expect(empty.isFull());

    var ring = a.bounded.Ring(u32, 3).init;
    try t.expectEqual(@as(usize, 3), ring.capacity());
    for (0..3) |_| {
        try t.expect(!ring.isFull());
        try ring.push(&value);
    }
    try t.expect(ring.isFull());
    try t.expectError(error.Full, ring.push(&value));
    try ring.pop(&out);
    try t.expect(!ring.isFull());
    try ring.push(&value); // wrapped
    try t.expect(ring.isFull());

    var storage: [2]u32 = undefined;
    var buffer = a.bounded.Buffer(u32).initBuffer(&storage);
    try t.expectEqual(@as(usize, 2), buffer.capacity());
    try buffer.append(&value);
    try buffer.append(&value);
    try t.expect(buffer.isFull());
    try t.expectError(error.Full, buffer.append(&value));

    // A buffer that grows reports the capacity it has, and is full only at that capacity.
    var grown = try a.bounded.Buffer(u32).initAllocated(t.allocator, 1, 4);
    defer grown.deinit(drop);
    try t.expectEqual(@as(usize, 1), grown.capacity());
    try grown.append(&value);
    try t.expect(grown.isFull());
    try grown.reserve(3);
    try t.expectEqual(@as(usize, 3), grown.capacity());
    try t.expect(!grown.isFull());

    var queue = try a.bounded.RingBuffer(u32).initAllocated(t.allocator, 2, 4);
    defer queue.deinit(drop);
    try queue.push(&value);
    try queue.push(&value);
    try t.expect(queue.isFull());
    try queue.pop(&out);
    try queue.push(&value); // wrapped at the capacity it has
    try t.expect(queue.isFull());
    try queue.reserve(4);
    try t.expectEqual(@as(usize, 4), queue.capacity());
    try t.expect(!queue.isFull());
}

test "A7 Budget reads its maximum and charge, and reserveKeeping leaves room for the control path" {
    const Budget = a.bounded.Budget(u32);
    var budget = Budget.init(10);
    try t.expectEqual(@as(u32, 10), budget.maximum());
    try t.expectEqual(@as(u32, 0), budget.charged());
    try t.expectEqual(@as(u32, 10), budget.remaining());

    // Ordinary admission keeps two units back for the control path.
    var first = try budget.reserveKeeping(6, 2);
    try t.expectEqual(@as(u32, 6), budget.charged());
    try t.expectError(error.LimitExceeded, budget.reserveKeeping(3, 2));
    try t.expectEqual(@as(u32, 6), budget.charged());
    var second = try budget.reserveKeeping(2, 2);
    try t.expectEqual(@as(u32, 8), budget.charged());
    try t.expectError(error.LimitExceeded, budget.reserveKeeping(1, 2));
    // A kept amount larger than what is free refuses instead of underflowing.
    try t.expectError(error.LimitExceeded, budget.reserveKeeping(0, 3));
    // The control path takes plain `reserve` and finds the room kept for it.
    var control = try budget.reserve(2);
    try t.expectEqual(@as(u32, 10), budget.charged());
    try t.expectEqual(@as(u32, 0), budget.remaining());
    try t.expectError(error.LimitExceeded, budget.reserve(1));
    try t.expectEqual(@as(u32, 10), budget.maximum());
    // Never above the maximum, and releasing restores what each held.
    control.release();
    try t.expectEqual(@as(u32, 2), budget.remaining());
    second.release();
    first.release();
    try t.expectEqual(@as(u32, 0), budget.charged());
    // Keeping nothing is a plain reserve.
    var plain = try budget.reserveKeeping(10, 0);
    try t.expectEqual(@as(u32, 0), budget.remaining());
    plain.release();
    try budget.consume(4);
    try t.expectEqual(@as(u32, 4), budget.charged());
}

const Phase = enum(u8) { idle, running, stopping, stopped };
const Hits = a.units.Count(struct {}, u8);
const Total = a.units.Bytes(u64);
const Ticket = a.id.Id(struct {}, u32);

test "A6 Atomic holds a distinct scalar whole and exchanges it without the backing integer" {
    const Cell = a.Atomic(Phase);
    comptime std.debug.assert(@sizeOf(Cell) == @sizeOf(u8) and @alignOf(Cell) == @alignOf(u8));
    comptime std.debug.assert(@sizeOf(a.Atomic(Ticket)) == @sizeOf(u32));
    comptime std.debug.assert(@sizeOf(a.Atomic(a.units.Instant(.awake, .nanosecond, u64))) == @sizeOf(u64));
    var cell: Cell = .init(.idle);
    try t.expectEqual(Phase.idle, cell.load(.acquire));
    cell.store(.running, .release);
    try t.expectEqual(Phase.running, cell.swap(.stopping, .acq_rel));
    try t.expectEqual(Phase.stopping, cell.load(.monotonic));
    // A failed exchange reports what it found; a successful one reports null.
    try t.expectEqual(@as(?Phase, .stopping), cell.cmpxchgStrong(.running, .stopped, .acq_rel, .acquire));
    try t.expectEqual(@as(?Phase, null), cell.cmpxchgStrong(.stopping, .stopped, .acq_rel, .acquire));
    try t.expectEqual(Phase.stopped, cell.load(.acquire));
    var tickets: a.Atomic(Ticket) = .init(Ticket.fromRaw(5));
    while (tickets.cmpxchgWeak(Ticket.fromRaw(5), Ticket.fromRaw(6), .acq_rel, .monotonic) != null) {}
    try t.expectEqual(Ticket.fromRaw(6), tickets.load(.acquire));
    // The high-water mark of a measure: orders by the backing integer.
    var peak: a.Atomic(Total) = .init(.fromRaw(10));
    try t.expectEqual(Total.fromRaw(10), peak.fetchMax(.fromRaw(30), .monotonic));
    try t.expectEqual(Total.fromRaw(30), peak.fetchMax(.fromRaw(20), .monotonic));
    try t.expectEqual(Total.fromRaw(30), peak.fetchMin(.fromRaw(5), .monotonic));
    try t.expectEqual(Total.fromRaw(5), peak.load(.monotonic));
}

test "A6 Atomic checked arithmetic reports overflow without changing the cell and the wrapping forms wrap" {
    var hits: a.Atomic(Hits) = .init(.fromRaw(250));
    try t.expectEqual(Hits.fromRaw(250), try hits.fetchAdd(.fromRaw(5), .monotonic));
    try t.expectEqual(Hits.fromRaw(255), hits.load(.monotonic));
    try t.expectError(error.Overflow, hits.fetchAdd(.fromRaw(1), .monotonic));
    try t.expectEqual(Hits.fromRaw(255), hits.load(.monotonic));
    try t.expectEqual(Hits.fromRaw(255), try hits.fetchSub(.fromRaw(255), .monotonic));
    try t.expectError(error.Underflow, hits.fetchSub(.fromRaw(1), .monotonic));
    try t.expectEqual(Hits.fromRaw(0), hits.load(.monotonic));
    // The hardware instruction wraps, and says so in its name.
    try t.expectEqual(Hits.fromRaw(0), hits.fetchSubWrapping(.fromRaw(1), .monotonic));
    try t.expectEqual(Hits.fromRaw(255), hits.load(.monotonic));
    try t.expectEqual(Hits.fromRaw(255), hits.fetchAddWrapping(.fromRaw(2), .monotonic));
    try t.expectEqual(Hits.fromRaw(1), hits.load(.monotonic));
    var span: a.Atomic(a.units.Duration(.millisecond, i16)) = .init(.fromRaw(-3));
    try t.expectEqual(@as(i16, -3), (try span.fetchAdd(.fromRaw(10), .acq_rel)).raw());
    try t.expectError(error.Overflow, span.fetchAdd(.fromRaw(32767), .acq_rel));
    try t.expectEqual(@as(i16, 7), span.load(.acquire).raw());
}

const Counting = struct {
    cell: a.Atomic(Hits) = .init(.fromRaw(0)),
    won: std.atomic.Value(u32) = .init(0),
    fn worker(self: *Counting) void {
        for (0..100) |_| {
            if (self.cell.fetchAdd(.fromRaw(1), .monotonic)) |_| {
                _ = self.won.fetchAdd(1, .monotonic);
            } else |_| {}
        }
    }
};

test "A6 native Atomic checked adds race to exactly the maximum and never past it" {
    if (builtin.single_threaded) return error.SkipZigTest;
    for (0..8) |_| {
        var state: Counting = .{};
        var group: Io.Group = .init;
        defer group.cancel(t.io);
        for (0..4) |_| try group.concurrent(t.io, Counting.worker, .{&state});
        try group.await(t.io);
        // 400 attempts at a u8: exactly 255 succeed, and the cell holds exactly that many.
        try t.expectEqual(@as(u32, 255), state.won.load(.monotonic));
        try t.expectEqual(Hits.fromRaw(255), state.cell.load(.monotonic));
    }
}
