//! Bounded intrusive waiters: no epoch wrap, lost signal or stack waiter escape.
const Condition = @This();
const std = @import("std");
const Io = std.Io;

/// Private: protects the stack waiter registry, association and count.
aegis_mutex: Io.Mutex = .init,
/// Private: association is stable from the first wait until teardown.
aegis_associated: ?*Io.Mutex = null,
/// Private: live stack waiters; every removal finishes before wait returns.
aegis_first: ?*Waiter = null,
/// Private: all-build finite waiter admission.
aegis_count: usize = 0,
/// Private: selected cap, no zero-as-unlimited convention.
aegis_limit: usize = 65535,
const Waiter = struct { next: ?*Waiter, notified: std.atomic.Value(u32) = .init(0) };
pub const WaitError = Io.Cancelable || Io.Timeout.Error || error{WaiterLimit};
/// What a wait that cancellation cannot interrupt can still end with.
pub const UncancelableWaitError = Io.Timeout.Error || error{WaiterLimit};

pub fn init() Condition {
    return .{};
}
pub fn initLimit(limit: usize) Condition {
    return .{ .aegis_limit = limit };
}

/// The kernel a blocking guard's `waitUncancelable` runs: `waitMutex` with cancellation blocked for the
/// wait, so it returns only on a wake, the timeout or the waiter limit, the mutex held again as `waitMutex`
/// leaves it. With no timeout it waits as long as the predicate needs; the signaling side must be sure to come.
pub fn waitMutexUncancelable(self: *Condition, io: Io, owner_mutex: *Io.Mutex, timeout: Io.Timeout) UncancelableWaitError!void {
    const before = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(before);
    return self.waitMutex(io, owner_mutex, timeout) catch |err| switch (err) {
        error.Canceled => unreachable, // unreachable: cancellation is blocked for the wait
        error.Timeout => error.Timeout,
        error.WaiterLimit => error.WaiterLimit,
    };
}

/// The kernel a blocking guard's `wait` runs. Caller holds this mutex; no value borrow survives the call.
/// Association misuse fails in every mode, before releasing the caller's lock.
pub fn waitMutex(self: *Condition, io: Io, owner_mutex: *Io.Mutex, timeout: Io.Timeout) WaitError!void {
    const deadline = timeout.toDeadline(io);
    self.aegis_mutex.lockUncancelable(io);
    if (self.aegis_associated) |associated| {
        if (associated != owner_mutex) @panic("condition used with a different owner");
    } else self.aegis_associated = owner_mutex;
    if (self.aegis_count == self.aegis_limit) {
        self.aegis_mutex.unlock(io);
        return error.WaiterLimit;
    }
    var waiter: Waiter = .{ .next = self.aegis_first };
    self.aegis_first = &waiter;
    self.aegis_count += 1;
    owner_mutex.unlock(io);
    self.aegis_mutex.unlock(io);
    // Deregistration and reacquisition are explicit parts of this blocking call.
    // The registry lock keeps signal/broadcast from referencing a departed stack frame.
    var canceled = false;
    defer {
        self.aegis_mutex.lockUncancelable(io);
        var link = &self.aegis_first;
        while (link.* != &waiter) link = &link.*.?.next;
        link.* = waiter.next;
        self.aegis_count -= 1;
        if (canceled and waiter.notified.load(.acquire) != 0) self.notifyOne(io);
        self.aegis_mutex.unlock(io);
        owner_mutex.lockUncancelable(io);
    }
    while (true) {
        // A pending cancellation wins over a signal even before the first park.
        io.checkCancel() catch {
            canceled = true;
            return error.Canceled;
        };
        io.futexWaitTimeout(u32, &waiter.notified.raw, 0, deadline) catch {
            canceled = true;
            return error.Canceled;
        };
        // Some host Io backends return normally when signal races cancellation.
        // Accept the wake only after checking pending cancellation; forwarding in
        // deregistration preserves the signal for an eligible surviving waiter.
        io.checkCancel() catch {
            canceled = true;
            return error.Canceled;
        };
        if (waiter.notified.load(.acquire) != 0) return;
        switch (deadline) {
            .none => {},
            .deadline => |d| if (d.untilNow(io).raw.nanoseconds >= 0) return error.Timeout,
            .duration => unreachable,
        }
        // Spurious wakes keep the original absolute deadline.
    }
}
fn notifyOne(self: *Condition, io: Io) void {
    var item = self.aegis_first;
    while (item) |waiter| : (item = waiter.next) {
        if (waiter.notified.load(.monotonic) == 0) {
            waiter.notified.store(1, .release);
            io.futexWake(u32, &waiter.notified.raw, 1);
            return;
        }
    }
}
/// Caller should publish its predicate under the associated data lock.
/// No FIFO/fairness guarantee; registration order is LIFO.
pub fn signal(self: *Condition, io: Io) void {
    self.aegis_mutex.lockUncancelable(io);
    defer self.aegis_mutex.unlock(io);
    self.notifyOne(io);
}
pub fn broadcast(self: *Condition, io: Io) void {
    self.aegis_mutex.lockUncancelable(io);
    defer self.aegis_mutex.unlock(io);
    var item = self.aegis_first;
    while (item) |waiter| : (item = waiter.next) {
        if (waiter.notified.load(.monotonic) == 0) {
            waiter.notified.store(1, .release);
            io.futexWake(u32, &waiter.notified.raw, 1);
        }
    }
}
