//! A one-shot signal across tasks: set once by any side, waited on by any task, carrying the value it was set with.
const std = @import("std");
const Io = std.Io;
const Atomic = @import("Atomic.zig").Atomic;

/// A signal one side sets, once, and any task waits for: a completion, a shutdown, a peer's answer. `T` is the
/// value the setter hands every waiter (`void` for a bare signal). Unlike `Once`, nobody initializes anything on
/// demand: the value comes from whichever side sets it.
///
/// `set` writes the value, then publishes it with release ordering and wakes every waiter, so a waiter never sees a
/// half-written value. A second `set` is refused with `error.AlreadySet` and changes nothing: two sides racing to
/// set it is a fact the loser learns, never a value silently overwritten. There is no reset. A new round is a new
/// Signal, as resetting a signal while a waiter is still on it is the race `std.Io.Event` leaves to its caller.
///
/// Ownership: the Signal belongs to whoever made it, which keeps it in place (never moved or copied once another
/// task can reach it) and alive until every waiter has returned and every pointer `wait` or `get` returned is
/// dropped. The pointer lives as long as the Signal; the value it points to never changes after `set`.
pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();
        // Open, so reading the word back is no tag check: only these three are ever stored.
        const State = enum(u32) { unset, setting, set, _ };

        /// Private: unset; claimed by the one setter while it writes the value; or set, published with release.
        state: Atomic(State) = .init(.unset),
        /// Private: written once, by the setter that claimed the state, before the state is set.
        value: T = undefined,

        pub const SetError = error{AlreadySet};
        pub const WaitTimeoutError = error{Timeout} || Io.Cancelable;

        pub fn init() Self {
            return .{};
        }

        /// Sets the signal to `value` and wakes every waiter; `error.AlreadySet` if any side set it first, the
        /// value it set kept.
        pub fn set(self: *Self, io: Io, value: T) SetError!void {
            if (self.state.cmpxchgStrong(.unset, .setting, .monotonic, .monotonic) != null) return error.AlreadySet;
            self.value = value;
            self.state.store(.set, .release);
            // Once per Signal: whoever waits on `unset` or `setting` is woken, whenever it began to wait.
            self.state.wake(io, std.math.maxInt(u32));
        }

        /// The value the signal was set with, or null while it is not set. Never waits.
        pub fn get(self: *const Self) ?*const T {
            return if (self.state.load(.acquire) == .set) &self.value else null;
        }

        /// Waits until the signal is set and returns its value; a cancellation point, as `std.Io.Event.wait`.
        pub fn wait(self: *const Self, io: Io) Io.Cancelable!*const T {
            while (true) {
                const seen = self.state.load(.acquire);
                if (seen == .set) return &self.value;
                try self.state.wait(io, seen);
            }
        }

        /// As `wait`, never canceled.
        pub fn waitUncancelable(self: *const Self, io: Io) *const T {
            while (true) {
                const seen = self.state.load(.acquire);
                if (seen == .set) return &self.value;
                self.state.waitUncancelable(io, seen);
            }
        }

        /// As `wait`, giving up with `error.Timeout` once `timeout` has passed; a spurious wakeup before that waits
        /// again.
        pub fn waitTimeout(self: *const Self, io: Io, timeout: Io.Timeout) WaitTimeoutError!*const T {
            const deadline = timeout.toDeadline(io);
            while (true) {
                const seen = self.state.load(.acquire);
                if (seen == .set) return &self.value;
                if (deadline.toDurationFromNow(io)) |left| if (left.raw.nanoseconds <= 0) return error.Timeout;
                try self.state.waitTimeout(io, seen, deadline);
            }
        }
    };
}

const t = std.testing;

test "a signal set once hands its value to every waiter; a second set is refused and changes nothing" {
    var signal: Signal(u64) = .init();
    try t.expect(signal.get() == null);
    try signal.set(t.io, 42);
    try t.expectError(error.AlreadySet, signal.set(t.io, 7));
    try t.expectEqual(@as(u64, 42), signal.get().?.*);
    try t.expectEqual(@as(u64, 42), (try signal.wait(t.io)).*);
    try t.expectEqual(@as(u64, 42), signal.waitUncancelable(t.io).*);
    try t.expectEqual(@as(u64, 42), (try signal.waitTimeout(t.io, .none)).*);
}

test "a bare signal waits for its set; an unset one times out" {
    var bare: Signal(void) = .init();
    try t.expectError(error.Timeout, bare.waitTimeout(t.io, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } }));
    try bare.set(t.io, {});
    _ = try bare.wait(t.io);
}
