//! Necessary handwritten operations paired with the adoption-gap capabilities.
const std = @import("std");
const a = @import("aegis");
const Io = std.Io;

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
