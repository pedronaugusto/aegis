//! Adoption gaps: guarded entry points, leaf initialization, counted ownership, ordered units,
//! failure-free std adapters, issued-ID reads, limit predicates and by-move owner construction.
const std = @import("std");
const builtin = @import("builtin");
const shake = @import("shakedown");
const a = @import("../root.zig");
const Io = std.Io;
const t = std.testing;

const patience: Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } };

test "A6 Guarded try-acquire never waits and leaves a held lock to its holder" {
    var owner = a.Guarded(u32).init(5);
    var held = owner.tryAcquire().?;
    try t.expect(owner.tryAcquire() == null);
    try t.expect(owner.tryAcquire() == null);
    held.value().* += 1;
    held.deinit();
    var next = owner.tryAcquire().?;
    defer next.deinit();
    try t.expectEqual(@as(u32, 6), next.value().*);
}

const Yielding = struct {
    owner: a.Guarded(u32) = .init(0),
    fn take(self: *Yielding, io: Io) a.Guarded(u32).AcquireError!u32 {
        var held = try self.owner.acquireYielding(io);
        defer held.deinit();
        held.value().* += 1;
        return held.value().*;
    }
};

test "A6 Guarded yielding acquire parks through Io while held and takes the lock on release" {
    var clock: shake.Clock = .init(t.io, .{});
    const io = clock.io();
    var state: Yielding = .{};
    var holder = state.owner.acquire();
    var waiter = try io.concurrent(Yielding.take, .{ &state, io });
    // A held lock parks the waiter on the Io sleep instead of spinning for ever.
    try clock.awaitArmed(1, patience);
    holder.value().* = 10;
    holder.deinit();
    clock.advance(.fromMicroseconds(50));
    try t.expectEqual(@as(u32, 11), try waiter.await(io));
    var after = state.owner.tryAcquire().?;
    after.deinit();
}

test "A6 Guarded yielding acquire canceled while parked grants nothing and keeps the holder" {
    var clock: shake.Clock = .init(t.io, .{});
    const io = clock.io();
    var state: Yielding = .{};
    var holder = state.owner.acquire();
    var waiter = try io.concurrent(Yielding.take, .{ &state, io });
    try clock.awaitArmed(1, patience);
    try t.expectError(error.Canceled, waiter.cancel(io));
    try t.expect(state.owner.tryAcquire() == null);
    holder.deinit();
    var after = state.owner.tryAcquire().?;
    try t.expectEqual(@as(u32, 0), after.value().*);
    after.deinit();
}

fn takeUncancelable(state: *Yielding, io: Io) u32 {
    var held = state.owner.acquireYieldingUncancelable(io);
    defer held.deinit();
    held.value().* += 1;
    return held.value().*;
}
fn cancelWaiter(io: Io, waiter: *Io.Future(u32)) u32 {
    return waiter.cancel(io);
}

test "A6 Guarded uncancelable yielding acquire ignores a cancellation request while parked" {
    var clock: shake.Clock = .init(t.io, .{});
    const io = clock.io();
    var state: Yielding = .{};
    var holder = state.owner.acquire();
    var waiter = try io.concurrent(takeUncancelable, .{ &state, io });
    try clock.awaitArmed(1, patience);
    var canceler = try io.concurrent(cancelWaiter, .{ io, &waiter });
    // Give the request real time to reach the parked waiter before the lock frees.
    try t.io.sleep(.fromMilliseconds(20), .awake);
    holder.deinit();
    clock.advance(.fromMicroseconds(50));
    try t.expectEqual(@as(u32, 1), canceler.await(io));
    var after = state.owner.tryAcquire().?;
    after.deinit();
}

test "A6 Guarded yielding acquire of a free lock never touches Io" {
    var clock: shake.Clock = .init(t.io, .{});
    var state: Yielding = .{};
    try t.expectEqual(@as(u32, 1), try state.take(clock.io()));
    try t.expectEqual(@as(usize, 0), clock.armed());
}

const Mixed = struct {
    owner: a.Guarded(Counts) = .init(.{}),
    const Counts = struct { count: usize = 0, checksum: usize = 0 };
    fn bump(held: anytype) void {
        const data = held.value();
        std.debug.assert(data.checksum == data.count *% 17);
        data.count += 1;
        data.checksum = data.count *% 17;
    }
    fn worker(self: *Mixed, io: Io, rounds: usize) void {
        for (0..rounds) |round| {
            switch (round % 3) {
                0 => {
                    var held = self.owner.acquire();
                    defer held.deinit();
                    bump(&held);
                },
                1 => {
                    var held = while (true) {
                        if (self.owner.tryAcquire()) |got| break got;
                        std.atomic.spinLoopHint();
                    };
                    defer held.deinit();
                    bump(&held);
                },
                else => {
                    var held = self.owner.acquireYielding(io) catch |err| @panic(@errorName(err));
                    defer held.deinit();
                    bump(&held);
                },
            }
        }
    }
};

test "A6 Guarded acquire try-acquire and yielding acquire exclude each other natively" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var state: Mixed = .{};
    var group: Io.Group = .init;
    defer group.cancel(t.io);
    for (0..4) |_| try group.concurrent(t.io, Mixed.worker, .{ &state, t.io, 1500 });
    try group.await(t.io);
    var held = state.owner.acquire();
    defer held.deinit();
    try t.expectEqual(@as(usize, 4 * 1500), held.value().count);
    try t.expectEqual(@as(usize, 4 * 1500 * 17), held.value().checksum);
}

test "A6 teardown hands a sole owner its data without an Io or a lock" {
    var spin = a.Guarded(u32).init(1);
    try t.expectEqual(@as(u32, 1), spin.teardown().*);
    var blocking = a.BlockingGuarded(u32).init(2);
    blocking.teardown().* += 1;
    try t.expectEqual(@as(u32, 3), blocking.teardown().*);
    var shared = a.RwGuarded(u32).init(4);
    try t.expectEqual(@as(u32, 4), shared.teardown().*);
    const O = a.Order(&.{.{ .name = "root" }});
    var ordered = O.Ordered(a.BlockingGuarded(u32), 0).init(.init(8));
    try t.expectEqual(@as(u32, 8), ordered.teardown().*);
    // A guard that ended before teardown leaves the lock free, so teardown agrees with it.
    var guard = try blocking.acquire(t.io);
    guard.deinit(t.io);
    try t.expectEqual(@as(u32, 3), blocking.teardown().*);
}

const Leaf = struct {
    value: u64 = 0,
    fn make(calls: *std.atomic.Value(u32), destination: *Leaf) error{BadInit}!void {
        if (calls.fetchAdd(1, .monotonic) == 0) return error.BadInit;
        destination.value = 99;
    }
    fn cleanup(_: *Leaf) void {}
};

test "A6 Lazy failure leaves it empty, retries, and returns only the initializer's errors" {
    const L = a.Lazy(Leaf);
    comptime std.debug.assert(@typeInfo(L.Result(Leaf.make)).error_union.error_set == error{BadInit});
    comptime std.debug.assert(L.Ref == *const Leaf);
    var lazy = L.init();
    defer lazy.deinit(Leaf.cleanup);
    var calls: std.atomic.Value(u32) = .init(0);
    try t.expect(lazy.get() == null);
    try t.expectError(error.BadInit, lazy.getOrInit(t.io, &calls, Leaf.make));
    try t.expect(lazy.get() == null);
    const value = try lazy.getOrInit(t.io, &calls, Leaf.make);
    try t.expectEqual(@as(u64, 99), value.value);
    try t.expect(value == lazy.get().?);
    try t.expect(value == try lazy.getOrInit(t.io, &calls, Leaf.make));
    try t.expectEqual(@as(u32, 2), calls.load(.monotonic));
}

const Cell = struct {
    guarded: a.Guarded(u64) = .init(0),
    pub const interior_lock = true;
    fn make(calls: *std.atomic.Value(u32), destination: *Cell) void {
        _ = calls.fetchAdd(1, .monotonic);
        std.Thread.yield() catch |err| @panic(@errorName(err));
        destination.* = .{ .guarded = .init(1000) };
    }
    fn drop(cell: *Cell) void {
        std.debug.assert(cell.guarded.teardown().* >= 1000);
    }
};

test "A6 Lazy hands a self-locking leaf out mutable and lets no initializer fail" {
    const L = a.Lazy(Cell);
    comptime std.debug.assert(L.Ref == *Cell);
    comptime std.debug.assert(L.Result(Cell.make) == *Cell);
    var lazy = L.init();
    defer lazy.deinit(Cell.drop);
    var calls: std.atomic.Value(u32) = .init(0);
    const cell = lazy.getOrInit(t.io, &calls, Cell.make);
    var held = cell.guarded.acquire();
    held.value().* += 1;
    held.deinit();
    var again = lazy.get().?.guarded.acquire();
    defer again.deinit();
    try t.expectEqual(@as(u64, 1001), again.value().*);
}

const LazyRace = struct {
    lazy: a.Lazy(Cell) = .init(),
    calls: std.atomic.Value(u32) = .init(0),
    fn worker(self: *LazyRace, io: Io) void {
        for (0..64) |_| {
            const cell = self.lazy.getOrInit(io, &self.calls, Cell.make);
            var held = cell.guarded.acquire();
            defer held.deinit();
            // Every caller sees the published value, never the undefined storage.
            std.debug.assert(held.value().* >= 1000);
            held.value().* += 1;
        }
    }
};

test "A6 Lazy native race initializes exactly once and publishes to every caller" {
    if (builtin.single_threaded) return error.SkipZigTest;
    for (0..16) |_| {
        var state: LazyRace = .{};
        defer state.lazy.deinit(Cell.drop);
        var group: Io.Group = .init;
        defer group.cancel(t.io);
        for (0..8) |_| try group.concurrent(t.io, LazyRace.worker, .{ &state, t.io });
        try group.await(t.io);
        try t.expectEqual(@as(u32, 1), state.calls.load(.monotonic));
        try t.expectEqual(@as(u64, 1000 + 8 * 64), state.lazy.get().?.guarded.teardown().*);
    }
}

const SimLazy = struct {
    race: LazyRace = .{},
    fn main(self: *SimLazy, io: Io) !void {
        var tasks: [3]Io.Future(void) = undefined;
        for (&tasks) |*task| task.* = try io.concurrent(LazyRace.worker, .{ &self.race, io });
        for (&tasks) |*task| task.await(io);
        try t.expectEqual(@as(u32, 1), self.race.calls.load(.monotonic));
        try t.expectEqual(@as(u64, 1000 + 3 * 64), self.race.lazy.get().?.guarded.teardown().*);
    }
};

test "A6 Lazy simulated schedules initialize once" {
    for (0..8) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .executor = .threads, .seed = seed, .yield_per_million = 250000 });
        defer sim.deinit();
        var state: SimLazy = .{};
        defer state.race.lazy.deinit(Cell.drop);
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(SimLazy.main, .{ &state, sim.io() }));
    }
}

const Payload = struct {
    gpa: std.mem.Allocator,
    bytes: []u8,
    cleaned: *std.atomic.Value(u32),
    fn drop(self: *Payload) void {
        _ = self.cleaned.fetchAdd(1, .monotonic);
        self.gpa.free(self.bytes);
    }
};
const SharedPayload = a.Shared(Payload, Payload.drop);

test "A6 Shared cleans once at the last release and frees the block" {
    var cleaned: std.atomic.Value(u32) = .init(0);
    var first = try SharedPayload.create(t.allocator, .{ .gpa = t.allocator, .bytes = try t.allocator.alloc(u8, 8), .cleaned = &cleaned });
    var second = first.retain();
    var third = second.retain();
    try t.expect(first.get() == second.get());
    try t.expectEqual(@as(usize, 3), first.block.count.load(.monotonic));
    first.release();
    third.release();
    try t.expectEqual(@as(u32, 0), cleaned.load(.monotonic));
    second.get().bytes[0] = 1;
    second.release();
    try t.expectEqual(@as(u32, 1), cleaned.load(.monotonic));
}

fn sharedAllocation(gpa: std.mem.Allocator) !void {
    var cleaned: std.atomic.Value(u32) = .init(0);
    var source: Payload = .{ .gpa = gpa, .bytes = try gpa.alloc(u8, 4), .cleaned = &cleaned };
    errdefer source.drop();
    var owner = try SharedPayload.createFrom(gpa, &source);
    owner.release();
    try t.expectEqual(@as(u32, 1), cleaned.load(.monotonic));
}

test "A6 Shared create fails without effect on every allocation and leaves the source with the caller" {
    try t.checkAllAllocationFailures(t.allocator, sharedAllocation, .{});
}

const Churn = struct {
    shared: SharedPayload,
    fn worker(self: *Churn) void {
        for (0..2000) |_| {
            var mine = self.shared.retain();
            // The payload stays alive and readable for as long as this handle is.
            std.debug.assert(mine.get().bytes.len == 16);
            mine.release();
        }
    }
};

test "A6 Shared concurrent retain and release run cleanup exactly once on the last" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var cleaned: std.atomic.Value(u32) = .init(0);
    var churn: Churn = .{ .shared = try SharedPayload.create(t.allocator, .{ .gpa = t.allocator, .bytes = try t.allocator.alloc(u8, 16), .cleaned = &cleaned }) };
    var group: Io.Group = .init;
    defer group.cancel(t.io);
    for (0..6) |_| try group.concurrent(t.io, Churn.worker, .{&churn});
    try group.await(t.io);
    try t.expectEqual(@as(u32, 0), cleaned.load(.monotonic));
    try t.expectEqual(@as(usize, 1), churn.shared.block.count.load(.monotonic));
    churn.shared.release();
    try t.expectEqual(@as(u32, 1), cleaned.load(.monotonic));
}

const Visible = struct {
    cell: a.Guarded(u64) = .init(0),
    seen: *std.atomic.Value(u64),
    pub const interior_lock = true;
    fn drop(self: *Visible) void {
        self.seen.store(self.cell.teardown().*, .monotonic);
    }
};

fn visibleWorker(handle: a.Shared(Visible, Visible.drop)) void {
    var mine = handle;
    var held = mine.get().cell.acquire();
    held.value().* += 1;
    held.deinit();
    mine.release();
}

test "A6 Shared hands a self-locking payload out mutable and the last release sees every write" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const S = a.Shared(Visible, Visible.drop);
    comptime std.debug.assert(S.Ref == *Visible);
    var seen: std.atomic.Value(u64) = .init(0);
    var owner = try S.create(t.allocator, .{ .seen = &seen });
    var group: Io.Group = .init;
    defer group.cancel(t.io);
    for (0..8) |_| try group.concurrent(t.io, visibleWorker, .{owner.retain()});
    try group.await(t.io);
    owner.release();
    try t.expectEqual(@as(u64, 8), seen.load(.monotonic));
}

const Tick = a.id.Counter(struct {}, u8);

test "A3 Counter reads its last issued ID without issuing" {
    var counter = Tick.init(0);
    try t.expect(counter.last() == null);
    const first = try counter.next();
    try t.expectEqual(first, counter.last().?);
    try t.expectEqual(first, counter.last().?);
    const second = try counter.next();
    try t.expectEqual(@as(u8, 2), counter.last().?.raw());
    try t.expect(!first.eql(second));
    var resumed = Tick.init(254);
    try t.expectEqual(@as(u8, 254), resumed.last().?.raw());
    _ = try resumed.next();
    try t.expectError(error.IdExhausted, resumed.next());
    try t.expectEqual(@as(u8, 255), resumed.last().?.raw());
}

test "A3 counts bytes bits durations and instants compare and test equal" {
    const U = a.units;
    inline for (.{ U.Count(struct {}, i16), U.Bytes(i16), U.Bits(i16), U.Duration(.second, i16), U.Instant(.awake, .second, i16) }) |V| {
        const low = V.fromRaw(std.math.minInt(i16));
        const mid = V.fromRaw(-1);
        const high = V.fromRaw(std.math.maxInt(i16));
        try t.expectEqual(std.math.Order.lt, low.compare(mid));
        try t.expectEqual(std.math.Order.gt, high.compare(mid));
        try t.expectEqual(std.math.Order.eq, mid.compare(V.fromRaw(-1)));
        try t.expect(mid.eql(V.fromRaw(-1)));
        try t.expect(!mid.eql(high));
    }
    const Size = U.Bytes(u64);
    try t.expectEqual(std.math.Order.lt, Size.fromRaw(1).compare(Size.fromRaw(2)));
    try t.expect(Size.fromRaw(std.math.maxInt(u64)).compare(Size.fromRaw(0)) == .gt);
}

test "A3 std adapters carry no error where every value converts and keep their checks where not" {
    const U = a.units;
    // A nanosecond i128 holds all of std's i96 range, both ways round, so nothing can fail.
    const Wide = U.Duration(.nanosecond, i128);
    comptime std.debug.assert(Wide.FromIoDurationError == error{});
    comptime std.debug.assert(@TypeOf(Wide.fromIoDuration(.zero, .exact)) == Wide);
    const extreme: Io.Duration = .fromNanoseconds(std.math.minInt(i96));
    try t.expectEqual(@as(i128, std.math.minInt(i96)), Wide.fromIoDuration(extreme, .exact).raw());
    try t.expectEqual(Io.Duration.max, try Wide.fromIoDuration(.max, .exact).toIoDuration());
    // A millisecond i64 widens into nanoseconds without a check, but narrowing back can lose data.
    const Ms = U.Duration(.millisecond, i64);
    comptime std.debug.assert(Ms.ToIoDurationError == error{});
    comptime std.debug.assert(@TypeOf(Ms.fromRaw(1).toIoDuration()) == Io.Duration);
    try t.expectEqual(@as(i96, std.math.maxInt(i64)) * 1_000_000, Ms.fromRaw(std.math.maxInt(i64)).toIoDuration().nanoseconds);
    try t.expectError(error.Overflow, Ms.fromIoDuration(.max, .down));
    try t.expectError(error.Inexact, Ms.fromIoDuration(.fromNanoseconds(1), .exact));
    try t.expectEqual(@as(i64, 1), (try Ms.fromIoDuration(.fromNanoseconds(1), .up)).raw());
    // An unsigned span cannot take a negative std duration.
    const Unsigned = U.Duration(.nanosecond, u64);
    try t.expectError(error.Overflow, Unsigned.fromIoDuration(.fromNanoseconds(-1), .exact));
    // Seconds of an i64 overflow std's nanoseconds only at the top, so the widening keeps its check there.
    const Minutes = U.Duration(.minute, i64);
    comptime std.debug.assert(Minutes.ToIoDurationError == error{Overflow});
    try t.expectError(error.Overflow, Minutes.fromRaw(std.math.maxInt(i64)).toIoDuration());
}

test "A3 instants take std timestamps raw or clock-tagged with the same checks" {
    const U = a.units;
    const Wide = U.Instant(.awake, .nanosecond, i128);
    const stamp: Io.Timestamp = .fromNanoseconds(std.math.maxInt(i96));
    comptime std.debug.assert(@TypeOf(Wide.fromTimestamp(stamp, .exact)) == Wide);
    try t.expectEqual(stamp, try Wide.fromTimestamp(stamp, .exact).toTimestamp());
    const Ns = U.Instant(.awake, .nanosecond, i64);
    comptime std.debug.assert(@TypeOf(Ns.fromRaw(1).toTimestamp()) == Io.Timestamp);
    try t.expectError(error.Overflow, Ns.fromTimestamp(stamp, .exact));
    const now: Io.Timestamp = .fromNanoseconds(123_456_789);
    try t.expectEqual(@as(i64, 123_456_789), (try Ns.fromTimestamp(now, .exact)).raw());
    try t.expectEqual(now, Ns.fromRaw(123_456_789).toTimestamp());
    const Us = U.Instant(.awake, .microsecond, i64);
    try t.expectError(error.Inexact, Us.fromTimestamp(now, .exact));
    try t.expectEqual(@as(i64, 123_456), (try Us.fromTimestamp(now, .down)).raw());
    try t.expectEqual(@as(i64, 123_457), (try Us.fromTimestamp(now, .up)).raw());
    // The clock-tagged form still checks the clock and shares the raw form's range.
    try t.expectError(error.ClockMismatch, Ns.fromIoTimestamp(now.withClock(.real), .exact));
    try t.expectEqual(@as(i64, 123_456_789), (try Ns.fromIoTimestamp(now.withClock(.awake), .exact)).raw());
    try t.expectEqual(Io.Clock.awake, Ns.fromRaw(1).toIoTimestamp().clock);
}

fn adapterProperty(_: void, case: *shake.Case) anyerror!void {
    const U = a.units;
    const nanos = shake.gen.int(case.source, i96);
    const wide = @as(i256, nanos);
    inline for (.{
        .{ U.Duration(.nanosecond, i64), 1, i64 },
        .{ U.Duration(.millisecond, i64), 1_000_000, i64 },
        .{ U.Duration(.second, i32), 1_000_000_000, i32 },
        .{ U.Duration(.nanosecond, i128), 1, i128 },
        .{ U.Duration(.day, i16), 86_400_000_000_000, i16 },
    }) |row| {
        const D, const scale, const Repr = row;
        inline for (.{ .down, .up, .exact }) |rounding| {
            const floor = @divFloor(wide, scale);
            const exact = @mod(wide, scale) == 0;
            const expected = if (rounding == .up) floor + @intFromBool(!exact) else floor;
            const fits = expected >= std.math.minInt(Repr) and expected <= std.math.maxInt(Repr);
            const converted = D.fromIoDuration(.fromNanoseconds(nanos), rounding);
            const lifted: anyerror!D = converted;
            if (rounding == .exact and !exact) {
                try t.expectError(error.Inexact, lifted);
            } else if (!fits) {
                try t.expectError(error.Overflow, lifted);
            } else {
                try t.expectEqual(expected, @as(i256, (try lifted).raw()));
            }
        }
    }
}

test "A3 std duration adapters match a wide oracle across units and roundings" {
    try shake.check(t.allocator, {}, adapterProperty, .{ .cases = 512, .seed = 0xa3a });
}

const Limit8 = a.bounded.Limit(u8);

test "A7 Limit exceeds is the boolean form of check at and around the maximum" {
    for ([_]u8{ 0, 1, 7, 254, 255 }) |maximum| {
        const limit = Limit8.init(maximum);
        for ([_]u8{ 0, 1, 6, 7, 8, 254, 255 }) |amount| {
            try t.expectEqual(amount > maximum, limit.exceeds(amount));
            if (limit.exceeds(amount)) try t.expectError(error.LimitExceeded, limit.check(amount)) else try limit.check(amount);
        }
    }
    try t.expect(!Limit8.init(255).exceeds(255));
    try t.expect(Limit8.init(0).exceeds(1));
}

const Budget8 = a.bounded.Budget(u8);
const Held = a.own.Owned(Budget8.Reservation, Budget8.Reservation.release);

test "A7 Owned takes a reservation by move so it releases once" {
    var budget = Budget8.init(10);
    var reservation = try budget.reserve(7);
    try t.expectEqual(@as(u8, 3), budget.remaining());
    var owner = Held.initFrom(&reservation);
    // The source was consumed: the one charge belongs to the owner alone.
    if (builtin.optimize == .debug) try t.expect(!reservation.live);
    try t.expectEqual(@as(u8, 3), budget.remaining());
    owner.deinit();
    try t.expectEqual(@as(u8, 10), budget.remaining());
}

test "A7 Owned init by move erases an inline secret source and keeps plain payloads by value" {
    const S = a.own.Owned(a.Secret([4]u8), secretDrop);
    var secret = a.Secret([4]u8).init(.{ 1, 2, 3, 4 });
    var owner = S.initFrom(&secret);
    defer owner.deinit();
    try t.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, owner.borrow().expose());
    try t.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, std.mem.asBytes(&secret));
    const P = a.own.Owned(u32, plainDrop);
    var value: u32 = 9;
    var plain = P.initFrom(&value);
    defer plain.deinit();
    try t.expectEqual(@as(u32, 9), plain.borrow().*);
}

fn secretDrop(secret: *a.Secret([4]u8)) void {
    secret.deinit();
}
fn plainDrop(_: *u32) void {}
