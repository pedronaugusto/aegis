const std = @import("std");
const a = @import("aegis");
const c = @import("a67.zig");
export fn baselineA67Mutex(io: *const std.Io, owner: *c.DirectMutex) u64 {
    return c.mutex(false, io.*, owner) catch |err| @intFromError(err);
}
export fn wrapperA67Mutex(io: *const std.Io, owner: *a.BlockingGuarded(u64)) u64 {
    return c.mutex(true, io.*, owner) catch |err| @intFromError(err);
}
export fn baselineA67RwRead(io: *const std.Io, owner: *c.DirectRw) u64 {
    return c.rw(false, false, io.*, owner) catch |err| @intFromError(err);
}
export fn wrapperA67RwRead(io: *const std.Io, owner: *a.RwGuarded(u64)) u64 {
    return c.rw(true, false, io.*, owner) catch |err| @intFromError(err);
}
export fn baselineA67RwWrite(io: *const std.Io, owner: *c.DirectRw) u64 {
    return c.rw(false, true, io.*, owner) catch |err| @intFromError(err);
}
export fn wrapperA67RwWrite(io: *const std.Io, owner: *a.RwGuarded(u64)) u64 {
    return c.rw(true, true, io.*, owner) catch |err| @intFromError(err);
}
export fn baselineA67OnceReady(owner: *c.DirectOnce) ?*const u64 {
    return c.onceReady(false, owner);
}
export fn wrapperA67OnceReady(owner: *a.Once(u64)) ?*const u64 {
    return c.onceReady(true, owner);
}
export fn baselineA67OnceCold(io: *const std.Io, owner: *c.DirectOnce, seed: u64) ?*const u64 {
    return c.onceCold(false, io.*, owner, seed) catch null;
}
export fn wrapperA67OnceCold(io: *const std.Io, owner: *a.Once(u64), seed: u64) ?*const u64 {
    return c.onceCold(true, io.*, owner, seed) catch null;
}
export fn baselineA67Condition(io: *const std.Io, changed: *c.DirectCondition, owner: *c.DirectMutex, timeout: *const std.Io.Timeout) u64 {
    return c.condition(false, io.*, changed, owner, timeout.*) catch |err| @intFromError(err);
}
export fn wrapperA67Condition(io: *const std.Io, changed: *a.Condition, owner: *a.BlockingGuarded(u64), timeout: *const std.Io.Timeout) u64 {
    return c.condition(true, io.*, changed, owner, timeout.*) catch |err| @intFromError(err);
}
export fn baselineA67Array(owner: *c.DirectArray, input: u64) bool {
    return c.array(false, owner, input);
}
export fn wrapperA67Array(owner: *a.bounded.Array(u64, 3), input: u64) bool {
    return c.array(true, owner, input);
}
export fn baselineA67Queue(owner: *c.DirectQueue, input: u64) bool {
    return c.queue(false, owner, input);
}
export fn wrapperA67Queue(owner: *a.bounded.Queue(u64, 3), input: u64) bool {
    return c.queue(true, owner, input);
}
export fn baselineA67Buffer(owner: *c.DirectBuffer, input: u64) bool {
    return c.buffer(false, owner, input);
}
export fn wrapperA67Buffer(owner: *a.bounded.Buffer(u64), input: u64) bool {
    return c.buffer(true, owner, input);
}
export fn baselineA67Budget(owner: *c.DirectBudget, amount: u64, release: u64) bool {
    return c.budget(false, owner, amount, release);
}
export fn wrapperA67Budget(owner: *a.bounded.Budget(u64), amount: u64, release: u64) bool {
    return c.budget(true, owner, amount, release);
}
export fn baselineA67Owned(owner: *c.Payload, fail: bool) void {
    return c.owned(false, owner, fail);
}
export fn wrapperA67Owned(owner: *c.Owned, fail: bool) void {
    return c.owned(true, owner, fail);
}
export fn baselineA67MustUse(owner: *u64, destination: *u64) void {
    return c.mustUse(false, owner, destination);
}
export fn wrapperA67MustUse(owner: *c.MustUse, destination: *u64) void {
    return c.mustUse(true, owner, destination);
}
export fn baselineA67Confined(owner: *c.DirectConfined, identity: a.TaskIdentity) u64 {
    return c.confined(false, owner, identity);
}
export fn wrapperA67Confined(owner: *a.Confined(u64), identity: a.TaskIdentity) u64 {
    return c.confined(true, owner, identity);
}
export fn baselineA67Ordered(io: *const std.Io, owner: *c.DirectMutex) u64 {
    return c.ordered(false, io.*, owner) catch |err| @intFromError(err);
}
export fn wrapperA67Ordered(io: *const std.Io, owner: *c.Ordered) u64 {
    return c.ordered(true, io.*, owner) catch |err| @intFromError(err);
}
comptime {
    std.debug.assert(@sizeOf(c.DirectMutex) == @sizeOf(a.BlockingGuarded(u64)));
    std.debug.assert(@alignOf(c.DirectMutex) == @alignOf(a.BlockingGuarded(u64)));
    std.debug.assert(@sizeOf(c.DirectRw) == @sizeOf(a.RwGuarded(u64)));
    std.debug.assert(@alignOf(c.DirectRw) == @alignOf(a.RwGuarded(u64)));
    std.debug.assert(@sizeOf(c.DirectRw) == @sizeOf(a.RwGuarded(u64)));
    std.debug.assert(@alignOf(c.DirectRw) == @alignOf(a.RwGuarded(u64)));
    std.debug.assert(@sizeOf(c.DirectOnce) == @sizeOf(a.Once(u64)));
    std.debug.assert(@alignOf(c.DirectOnce) == @alignOf(a.Once(u64)));
    std.debug.assert(@sizeOf(c.DirectOnce) == @sizeOf(a.Once(u64)));
    std.debug.assert(@alignOf(c.DirectOnce) == @alignOf(a.Once(u64)));
    std.debug.assert(@sizeOf(c.DirectMutex) == @sizeOf(a.BlockingGuarded(u64)));
    std.debug.assert(@alignOf(c.DirectMutex) == @alignOf(a.BlockingGuarded(u64)));
    std.debug.assert(@sizeOf(c.DirectArray) == @sizeOf(a.bounded.Array(u64, 3)));
    std.debug.assert(@alignOf(c.DirectArray) == @alignOf(a.bounded.Array(u64, 3)));
    std.debug.assert(@sizeOf(c.DirectQueue) == @sizeOf(a.bounded.Queue(u64, 3)));
    std.debug.assert(@alignOf(c.DirectQueue) == @alignOf(a.bounded.Queue(u64, 3)));
    std.debug.assert(@sizeOf(c.DirectBuffer) == @sizeOf(a.bounded.Buffer(u64)));
    std.debug.assert(@alignOf(c.DirectBuffer) == @alignOf(a.bounded.Buffer(u64)));
    std.debug.assert(@sizeOf(c.DirectBudget) == @sizeOf(a.bounded.Budget(u64)));
    std.debug.assert(@alignOf(c.DirectBudget) == @alignOf(a.bounded.Budget(u64)));
    std.debug.assert(@sizeOf(c.Payload) == @sizeOf(c.Owned));
    std.debug.assert(@alignOf(c.Payload) == @alignOf(c.Owned));
    std.debug.assert(@sizeOf(u64) == @sizeOf(c.MustUse));
    std.debug.assert(@alignOf(u64) == @alignOf(c.MustUse));
    std.debug.assert(@sizeOf(c.DirectConfined) == @sizeOf(a.Confined(u64)));
    std.debug.assert(@alignOf(c.DirectConfined) == @alignOf(a.Confined(u64)));
    std.debug.assert(@sizeOf(c.DirectMutex) == @sizeOf(c.Ordered));
    std.debug.assert(@alignOf(c.DirectMutex) == @alignOf(c.Ordered));
    std.debug.assert(@sizeOf(a.BlockingGuarded(u64).Guard) == @sizeOf(*u64));
    std.debug.assert(@sizeOf(a.RwGuarded(u64).ReadGuard) == @sizeOf(*u64));
    std.debug.assert(@sizeOf(a.RwGuarded(u64).WriteGuard) == @sizeOf(*u64));
}

export fn baselineA67RingBuffer(owner: *c.DirectRingBuffer, input: u64) bool {
    return c.ringBuffer(false, owner, input);
}
export fn wrapperA67RingBuffer(owner: *a.bounded.RingBuffer(u64), input: u64) bool {
    return c.ringBuffer(true, owner, input);
}
export fn baselineA67Limit(maximum: u64, amount: u64) bool {
    return c.limit(false, maximum, amount);
}
export fn wrapperA67Limit(maximum: u64, amount: u64) bool {
    return c.limit(true, maximum, amount);
}
comptime {
    std.debug.assert(@sizeOf(c.DirectRingBuffer) == @sizeOf(a.bounded.RingBuffer(u64)));
    std.debug.assert(@alignOf(c.DirectRingBuffer) == @alignOf(a.bounded.RingBuffer(u64)));
}
