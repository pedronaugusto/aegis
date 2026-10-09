//! Necessary handwritten operations paired with the public A6/A7 capabilities.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");
const Io = std.Io;
pub const DirectCondition = @import("DirectCondition.zig");
pub const DirectMutex = struct { mutex: Io.Mutex = .init, data: u64 };
pub const DirectRw = struct { lock: Io.RwLock = .init, admitted: std.atomic.Value(usize) = .init(0), limit: usize = 65535, data: u64 };
pub const DirectOnce = struct { state: std.atomic.Value(enum(u32) { empty, running, ready }) = .init(.empty), mutex: Io.Mutex = .init, changed: DirectCondition = .{}, data: u64 = undefined };
pub const DirectArray = struct { storage: [3]u64 = undefined, used: usize = 0 };
pub const DirectQueue = struct {
    storage: [3]u64 = undefined,
    head: usize = 0,
    used: usize = 0,
    fn index(self: *const DirectQueue, offset: usize) usize {
        const remaining = 3 - self.head;
        return if (offset < remaining) self.head + offset else offset - remaining;
    }
};
pub const DirectRingBuffer = struct {
    storage: []u64,
    gpa: ?std.mem.Allocator,
    maximum: usize,
    head: usize = 0,
    used: usize = 0,
    fn index(self: *const DirectRingBuffer, offset: usize) usize {
        const remaining = self.storage.len - self.head;
        return if (offset < remaining) self.head + offset else offset - remaining;
    }
};
pub const DirectBudget = struct { maximum: u64, used: u64 = 0 };
pub const DirectBuffer = struct { storage: []u64, gpa: ?std.mem.Allocator, maximum: usize, used: usize = 0 };
pub const checked = builtin.mode == .debug or builtin.mode == .safe;
pub const DirectConfined = struct { data: u64, owner: if (checked) a.TaskIdentity else void };
pub const Payload = struct { output: *u64, value: u64 };
pub fn cleanup(payload: *Payload) void {
    payload.output.* +%= payload.value;
}
pub const Owned = a.own.Owned(Payload, cleanup);
pub const MustUse = a.own.MustUse(u64, "inspect result");
pub const Policy = a.Order(&.{.{ .name = "root" }});
pub const Ordered = Policy.Ordered(a.BlockingGuarded(u64), 0);

pub fn mutex(comptime wrapped: bool, io: Io, owner: if (wrapped) *a.BlockingGuarded(u64) else *DirectMutex) Io.Cancelable!u64 {
    if (wrapped) {
        var guard = try owner.acquire(io);
        defer guard.deinit(io);
        guard.value().* +%= 1;
        return guard.value().*;
    }
    try owner.mutex.lock(io);
    defer owner.mutex.unlock(io);
    owner.data +%= 1;
    return owner.data;
}
fn admit(owner: *DirectRw) error{AdmissionLimit}!void {
    var old = owner.admitted.load(.monotonic);
    while (true) {
        if (old == owner.limit) return error.AdmissionLimit;
        old = owner.admitted.cmpxchgWeak(old, old + 1, .monotonic, .monotonic) orelse return;
    }
}
pub fn rw(comptime wrapped: bool, comptime write: bool, io: Io, owner: if (wrapped) *a.RwGuarded(u64) else *DirectRw) (Io.Cancelable || error{AdmissionLimit})!u64 {
    if (wrapped) {
        if (write) {
            var guard = try owner.write(io);
            defer guard.deinit(io);
            guard.value().* +%= 1;
            return guard.value().*;
        } else {
            var guard = try owner.read(io);
            defer guard.deinit(io);
            return guard.value().*;
        }
    }
    try admit(owner);
    errdefer _ = owner.admitted.fetchSub(1, .monotonic);
    if (write) try owner.lock.lock(io) else try owner.lock.lockShared(io);
    defer {
        if (write) owner.lock.unlock(io) else owner.lock.unlockShared(io);
        _ = owner.admitted.fetchSub(1, .monotonic);
    }
    if (write) owner.data +%= 1;
    return owner.data;
}
pub fn onceReady(comptime wrapped: bool, owner: if (wrapped) *a.Once(u64) else *DirectOnce) ?*const u64 {
    if (wrapped) return owner.get();
    return if (owner.state.load(.acquire) == .ready) &owner.data else null;
}
fn initialize(_: Io, seed: u64, destination: *u64) Io.Cancelable!void {
    destination.* = seed;
}
pub fn onceCold(comptime wrapped: bool, io: Io, owner: if (wrapped) *a.Once(u64) else *DirectOnce, seed: u64) (Io.Cancelable || error{WaiterLimit})!*const u64 {
    if (wrapped) {
        var task: a.InitContext = .{};
        return owner.getOrInit(io, &task, seed, initialize);
    }
    if (owner.state.load(.acquire) == .ready) return &owner.data;
    try owner.mutex.lock(io);
    while (true) {
        switch (owner.state.load(.acquire)) {
            .ready => {
                owner.mutex.unlock(io);
                return &owner.data;
            },
            .empty => break,
            .running => owner.changed.waitMutex(io, &owner.mutex, .none) catch |err| {
                owner.mutex.unlock(io);
                switch (err) {
                    error.Timeout => unreachable,
                    error.Canceled, error.WaiterLimit => |e| return e,
                }
            },
        }
    }
    owner.state.store(.running, .monotonic);
    owner.mutex.unlock(io);
    try initialize(io, seed, &owner.data);
    owner.mutex.lockUncancelable(io);
    owner.state.store(.ready, .release);
    owner.changed.broadcast(io);
    owner.mutex.unlock(io);
    return &owner.data;
}
pub fn condition(comptime wrapped: bool, io: Io, changed: if (wrapped) *a.Condition else *DirectCondition, owner: if (wrapped) *a.BlockingGuarded(u64) else *DirectMutex, timeout: Io.Timeout) a.Condition.WaitError!u64 {
    if (wrapped) {
        var guard = try owner.acquire(io);
        defer guard.deinit(io);
        try changed.wait(io, &guard, timeout);
        return guard.value().*;
    }
    try owner.mutex.lock(io);
    defer owner.mutex.unlock(io);
    try changed.waitMutex(io, &owner.mutex, timeout);
    return owner.data;
}
pub fn array(comptime wrapped: bool, owner: if (wrapped) *a.bounded.Array(u64, 3) else *DirectArray, input: u64) bool {
    if (wrapped) {
        var value = input;
        owner.append(&value) catch return false;
        return true;
    }
    if (owner.used == 3) return false;
    owner.storage[owner.used] = input;
    owner.used += 1;
    return true;
}
pub fn queue(comptime wrapped: bool, owner: if (wrapped) *a.bounded.Queue(u64, 3) else *DirectQueue, input: u64) bool {
    if (wrapped) {
        var value = input;
        owner.push(&value) catch return false;
        return true;
    }
    if (owner.used == 3) return false;
    owner.storage[owner.index(owner.used)] = input;
    owner.used += 1;
    return true;
}
pub fn buffer(comptime wrapped: bool, owner: if (wrapped) *a.bounded.Buffer(u64) else *DirectBuffer, input: u64) bool {
    if (wrapped) {
        var value = input;
        owner.append(&value) catch return false;
        return true;
    }
    if (owner.used == owner.storage.len) return false;
    owner.storage[owner.used] = input;
    owner.used += 1;
    return true;
}
pub fn budget(comptime wrapped: bool, owner: if (wrapped) *a.bounded.Budget(u64) else *DirectBudget, amount: u64, release: u64) bool {
    if (wrapped) {
        owner.consume(amount) catch return false;
        var reservation: a.bounded.Budget(u64).Reservation = .{ .budget = owner, .amount = release };
        reservation.release();
        return true;
    }
    if (amount > owner.maximum - owner.used) return false;
    owner.used += amount;
    if (release > owner.used) @panic("budget reservation underflow");
    owner.used -= release;
    return true;
}
pub fn owned(comptime wrapped: bool, owner: if (wrapped) *Owned else *Payload, fail: bool) void {
    if (wrapped) {
        defer owner.deinit();
        if (fail) return;
        owner.borrowMut().value +%= 1;
    } else {
        defer cleanup(owner);
        if (fail) return;
        owner.value +%= 1;
    }
}
pub fn mustUse(comptime wrapped: bool, owner: if (wrapped) *MustUse else *u64, destination: *u64) void {
    if (wrapped) {
        owner.take(destination);
        owner.deinit();
    } else destination.* = owner.*;
}
pub fn confined(comptime wrapped: bool, owner: if (wrapped) *a.Confined(u64) else *DirectConfined, identity: a.TaskIdentity) u64 {
    if (wrapped) {
        owner.value(identity).* +%= 1;
        return owner.valueConst(identity).*;
    }
    if (checked and owner.owner != identity) @panic("Confined accessed by another logical task");
    owner.data +%= 1;
    return owner.data;
}
pub fn ordered(comptime wrapped: bool, io: Io, owner: if (wrapped) *Ordered else *DirectMutex) Io.Cancelable!u64 {
    if (wrapped) {
        var task: Policy.Context = .{};
        var guard = try owner.acquireOrdered(io, &task);
        defer guard.deinit(io);
        guard.value().* +%= 1;
        return guard.value().*;
    }
    return mutex(false, io, owner);
}

pub fn ringBuffer(comptime wrapped: bool, owner: if (wrapped) *a.bounded.RingBuffer(u64) else *DirectRingBuffer, input: u64) bool {
    if (wrapped) {
        var value = input;
        owner.push(&value) catch return false;
        return true;
    }
    if (owner.used == owner.storage.len) return false;
    owner.storage[owner.index(owner.used)] = input;
    owner.used += 1;
    return true;
}
pub fn limit(comptime wrapped: bool, maximum: u64, amount: u64) bool {
    if (wrapped) {
        a.bounded.Limit(u64).init(maximum).check(amount) catch return false;
        return true;
    }
    return amount <= maximum;
}
