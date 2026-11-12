//! Pulse under shakedown's simulation: a bump between a waiter's read and its wait is never lost, every
//! waiter wakes on one bump, and a timeout and a cancel each return.
const std = @import("std");
const shake = @import("shakedown");
const a = @import("../root.zig");
const Io = std.Io;
const t = std.testing;
const Generation = a.Pulse.Generation;

const PulseState = struct {
    pulse: a.Pulse = .init(),

    fn waitPast(self: *const PulseState, io: Io, seen: Generation) Io.Cancelable!Generation {
        return self.pulse.waitPast(io, seen);
    }

    fn bumpOnce(self: *PulseState, io: Io) void {
        self.pulse.bump(io);
    }

    /// The waiter reads the generation, then waits past it, while another task bumps once: before the wait
    /// begins, while it begins or after it sleeps. In every order the wait returns.
    fn lostWake(self: *PulseState, io: Io) !void {
        const seen = self.pulse.current();
        var bumper = try io.concurrent(bumpOnce, .{ self, io });
        const past = try self.pulse.waitPast(io, seen);
        try t.expect(!past.eql(seen));
        bumper.await(io);
    }

    /// Four waiters wait past one generation; one bump wakes them all.
    fn manyWaiters(self: *PulseState, io: Io) !void {
        const seen = self.pulse.current();
        var waiters: [4]Io.Future(Io.Cancelable!Generation) = undefined;
        for (&waiters) |*waiter| waiter.* = try io.concurrent(waitPast, .{ self, io, seen });
        self.pulse.bump(io);
        for (&waiters) |*waiter| try t.expect(!(try waiter.await(io)).eql(seen));
    }

    /// No one bumps: the wait gives up at its deadline.
    fn timeout(self: *PulseState, io: Io) !void {
        const left: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } };
        try t.expectError(error.Timeout, self.pulse.waitPastTimeout(io, self.pulse.current(), left));
    }

    /// No one bumps: a canceled waiter returns `Canceled`.
    fn cancel(self: *PulseState, io: Io) !void {
        var waiter = try io.concurrent(waitPast, .{ self, io, self.pulse.current() });
        try t.expectError(error.Canceled, waiter.cancel(io));
    }
};

const scenarios = .{ PulseState.lostWake, PulseState.manyWaiters, PulseState.timeout, PulseState.cancel };

test "pulse: a bump is never lost, every waiter wakes, a timeout and a cancel return, under seeded yields and spurious wakes" {
    for (0..8) |seed| {
        inline for (scenarios) |run| {
            const sim = try shake.Sim.init(t.allocator, .{ .executor = .threads, .seed = seed, .yield_per_million = 250000, .spurious_wake_per_million = 300000 });
            defer sim.deinit();
            var state: PulseState = .{};
            try t.expectEqual(shake.Sim.Outcome.finished, sim.run(run, .{ &state, sim.io() }));
        }
    }
}

fn searched(comptime run: fn (*PulseState, Io) anyerror!void) fn (void, *shake.Case) anyerror!void {
    return struct {
        fn body(_: void, c: *shake.Case) anyerror!void {
            const sim = try c.sim(.{ .executor = .threads });
            var state: PulseState = .{};
            switch (sim.run(run, .{ &state, sim.io() })) {
                .finished => {},
                .failed => |err| return err,
                else => return error.Unfinished,
            }
        }
    }.body;
}

test "pulse: the lost-wake race and the many waiters end clean in every order within the bound" {
    inline for (.{ PulseState.lostWake, PulseState.manyWaiters }) |run| {
        const result = try shake.explore(t.allocator, {}, searched(run), .{ .spurious_wakes = 1 });
        try t.expect(result.complete);
    }
}
