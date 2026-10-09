//! Handwritten bounded waiter registry: independent necessary-operation cost floor.
const Condition = @This();
const std = @import("std");
const Io = std.Io;

/// Private: protects the stack waiter registry, association and count.
mutex: Io.Mutex = .init,
/// Private: association is stable from the first wait until teardown.
associated: ?*Io.Mutex = null,
/// Private: live stack waiters; every removal finishes before wait returns.
first: ?*Waiter = null,
/// Private: all-build finite waiter admission.
count: usize = 0,
/// Private: selected cap, no zero-as-unlimited convention.
limit: usize = 65535,
const Waiter = struct { next: ?*Waiter, notified: std.atomic.Value(u32) = .init(0) };
pub const WaitError = Io.Cancelable || Io.Timeout.Error || error{WaiterLimit};

/// Internal kernel seam. Caller holds this mutex; no value borrow survives the call.
/// Association misuse fails in every mode, before releasing the caller's lock.
pub fn waitMutex(self: *Condition, io: Io, owner_mutex: *Io.Mutex, timeout: Io.Timeout) WaitError!void {
    const deadline = timeout.toDeadline(io);
    self.mutex.lockUncancelable(io);
    if (self.associated) |associated| {
        if (associated != owner_mutex) @panic("condition used with a different owner");
    } else self.associated = owner_mutex;
    if (self.count == self.limit) {
        self.mutex.unlock(io);
        return error.WaiterLimit;
    }
    var waiter: Waiter = .{ .next = self.first };
    self.first = &waiter;
    self.count += 1;
    owner_mutex.unlock(io);
    self.mutex.unlock(io);
    // Deregistration and reacquisition are explicit parts of this blocking call.
    // The registry lock keeps signal/broadcast from referencing a departed stack frame.
    var canceled = false;
    defer {
        self.mutex.lockUncancelable(io);
        var link = &self.first;
        while (link.* != &waiter) link = &link.*.?.next;
        link.* = waiter.next;
        self.count -= 1;
        if (canceled and waiter.notified.load(.acquire) != 0) self.notifyOne(io);
        self.mutex.unlock(io);
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
    var item = self.first;
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
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);
    self.notifyOne(io);
}
pub fn broadcast(self: *Condition, io: Io) void {
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);
    var item = self.first;
    while (item) |waiter| : (item = waiter.next) {
        if (waiter.notified.load(.monotonic) == 0) {
            waiter.notified.store(1, .release);
            io.futexWake(u32, &waiter.notified.raw, 1);
        }
    }
}
