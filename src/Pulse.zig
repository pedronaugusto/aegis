//! A repeated wake across tasks: bumped by any side, any number of times, and waited past by any task
//! that keeps the generation it last saw.
const std = @import("std");
const Io = std.Io;
const Atomic = @import("Atomic.zig").Atomic;
const units = @import("units.zig");

/// A wake one side gives again and again and any task waits past: data arrived, room was made, an orphan
/// was adopted. Where `Signal` is once, `Pulse` is every time: each `bump` advances its generation by one and
/// wakes every waiter, and a waiter keeps the generation it last saw and waits until the Pulse has moved past
/// it. Nothing is reset, so nothing races a reset: a waiter that read `current`, then waits past what it read,
/// never misses a bump made in between, because the wait sleeps only while the word still holds `seen`.
///
/// A Pulse carries no value. What changed is the caller's to read after the wait, under whatever guards it.
///
/// The generation is a 32-bit word, as a futex waits on, and wraps. A waiter that misses exactly 2^32 bumps
/// between reading the generation and waiting past it would see the word unchanged and sleep on. No program
/// makes four billion bumps in that window; it is stated, not handled.
///
/// Ownership: the Pulse belongs to whoever made it, which keeps it in place (never moved or copied once
/// another task can reach it) and alive until every waiter has returned.
pub const Pulse = struct {
    /// Private: the generation, one more per bump, wrapping.
    aegis_generation: Atomic(Generation) = .init(.fromRaw(0)),

    /// Which bump a Pulse is at, modulo 2^32: compared with another, never counted by hand.
    pub const Generation = units.Count(Pulse, u32);
    pub const WaitTimeoutError = error{Timeout} || Io.Cancelable;

    pub fn init() Pulse {
        return .{};
    }

    /// Advances the generation by one and wakes every waiter. Never fails and never waits.
    pub fn bump(self: *Pulse, io: Io) void {
        _ = self.aegis_generation.fetchAddWrapping(.fromRaw(1), .release);
        self.aegis_generation.wake(io, std.math.maxInt(u32));
    }

    /// The generation now. A waiter reads it, looks at what the Pulse guards, and waits past it if nothing it
    /// wants is there yet.
    pub fn current(self: *const Pulse) Generation {
        return self.aegis_generation.load(.acquire);
    }

    /// Waits until the generation is past `seen` and returns the one it found; a cancellation point.
    pub fn waitPast(self: *const Pulse, io: Io, seen: Generation) Io.Cancelable!Generation {
        while (true) {
            const now = self.aegis_generation.load(.acquire);
            if (!now.eql(seen)) return now;
            try self.aegis_generation.wait(io, seen);
        }
    }

    /// As `waitPast`, never canceled.
    pub fn waitPastUncancelable(self: *const Pulse, io: Io, seen: Generation) Generation {
        while (true) {
            const now = self.aegis_generation.load(.acquire);
            if (!now.eql(seen)) return now;
            self.aegis_generation.waitUncancelable(io, seen);
        }
    }

    /// As `waitPast`, giving up with `error.Timeout` once `timeout` has passed; a spurious wakeup before that
    /// waits again.
    pub fn waitPastTimeout(self: *const Pulse, io: Io, seen: Generation, timeout: Io.Timeout) WaitTimeoutError!Generation {
        const deadline = timeout.toDeadline(io);
        while (true) {
            const now = self.aegis_generation.load(.acquire);
            if (!now.eql(seen)) return now;
            if (deadline.toDurationFromNow(io)) |left| if (left.raw.nanoseconds <= 0) return error.Timeout;
            try self.aegis_generation.waitTimeout(io, seen, deadline);
        }
    }
};

const t = std.testing;

test "a pulse moves past every generation a waiter saw, once per bump, and a waiter past it returns at once" {
    var pulse: Pulse = .init();
    const first = pulse.current();
    pulse.bump(t.io);
    const second = try pulse.waitPast(t.io, first);
    try t.expect(!second.eql(first));
    try t.expect(pulse.waitPastUncancelable(t.io, first).eql(second));
    pulse.bump(t.io);
    try t.expect(!(try pulse.waitPastTimeout(t.io, second, .none)).eql(second));
}

test "a pulse no one bumps times out past the generation it holds" {
    var pulse: Pulse = .init();
    const seen = pulse.current();
    try t.expectError(error.Timeout, pulse.waitPastTimeout(t.io, seen, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } }));
}
