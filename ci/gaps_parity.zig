const std = @import("std");
const a = @import("aegis");
const c = @import("gaps.zig");
export fn baselineGapsTryAcquire(owner: *c.Owner(false)) bool {
    return c.tryAcquire(false, owner);
}
export fn wrapperGapsTryAcquire(owner: *c.Owner(true)) bool {
    return c.tryAcquire(true, owner);
}
export fn baselineGapsTeardown(owner: *c.Owner(false)) usize {
    return c.teardown(false, owner);
}
export fn wrapperGapsTeardown(owner: *c.Owner(true)) usize {
    return c.teardown(true, owner);
}
export fn baselineGapsLazyReady(owner: *c.DirectLazy) ?*const u64 {
    return c.lazyReady(false, owner);
}
export fn wrapperGapsLazyReady(owner: *a.Lazy(u64)) ?*const u64 {
    return c.lazyReady(true, owner);
}
export fn baselineGapsLazyCold(io: *const std.Io, owner: *c.DirectLazy, seed: u64) ?*const u64 {
    return c.lazyCold(false, io.*, owner, seed) catch null;
}
export fn wrapperGapsLazyCold(io: *const std.Io, owner: *a.Lazy(u64), seed: u64) ?*const u64 {
    return c.lazyCold(true, io.*, owner, seed) catch null;
}
export fn baselineGapsLazyInfallible(io: *const std.Io, owner: *c.DirectLazy, seed: u64) *const u64 {
    return c.lazyInfallible(false, io.*, owner, seed);
}
export fn wrapperGapsLazyInfallible(io: *const std.Io, owner: *a.Lazy(u64), seed: u64) *const u64 {
    return c.lazyInfallible(true, io.*, owner, seed);
}
export fn baselineGapsSharedRetain(owner: *const c.DirectHandle) *c.DirectBlock {
    return c.sharedRetain(false, owner).block;
}
export fn wrapperGapsSharedRetain(owner: *const c.Handle) *anyopaque {
    return c.sharedRetain(true, owner).block;
}
export fn baselineGapsSharedGet(owner: *const c.DirectHandle) *const u64 {
    return c.sharedGet(false, owner);
}
export fn wrapperGapsSharedGet(owner: *const c.Handle) *const u64 {
    return c.sharedGet(true, owner);
}
export fn baselineGapsSharedRelease(owner: *c.DirectHandle) void {
    c.sharedRelease(false, owner);
}
export fn wrapperGapsSharedRelease(owner: *c.Handle) void {
    c.sharedRelease(true, owner);
}
export fn baselineGapsOwnedFrom(source: *c.Payload, fail: bool) void {
    c.ownedFrom(false, source, fail);
}
export fn wrapperGapsOwnedFrom(source: *c.Payload, fail: bool) void {
    c.ownedFrom(true, source, fail);
}
export fn baselineGapsCompare(x: u64, y: u64) i8 {
    return c.compare(false, x, y);
}
export fn wrapperGapsCompare(x: u64, y: u64) i8 {
    return c.compare(true, x, y);
}
export fn baselineGapsEqual(x: u64, y: u64) bool {
    return c.equal(false, x, y);
}
export fn wrapperGapsEqual(x: u64, y: u64) bool {
    return c.equal(true, x, y);
}
export fn baselineGapsLast(issued: u64) u64 {
    return c.last(false, issued);
}
export fn wrapperGapsLast(issued: u64) u64 {
    return c.last(true, issued);
}
export fn baselineGapsExceeds(maximum: u64, amount: u64) bool {
    return c.exceeds(false, maximum, amount);
}
export fn wrapperGapsExceeds(maximum: u64, amount: u64) bool {
    return c.exceeds(true, maximum, amount);
}
export fn baselineGapsIoWiden(value: i64, out: *i96) void {
    c.ioWiden(false, value, out);
}
export fn wrapperGapsIoWiden(value: i64, out: *i96) void {
    c.ioWiden(true, value, out);
}
export fn baselineGapsIoTimestamp(stamp: *const std.Io.Timestamp) i128 {
    return c.ioTimestamp(false, stamp);
}
export fn wrapperGapsIoTimestamp(stamp: *const std.Io.Timestamp) i128 {
    return c.ioTimestamp(true, stamp);
}
export fn baselineGapsIoNarrow(stamp: *const std.Io.Timestamp) i64 {
    return c.ioNarrow(false, stamp) catch std.math.minInt(i64);
}
export fn wrapperGapsIoNarrow(stamp: *const std.Io.Timestamp) i64 {
    return c.ioNarrow(true, stamp) catch std.math.minInt(i64);
}
export fn baselineGapsNever(code: u8) u8 {
    return c.never(false, code);
}
export fn wrapperGapsNever(code: u8) u8 {
    return c.never(true, code);
}
export fn baselineGapsIndexCompare(x: u32, y: u32) i8 {
    return c.indexCompare(false, x, y);
}
export fn wrapperGapsIndexCompare(x: u32, y: u32) i8 {
    return c.indexCompare(true, x, y);
}
export fn baselineGapsOwnedIo(io: *const std.Io, source: *c.Resource, fail: bool) void {
    c.ownedIo(false, io, source, fail);
}
export fn wrapperGapsOwnedIo(io: *const std.Io, source: *c.Resource, fail: bool) void {
    c.ownedIo(true, io, source, fail);
}
export fn baselineGapsWideRoundTrip(stamp: *const std.Io.Timestamp, out: *std.Io.Timestamp) void {
    c.wideRoundTrip(false, stamp, out);
}
export fn wrapperGapsWideRoundTrip(stamp: *const std.Io.Timestamp, out: *std.Io.Timestamp) void {
    c.wideRoundTrip(true, stamp, out);
}
export fn baselineGapsIsHeld(owner: *const c.Owner(false)) bool {
    return c.isHeld(false, owner);
}
export fn wrapperGapsIsHeld(owner: *const c.Owner(true)) bool {
    return c.isHeld(true, owner);
}
export fn baselineGapsSaturatingAdd(x: u64, y: u64) u64 {
    return c.saturatingAdd(false, x, y);
}
export fn wrapperGapsSaturatingAdd(x: u64, y: u64) u64 {
    return c.saturatingAdd(true, x, y);
}
export fn baselineGapsSaturatingSub(x: i64, y: i64) i64 {
    return c.saturatingSub(false, x, y);
}
export fn wrapperGapsSaturatingSub(x: i64, y: i64) i64 {
    return c.saturatingSub(true, x, y);
}
export fn baselineGapsSaturatingSpan(from: u64, to: u64) u64 {
    return c.saturatingSpan(false, from, to);
}
export fn wrapperGapsSaturatingSpan(from: u64, to: u64) u64 {
    return c.saturatingSpan(true, from, to);
}
export fn baselineGapsIdSuccessor(x: u64) u64 {
    return c.idSuccessor(false, x) catch std.math.maxInt(u64);
}
export fn wrapperGapsIdSuccessor(x: u64) u64 {
    return c.idSuccessor(true, x) catch std.math.maxInt(u64);
}
export fn baselineGapsIdAdvance(x: u64, n: u64) u64 {
    return c.idAdvance(false, x, n) catch std.math.maxInt(u64);
}
export fn wrapperGapsIdAdvance(x: u64, n: u64) u64 {
    return c.idAdvance(true, x, n) catch std.math.maxInt(u64);
}
export fn baselineGapsIdRetreat(x: u64, n: u64) u64 {
    return c.idRetreat(false, x, n) catch std.math.maxInt(u64);
}
export fn wrapperGapsIdRetreat(x: u64, n: u64) u64 {
    return c.idRetreat(true, x, n) catch std.math.maxInt(u64);
}
export fn baselineGapsIdDistance(x: u64, y: u64) u64 {
    return c.idDistance(false, x, y) catch std.math.maxInt(u64);
}
export fn wrapperGapsIdDistance(x: u64, y: u64) u64 {
    return c.idDistance(true, x, y) catch std.math.maxInt(u64);
}
comptime {
    std.debug.assert(@sizeOf(c.DirectSpin) == @sizeOf(c.Owner(true)));
    std.debug.assert(@sizeOf(c.DirectLazy) == @sizeOf(a.Lazy(u64)));
    std.debug.assert(@alignOf(c.DirectLazy) == @alignOf(a.Lazy(u64)));
    std.debug.assert(@sizeOf(c.Handle) == @sizeOf(c.DirectHandle));
    std.debug.assert(@sizeOf(c.DirectBlock) == @sizeOf(@typeInfo(@FieldType(c.Handle, "block")).pointer.child));
}
