const std = @import("std");
const shake = @import("shakedown");
const Secret = @import("../root.zig").Secret;
const Guarded = @import("../root.zig").Guarded;
const Material = @import("material").Material;

fn patterns(_: void, c: *shake.Case) !void {
    const pattern = shake.gen.int(c.source, u8);
    var source: Secret(Material) = undefined;
    var destination: Secret(Material) = undefined;
    @memset(std.mem.asBytes(&source), pattern);
    source.moveInto(&destination);
    for (std.mem.asBytes(&source)) |byte| try std.testing.expect(byte == 0);
    for (std.mem.asBytes(&destination)) |byte| try std.testing.expect(byte == pattern);
    destination.deinit();
    for (std.mem.asBytes(&destination)) |byte| try std.testing.expect(byte == 0);
}

test "Consumer shakedown secret representation transfer property" {
    try shake.check(std.testing.allocator, {}, patterns, .{ .cases = 512, .seed = 0xae615 });
}

// Before-free observation, never a read of freed storage or a wiped typed value.
const Observe = struct {
    child: std.mem.Allocator,
    allocations: usize = 0,
    frees: usize = 0,
    fn allocator(self: *Observe) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = std.mem.Allocator.noResize, .remap = std.mem.Allocator.noRemap, .free = free } };
    }
    fn of(ptr: *anyopaque) *Observe {
        return @ptrCast(@alignCast(ptr)); // safe: only allocator() installs this vtable with an Observe pointer
    }
    fn alloc(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const observer = of(ptr);
        const memory = observer.child.rawAlloc(len, alignment, ra) orelse return null;
        observer.allocations += 1;
        return memory;
    }
    fn free(ptr: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        @setRuntimeSafety(true);
        std.debug.assert(of(ptr).frees < of(ptr).allocations);
        for (bytes) |byte| std.debug.assert(byte == 0);
        of(ptr).frees += 1;
        of(ptr).child.rawFree(bytes, alignment, ra);
    }
};

fn construction(gpa: std.mem.Allocator, fail_after_move: bool) !void {
    @setRuntimeSafety(true);
    var no_resize = shake.alloc.NoResize.init(gpa);
    var observed: Observe = .{ .child = no_resize.allocator() };
    defer std.debug.assert(observed.allocations == observed.frees);
    const a = observed.allocator();
    var source = Secret([48]u8).init(@splat(0x6b));
    const destination = stage: {
        // These error defers end at publication; later errors must not destroy twice.
        errdefer {
            source.deinit();
            for (std.mem.asBytes(&source)) |byte| std.debug.assert(byte == 0);
        }
        const destination = try a.create(Secret([48]u8));
        errdefer {
            std.crypto.secureZero(u8, std.mem.asBytes(destination));
            a.destroy(destination);
        }
        const scratch = try a.dupe(u8, &@as([32]u8, @splat(0xb7)));
        defer {
            std.crypto.secureZero(u8, scratch);
            // Allocator.free poisons slices before rawFree in Debug; observe first.
            a.rawFree(scratch, .of(u8), @returnAddress());
        }
        source.moveInto(destination);
        break :stage destination;
    };
    defer {
        destination.deinit();
        a.destroy(destination);
    }
    for (std.mem.asBytes(&source)) |byte| try std.testing.expect(byte == 0);
    if (fail_after_move) return error.Aborted;
    try std.testing.expect(destination.expose()[0] == 0x6b);
}

test "Consumer allocation-failure construction observes every wipe before free" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, construction, .{false});
    try std.testing.expectError(error.Aborted, construction(std.testing.allocator, true));
}

const Counts = struct { jobs: usize = 0, bytes: usize = 0 };
const Budget = struct {
    max_jobs: usize = 4,
    max_bytes: usize = 1024,
    shared: Guarded(Counts) = .init(.{}),
    fn reserve(b: *Budget, amount: usize) error{ServiceBusy}!void {
        @setRuntimeSafety(true);
        var held = b.shared.acquire();
        defer held.deinit();
        const active = held.value();
        if (active.jobs >= b.max_jobs or active.bytes > b.max_bytes or amount > b.max_bytes -| active.bytes) return error.ServiceBusy;
        active.jobs += 1;
        active.bytes += amount;
    }
    fn release(b: *Budget, amount: usize) void {
        @setRuntimeSafety(true);
        var held = b.shared.acquire();
        defer held.deinit();
        const active = held.value();
        std.debug.assert(active.jobs > 0);
        std.debug.assert(active.bytes >= amount);
        active.jobs -= 1;
        active.bytes -= amount;
    }
    fn counts(b: *Budget) Counts {
        var held = b.shared.acquire();
        defer held.deinit();
        return held.value().*;
    }
};

fn charges(_: void, c: *shake.Case) !void {
    var budget: Budget = .{};
    const amount = shake.gen.intRange(c.source, usize, 0, 2048);
    const expected = amount <= budget.max_bytes;
    if (budget.reserve(amount)) |_| {
        try std.testing.expect(expected);
        const before = budget.counts();
        try std.testing.expectEqual(@as(usize, 1), before.jobs);
        try std.testing.expectEqual(amount, before.bytes);
        budget.release(amount);
        try std.testing.expectEqual(Counts{}, budget.counts());
    } else |err| {
        try std.testing.expect(!expected and err == error.ServiceBusy);
        try std.testing.expectEqual(Counts{}, budget.counts());
    }
    try std.testing.expectError(error.ServiceBusy, budget.reserve(std.math.maxInt(usize)));
}

test "Consumer Budget cap arithmetic and charge conservation property" {
    try shake.check(std.testing.allocator, {}, charges, .{ .cases = 256, .seed = 0xb0d6e7 });
}

const Phase = enum { pending, running, ready, abandoned, acknowledged };
const Completion = struct { phase: Phase = .pending, result: ?usize = null };
const Job = struct {
    shared: Guarded(Completion) = .init(.{}),
    fn run(job: *Job) void {
        {
            var held = job.shared.acquire();
            defer held.deinit();
            if (held.value().phase == .abandoned) return;
            std.debug.assert(held.value().phase == .pending);
            held.value().phase = .running;
        }
        // Native.evaluate belongs between the scopes. This fixture owns no connection pointer.
        var held = job.shared.acquire();
        defer held.deinit();
        if (held.value().phase != .abandoned) {
            held.value().result = 17;
            held.value().phase = .ready;
        }
    }
    fn abandon(job: *Job) void {
        var held = job.shared.acquire();
        defer held.deinit();
        if (held.value().phase == .acknowledged) return;
        held.value().phase = .abandoned;
        held.value().result = null;
    }
    fn take(job: *Job) ?usize {
        var held = job.shared.acquire();
        defer held.deinit();
        if (held.value().phase != .ready) return null;
        const result = held.value().result;
        held.value().result = null;
        held.value().phase = .acknowledged;
        return result;
    }
};

fn takeRace(job: *Job) void {
    _ = job.take();
}

test "Consumer Job run abandon take races retain charges until executor reap" {
    var budget: Budget = .{};
    for (0..32) |_| {
        try budget.reserve(128);
        var job: Job = .{};
        var group: std.Io.Group = .init;
        defer group.cancel(std.testing.io);
        try group.concurrent(std.testing.io, Job.run, .{&job});
        try group.concurrent(std.testing.io, Job.abandon, .{&job});
        try group.concurrent(std.testing.io, takeRace, .{&job});
        try group.await(std.testing.io);
        try std.testing.expectEqual(@as(usize, 1), budget.counts().jobs);
        var held = job.shared.acquire();
        try std.testing.expect(held.value().phase == .abandoned or held.value().phase == .acknowledged);
        try std.testing.expect(held.value().result == null);
        held.deinit();
        // Charge reclamation is an executor-lifetime operation, never an unlock side effect.
        budget.release(128);
        try std.testing.expectEqual(Counts{}, budget.counts());
    }
}
