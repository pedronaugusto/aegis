//! Necessary handwritten operations paired with the adoption-gap capabilities.
const std = @import("std");
const a = @import("aegis");
const Io = std.Io;
const base = @import("a67.zig");

/// The hand-written spin owner: a lock beside its data.
pub const DirectSpin = struct { lock: std.atomic.Value(bool) = .init(false), data: usize };
pub fn Owner(comptime wrapped: bool) type {
    return if (wrapped) a.Guarded(usize) else DirectSpin;
}
pub const DirectLazy = struct { state: std.atomic.Value(enum(u8) { empty, ready }) = .init(.empty), mutex: Io.Mutex = .init, data: u64 = undefined };
pub const DirectBlock = struct { count: std.atomic.Value(usize) = .init(1), gpa: std.mem.Allocator, data: u64 };
pub const handle_limit = std.math.maxInt(usize) / 2;
const Counted = a.Shared(u64, drop);
pub const Handle = Counted;
pub const Payload = struct { output: *u64, value: u64 };
const Held = a.own.Owned(Payload, release);

/// The cleanup both sides run on the last release; observable, so it is never elided.
fn drop(value: *u64) void {
    std.mem.doNotOptimizeAway(value);
    value.* = 0;
}
fn release(payload: *Payload) void {
    payload.output.* +%= payload.value;
}

pub fn tryAcquire(comptime wrapped: bool, owner: *Owner(wrapped)) bool {
    if (wrapped) {
        var held = owner.tryAcquire() orelse return false;
        defer held.deinit();
        held.value().* +%= 1;
        return true;
    }
    if (owner.lock.swap(true, .acquire)) return false;
    defer owner.lock.store(false, .release);
    owner.data +%= 1;
    return true;
}

pub fn teardown(comptime wrapped: bool, owner: *Owner(wrapped)) usize {
    if (wrapped) return owner.teardown().*;
    std.debug.assert(!owner.lock.load(.monotonic));
    return owner.data;
}

pub fn lazyReady(comptime wrapped: bool, owner: if (wrapped) *a.Lazy(u64) else *DirectLazy) ?*const u64 {
    if (wrapped) return owner.get();
    return if (owner.state.load(.acquire) == .ready) &owner.data else null;
}
fn make(seed: u64, destination: *u64) void {
    destination.* = seed;
}
fn makeFallible(seed: u64, destination: *u64) error{Refused}!void {
    if (seed == 0) return error.Refused;
    destination.* = seed;
}
pub fn lazyCold(comptime wrapped: bool, io: Io, owner: if (wrapped) *a.Lazy(u64) else *DirectLazy, seed: u64) error{Refused}!*const u64 {
    if (wrapped) return owner.getOrInit(io, seed, makeFallible);
    if (owner.state.load(.acquire) == .ready) return &owner.data;
    owner.mutex.lockUncancelable(io);
    defer owner.mutex.unlock(io);
    if (owner.state.load(.monotonic) == .empty) {
        try makeFallible(seed, &owner.data);
        owner.state.store(.ready, .release);
    }
    return &owner.data;
}
pub fn lazyInfallible(comptime wrapped: bool, io: Io, owner: if (wrapped) *a.Lazy(u64) else *DirectLazy, seed: u64) *const u64 {
    if (wrapped) return owner.getOrInit(io, seed, make);
    if (owner.state.load(.acquire) == .ready) return &owner.data;
    owner.mutex.lockUncancelable(io);
    defer owner.mutex.unlock(io);
    if (owner.state.load(.monotonic) == .empty) {
        make(seed, &owner.data);
        owner.state.store(.ready, .release);
    }
    return &owner.data;
}

/// The hand-written handle: one pointer to the counted block, as `Handle` is.
pub const DirectHandle = struct { block: *DirectBlock };
pub fn sharedRetain(comptime wrapped: bool, owner: if (wrapped) *const Handle else *const DirectHandle) if (wrapped) Handle else DirectHandle {
    if (wrapped) return owner.retain();
    const before = owner.block.count.fetchAdd(1, .monotonic);
    if (before >= handle_limit) @panic("shared owner handle count overflow");
    return .{ .block = owner.block };
}
pub fn sharedGet(comptime wrapped: bool, owner: if (wrapped) *const Handle else *const DirectHandle) *const u64 {
    if (wrapped) return owner.get();
    return &owner.block.data;
}
pub fn sharedRelease(comptime wrapped: bool, owner: if (wrapped) *Handle else *DirectHandle) void {
    if (wrapped) return owner.release();
    const block = owner.block;
    if (block.count.fetchSub(1, .release) != 1) return;
    _ = block.count.load(.acquire);
    drop(&block.data);
    const gpa = block.gpa;
    gpa.destroy(block);
}

pub fn ownedFrom(comptime wrapped: bool, source: *Payload, fail: bool) void {
    if (wrapped) {
        var owner = Held.initFrom(source);
        defer owner.deinit();
        if (fail) return;
        owner.borrowMut().value +%= 1;
    } else {
        var payload = source.*;
        defer release(&payload);
        if (fail) return;
        payload.value +%= 1;
    }
}

const Tag = struct {};
pub fn compare(comptime wrapped: bool, x: u64, y: u64) i8 {
    if (wrapped) return @backingInt(a.units.Count(Tag, u64).fromRaw(x).compare(.fromRaw(y)));
    return @backingInt(std.math.order(x, y));
}
pub fn equal(comptime wrapped: bool, x: u64, y: u64) bool {
    if (wrapped) return a.units.Bytes(u64).fromRaw(x).eql(.fromRaw(y));
    return x == y;
}
pub fn last(comptime wrapped: bool, issued: u64) u64 {
    if (wrapped) {
        const counter = a.id.Counter(Tag, u64).init(issued);
        return if (counter.last()) |id| id.raw() else std.math.maxInt(u64);
    }
    return if (issued == 0) std.math.maxInt(u64) else issued;
}
pub fn exceeds(comptime wrapped: bool, maximum: u64, amount: u64) bool {
    if (wrapped) return a.bounded.Limit(u64).init(maximum).exceeds(amount);
    return amount > maximum;
}
/// A millisecond i64 widens into std's i96 nanoseconds: no error, no range check.
pub fn ioWiden(comptime wrapped: bool, value: i64, out: *i96) void {
    if (wrapped) {
        out.* = a.units.Duration(.millisecond, i64).fromRaw(value).toIoDuration().nanoseconds;
        return;
    }
    out.* = @as(i96, value) * 1_000_000;
}
/// std's i96 nanoseconds into a nanosecond i128 instant: no error, no range check.
pub fn ioTimestamp(comptime wrapped: bool, stamp: *const Io.Timestamp) i128 {
    if (wrapped) return a.units.Instant(.awake, .nanosecond, i128).fromTimestamp(stamp.*, .exact).raw();
    return stamp.nanoseconds;
}
/// The same into a nanosecond i64 instant narrows, so the one range check stays.
pub fn ioNarrow(comptime wrapped: bool, stamp: *const Io.Timestamp) error{Overflow}!i64 {
    if (wrapped) return (try a.units.Instant(.awake, .nanosecond, i64).fromTimestamp(stamp.*, .exact)).raw();
    const value = stamp.nanoseconds;
    if (value > std.math.maxInt(i64) or value < std.math.minInt(i64)) return error.Overflow;
    return @intCast(value); // safe: both bounds checked above
}

/// A contract path that ends control flow, against the hand-written panic it replaces.
pub fn never(comptime wrapped: bool, code: u8) u8 {
    return switch (code) {
        0 => 1,
        1 => 2,
        else => if (wrapped) a.assert.never("a code outside the table") else @panic("a code outside the table"),
    };
}
pub fn indexCompare(comptime wrapped: bool, x: u32, y: u32) i8 {
    if (wrapped) {
        const I = a.handle.Index(Tag, u32);
        const left: I = @fromBackingInt(x);
        const right: I = @fromBackingInt(y);
        return @backingInt(left.compare(right));
    }
    return @backingInt(std.math.order(x, y));
}
pub const Resource = struct { sink: *u64, value: u64 };
/// The cleanup both sides run: it reads the Io it is given, so the Io is really passed.
fn closeResource(resource: *Resource, io: Io) void {
    std.mem.doNotOptimizeAway(io.userdata);
    resource.sink.* +%= resource.value;
}
const HeldIo = a.own.OwnedIo(Resource, closeResource);
pub fn ownedIo(comptime wrapped: bool, io: *const Io, source: *Resource, fail: bool) void {
    if (wrapped) {
        var owner = HeldIo.init(source.*);
        defer owner.deinit(io.*);
        if (fail) return;
        owner.borrowMut().value +%= 1;
    } else {
        var resource = source.*;
        defer closeResource(&resource, io.*);
        if (fail) return;
        resource.value +%= 1;
    }
}
/// std's i96 nanoseconds into a nanosecond i96 duration and instant and back: no error, no range check.
pub fn wideRoundTrip(comptime wrapped: bool, stamp: *const Io.Timestamp, out: *Io.Timestamp) void {
    if (wrapped) {
        const instant = a.units.Instant(.awake, .nanosecond, i96).fromTimestamp(stamp.*, .exact);
        out.* = instant.toTimestamp();
        return;
    }
    out.* = .fromNanoseconds(stamp.nanoseconds);
}

/// A lock read is one acquire load of the flag, taken or not.
pub fn isHeld(comptime wrapped: bool, owner: *const Owner(wrapped)) bool {
    if (wrapped) return owner.isHeld();
    return owner.lock.load(.acquire);
}
pub fn saturatingAdd(comptime wrapped: bool, x: u64, y: u64) u64 {
    if (wrapped) return a.units.Duration(.nanosecond, u64).fromRaw(x).saturatingAdd(.fromRaw(y)).raw();
    return x +| y;
}
pub fn saturatingSub(comptime wrapped: bool, x: i64, y: i64) i64 {
    if (wrapped) return a.units.Instant(.real, .microsecond, i64).fromRaw(x).saturatingSub(.fromRaw(y)).raw();
    return x -| y;
}
/// A clock that stepped back: the span is zero, not an error.
pub fn saturatingSpan(comptime wrapped: bool, from: u64, to: u64) u64 {
    if (wrapped) {
        const Awake = a.units.Instant(.awake, .nanosecond, u64);
        return Awake.fromRaw(from).saturatingDurationTo(Awake.fromRaw(to)).raw();
    }
    return to -| from;
}
const Seq64 = a.id.Id(Tag, u64);
pub fn idSuccessor(comptime wrapped: bool, x: u64) error{IdExhausted}!u64 {
    if (wrapped) return (try Seq64.fromRaw(x).successor()).raw();
    const sum = @addWithOverflow(x, 1);
    if (sum[1] != 0) return error.IdExhausted;
    return sum[0];
}
pub fn idAdvance(comptime wrapped: bool, x: u64, n: u64) error{IdExhausted}!u64 {
    if (wrapped) return (try Seq64.fromRaw(x).advance(.fromRaw(n))).raw();
    const sum = @addWithOverflow(x, n);
    if (sum[1] != 0) return error.IdExhausted;
    return sum[0];
}
pub fn idRetreat(comptime wrapped: bool, x: u64, n: u64) error{IdUnderflow}!u64 {
    if (wrapped) return (try Seq64.fromRaw(x).retreat(.fromRaw(n))).raw();
    const below = @subWithOverflow(x, n);
    if (below[1] != 0) return error.IdUnderflow;
    return below[0];
}
pub fn idDistance(comptime wrapped: bool, x: u64, y: u64) error{Backwards}!u64 {
    if (wrapped) return (try Seq64.fromRaw(x).distanceTo(Seq64.fromRaw(y))).raw();
    if (y < x) return error.Backwards;
    return y - x;
}

/// A widening cast cannot fail, so it is the value and nothing else.
pub fn castWiden(comptime wrapped: bool, x: u32) u64 {
    if (wrapped) return a.int.cast(u64, x);
    return x;
}
/// Into usize from 32 bits cannot fail on any supported target.
pub fn castUsize(comptime wrapped: bool, x: u32) usize {
    if (wrapped) return a.int.cast(usize, x);
    return x;
}
pub fn countConvert(comptime wrapped: bool, x: u16) u32 {
    if (wrapped) return a.units.Count(Tag, u16).fromRaw(x).convert(u32).raw();
    return x;
}
/// Milliseconds of an i32 into nanoseconds of an i64 always fit: no range check.
pub fn durationWiden(comptime wrapped: bool, x: i32) i64 {
    if (wrapped) return a.units.Duration(.millisecond, i32).fromRaw(x).convert(.nanosecond, i64, .exact).raw();
    return @as(i64, x) * 1_000_000;
}
/// Whole days of a u64 nanosecond count always fit a u32: a division and a narrowing, no range check.
pub fn durationCoarse(comptime wrapped: bool, x: u64) u32 {
    if (wrapped) return a.units.Duration(.nanosecond, u64).fromRaw(x).convert(.day, u32, .down).raw();
    return @truncate(x / 86_400_000_000_000);
}

pub fn bufferCapacity(comptime wrapped: bool, owner: if (wrapped) *const a.bounded.Buffer(u64) else *const base.DirectBuffer) usize {
    if (wrapped) return owner.capacity();
    return owner.storage.len;
}
pub fn bufferFull(comptime wrapped: bool, owner: if (wrapped) *const a.bounded.Buffer(u64) else *const base.DirectBuffer) bool {
    if (wrapped) return owner.isFull();
    return owner.used == owner.storage.len;
}
/// An ordinary admission that keeps room for the control path; the reservation it grants is dropped unreleased,
/// as the hand-written count is.
pub fn budgetKeeping(comptime wrapped: bool, owner: if (wrapped) *a.bounded.Budget(u64) else *base.DirectBudget, amount: u64, kept: u64) bool {
    if (wrapped) {
        _ = owner.reserveKeeping(amount, kept) catch return false;
        return true;
    }
    const free = owner.maximum - owner.used;
    if (kept > free or amount > free - kept) return false;
    owner.used += amount;
    return true;
}
pub fn budgetCharged(comptime wrapped: bool, owner: if (wrapped) *const a.bounded.Budget(u64) else *const base.DirectBudget) u64 {
    if (wrapped) return owner.charged() +% owner.maximum();
    return owner.used +% owner.maximum;
}
pub fn orderedUncancelable(comptime wrapped: bool, io: *const Io, owner: if (wrapped) *base.Ordered else *base.DirectMutex) u64 {
    if (wrapped) {
        var task: base.Policy.Context = .{};
        var guard = owner.acquireOrderedUncancelable(io.*, &task);
        defer guard.deinit(io.*);
        guard.value().* +%= 1;
        return guard.value().*;
    }
    owner.mutex.lockUncancelable(io.*);
    defer owner.mutex.unlock(io.*);
    owner.data +%= 1;
    return owner.data;
}
pub fn waitUncancelable(comptime wrapped: bool, io: *const Io, changed: if (wrapped) *a.Condition else *base.DirectCondition, owner: if (wrapped) *a.BlockingGuarded(u64) else *base.DirectMutex, timeout: Io.Timeout) a.Condition.UncancelableWaitError!u64 {
    if (wrapped) {
        var guard = owner.acquireUncancelable(io.*);
        defer guard.deinit(io.*);
        try changed.waitUncancelable(io.*, &guard, timeout);
        return guard.value().*;
    }
    owner.mutex.lockUncancelable(io.*);
    defer owner.mutex.unlock(io.*);
    try directWaitUncancelable(io.*, changed, &owner.mutex, timeout);
    return owner.data;
}
/// The hand-written wait that cancellation cannot interrupt: the same blocked protection around the same kernel.
fn directWaitUncancelable(io: Io, changed: *base.DirectCondition, mutex: *Io.Mutex, timeout: Io.Timeout) a.Condition.UncancelableWaitError!void {
    const before = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(before);
    return changed.waitMutex(io, mutex, timeout) catch |err| switch (err) {
        error.Canceled => unreachable, // unreachable: cancellation is blocked for the wait
        error.Timeout => error.Timeout,
        error.WaiterLimit => error.WaiterLimit,
    };
}

pub const Hits = a.units.Count(Tag, u32);
pub fn AtomicCell(comptime wrapped: bool) type {
    return if (wrapped) a.Atomic(Hits) else std.atomic.Value(u32);
}
pub fn atomicLoad(comptime wrapped: bool, cell: *const AtomicCell(wrapped)) u32 {
    if (wrapped) return cell.load(.acquire).raw();
    return cell.load(.acquire);
}
pub fn atomicStore(comptime wrapped: bool, cell: *AtomicCell(wrapped), value: u32) void {
    if (wrapped) return cell.store(.fromRaw(value), .release);
    cell.store(value, .release);
}
pub fn atomicSwap(comptime wrapped: bool, cell: *AtomicCell(wrapped), value: u32) u32 {
    if (wrapped) return cell.swap(.fromRaw(value), .acq_rel).raw();
    return cell.swap(value, .acq_rel);
}
pub fn atomicCompareExchange(comptime wrapped: bool, cell: *AtomicCell(wrapped), expected: u32, value: u32) bool {
    if (wrapped) return cell.cmpxchgStrong(.fromRaw(expected), .fromRaw(value), .acq_rel, .acquire) == null;
    return cell.cmpxchgStrong(expected, value, .acq_rel, .acquire) == null;
}
pub fn atomicMax(comptime wrapped: bool, cell: *AtomicCell(wrapped), value: u32) u32 {
    if (wrapped) return cell.fetchMax(.fromRaw(value), .monotonic).raw();
    return cell.fetchMax(value, .monotonic);
}
pub fn atomicAddWrapping(comptime wrapped: bool, cell: *AtomicCell(wrapped), value: u32) u32 {
    if (wrapped) return cell.fetchAddWrapping(.fromRaw(value), .monotonic).raw();
    return cell.fetchAdd(value, .monotonic);
}
/// The checked add is a weak compare-and-swap loop in both, with the overflow answered before anything is written.
pub fn atomicAdd(comptime wrapped: bool, cell: *AtomicCell(wrapped), value: u32) error{ Overflow, Underflow }!u32 {
    if (wrapped) return (try cell.fetchAdd(.fromRaw(value), .acq_rel)).raw();
    var seen = cell.load(.monotonic);
    while (true) {
        const sum = @addWithOverflow(seen, value);
        if (sum[1] != 0) return error.Overflow;
        seen = cell.cmpxchgWeak(seen, sum[0], .acq_rel, .monotonic) orelse return seen;
    }
}
