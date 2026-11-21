//! A one-shot signal across tasks: set once by any side, waited on by any task, carrying the value it was set with.
const std = @import("std");
const Io = std.Io;
const Atomic = @import("Atomic.zig").Atomic;

/// A signal one side sets, once, and any task waits for: a completion, a shutdown, a peer's answer. `T` is the
/// value the setter hands every waiter (`void` for a bare signal). Unlike `Once`, nobody initializes anything on
/// demand: the value comes from whichever side sets it.
///
/// `set` writes the value, then publishes it with release ordering and wakes every waiter, so a waiter never sees a
/// half-written value. `set` answers whether this call set it: a second `set` returns false and changes nothing, the
/// first value kept, never silently overwritten. For a single owner a second set is a contract break, so it writes
/// `aegis.assert.invariant(signal.set(io, v), ...)`; for sides racing to set it, losing is the normal answer, and
/// they branch on the bool. Neither is a failure to recover from, so there is no error. There is no reset. A new round is a new
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
        aegis_state: Atomic(State) = .init(.unset),
        /// Private: written once, by the setter that claimed the state, before the state is set.
        aegis_value: T = undefined,

        pub const WaitTimeoutError = error{Timeout} || Io.Cancelable;

        pub fn init() Self {
            return .{};
        }

        /// Sets the signal to `value` and wakes every waiter, and returns true; returns false when any side set it
        /// first, the value it set kept and nobody woken again.
        pub fn set(self: *Self, io: Io, value: T) bool {
            if (self.aegis_state.cmpxchgStrong(.unset, .setting, .monotonic, .monotonic) != null) return false;
            self.aegis_value = value;
            self.aegis_state.store(.set, .release);
            // Once per Signal: whoever waits on `unset` or `setting` is woken, whenever it began to wait.
            self.aegis_state.wake(io, std.math.maxInt(u32));
            return true;
        }

        /// The value the signal was set with, or null while it is not set. Never waits.
        pub fn get(self: *const Self) ?*const T {
            return if (self.aegis_state.load(.acquire) == .set) &self.aegis_value else null;
        }

        /// Waits until the signal is set and returns its value; a cancellation point, as `std.Io.Event.wait`.
        pub fn wait(self: *const Self, io: Io) Io.Cancelable!*const T {
            while (true) {
                const seen = self.aegis_state.load(.acquire);
                if (seen == .set) return &self.aegis_value;
                try self.aegis_state.wait(io, seen);
            }
        }

        /// As `wait`, never canceled.
        pub fn waitUncancelable(self: *const Self, io: Io) *const T {
            while (true) {
                const seen = self.aegis_state.load(.acquire);
                if (seen == .set) return &self.aegis_value;
                self.aegis_state.waitUncancelable(io, seen);
            }
        }

        /// As `wait`, giving up with `error.Timeout` once `timeout` has passed; a spurious wakeup before that waits
        /// again.
        pub fn waitTimeout(self: *const Self, io: Io, timeout: Io.Timeout) WaitTimeoutError!*const T {
            const deadline = timeout.toDeadline(io);
            while (true) {
                const seen = self.aegis_state.load(.acquire);
                if (seen == .set) return &self.aegis_value;
                if (deadline.toDurationFromNow(io)) |left| if (left.raw.nanoseconds <= 0) return error.Timeout;
                try self.aegis_state.waitTimeout(io, seen, deadline);
            }
        }
    };
}

const t = std.testing;
const invariant = @import("assert.zig").invariant;

test "a single owner's set is asserted to be the one that set it; a second set returns false and changes nothing" {
    var signal: Signal(u64) = .init();
    try t.expect(signal.get() == null);
    // The single owner's use: its one set is the one, by contract.
    invariant(signal.set(t.io, 42), "the owner sets the signal once");
    // A second set is answered, not refused: false, the first value kept.
    try t.expect(!signal.set(t.io, 7));
    try t.expectEqual(@as(u64, 42), signal.get().?.*);
    try t.expectEqual(@as(u64, 42), (try signal.wait(t.io)).*);
    try t.expectEqual(@as(u64, 42), signal.waitUncancelable(t.io).*);
    try t.expectEqual(@as(u64, 42), (try signal.waitTimeout(t.io, .none)).*);
}

test "a bare signal waits for its set; an unset one times out" {
    var bare: Signal(void) = .init();
    try t.expectError(error.Timeout, bare.waitTimeout(t.io, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } }));
    try t.expect(bare.set(t.io, {}));
    _ = try bare.wait(t.io);
}
