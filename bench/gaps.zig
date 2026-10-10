//! Same-host alternating A/B for the adoption-gap operations against their hand-written forms. Never a CI timing gate.
const std = @import("std");
const gaps = @import("gaps");
const aegis = @import("aegis");
const Io = std.Io;
const samples = 16;
const iterations = 5_000_000;
const names = [_][]const u8{ "try_acquire", "lazy_ready", "lazy_cold", "shared_churn", "shared_churn_4", "atomic_add", "atomic_add_4", "atomic_add_vs_hardware", "atomic_add_vs_hardware_4" };
const Sample = struct { baseline: f64, wrapper: f64 };

fn Churn(comptime wrapped: bool) type {
    return struct {
        handle: if (wrapped) gaps.Handle else gaps.DirectHandle,
        fn worker(self: *@This(), count: usize) void {
            for (0..count) |_| {
                var mine = gaps.sharedRetain(wrapped, &self.handle);
                std.mem.doNotOptimizeAway(gaps.sharedGet(wrapped, &mine));
                gaps.sharedRelease(wrapped, &mine);
            }
        }
    };
}

/// A counter fed by several tasks. The "vs_hardware" rows put the checked add on the wrapper side against the plain
/// wrapping instruction, which is what the checked form costs; the others pair the checked add with the
/// hand-written compare-and-swap loop that does the same.
fn Adding(comptime wrapped: bool, comptime hardware: bool) type {
    return struct {
        cell: gaps.AtomicCell(wrapped),
        fn add(self: *@This()) void {
            if (hardware and !wrapped) {
                std.mem.doNotOptimizeAway(gaps.atomicAddWrapping(false, &self.cell, 1));
            } else {
                std.mem.doNotOptimizeAway(gaps.atomicAdd(wrapped, &self.cell, 1) catch unreachable); // unreachable: the count stays far below the maximum
            }
        }
        fn worker(self: *@This(), count: usize) void {
            for (0..count) |_| self.add();
        }
    };
}

noinline fn measure(comptime wrapped: bool, comptime name: []const u8, io: Io, count: usize) !f64 {
    var accumulator: u64 = 0;
    var owner: gaps.Owner(wrapped) = .{ .data = 0 };
    var lazy: if (wrapped) aegis.Lazy(u64) else gaps.DirectLazy = .{};
    var block: gaps.DirectBlock = .{ .gpa = std.testing.failing_allocator, .data = 7 };
    var churn: Churn(wrapped) = .{ .handle = if (wrapped) .{ .block = @ptrCast(&block) } else .{ .block = &block } }; // safe: Handle's block is the same one-pointer layout as the hand-written block, asserted by the parity gate
    block.count.store(1 << 20, .monotonic);
    if (comptime std.mem.eql(u8, name, "lazy_ready")) _ = try gaps.lazyCold(wrapped, io, &lazy, 5);
    const hardware = comptime std.mem.indexOf(u8, name, "vs_hardware") != null;
    var adding: Adding(wrapped, hardware) = .{ .cell = if (wrapped) .init(.fromRaw(0)) else .init(0) };
    const threads: usize = if (comptime std.mem.endsWith(u8, name, "_4")) 4 else 1;
    const start = Io.Clock.awake.now(io);
    if (threads > 1) {
        var group: Io.Group = .init;
        defer group.cancel(io);
        if (comptime std.mem.startsWith(u8, name, "atomic")) {
            for (0..threads) |_| try group.concurrent(io, Adding(wrapped, hardware).worker, .{ &adding, count });
        } else for (0..threads) |_| try group.concurrent(io, Churn(wrapped).worker, .{ &churn, count });
        try group.await(io);
    } else for (0..count) |i| {
        if (comptime std.mem.eql(u8, name, "try_acquire")) {
            accumulator +%= @intFromBool(gaps.tryAcquire(wrapped, &owner));
        } else if (comptime std.mem.eql(u8, name, "lazy_ready")) {
            accumulator +%= (gaps.lazyReady(wrapped, &lazy)).?.*;
        } else if (comptime std.mem.startsWith(u8, name, "atomic")) {
            adding.add();
        } else if (comptime std.mem.eql(u8, name, "lazy_cold")) {
            lazy.state.store(.empty, .monotonic);
            accumulator +%= (try gaps.lazyCold(wrapped, io, &lazy, i + 1)).*;
        } else Churn(wrapped).worker(&churn, 1);
    }
    const elapsed = start.durationTo(Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(accumulator);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count * threads));
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &out.interface;
    inline for (names) |name| {
        const rounds: usize = if (comptime std.mem.endsWith(u8, name, "_4")) iterations / 10 else iterations;
        if (smoke) {
            _ = try measure(false, name, init.io, 2);
            _ = try measure(true, name, init.io, 2);
        } else {
            _ = try measure(false, name, init.io, rounds / 5);
            _ = try measure(true, name, init.io, rounds / 5);
            var rows: [samples]Sample = undefined;
            for (&rows, 0..) |*row, i| {
                if (i % 2 == 0) {
                    row.baseline = try measure(false, name, init.io, rounds);
                    row.wrapper = try measure(true, name, init.io, rounds);
                } else {
                    row.wrapper = try measure(true, name, init.io, rounds);
                    row.baseline = try measure(false, name, init.io, rounds);
                }
            }
            try report(writer, name, &rows);
        }
    }
    try writer.flush();
}

fn median(values: []f64) f64 {
    std.mem.sort(f64, values, {}, std.sort.asc(f64));
    return values[values.len / 2];
}

fn report(out: *std.Io.Writer, name: []const u8, rows: []const Sample) !void {
    var base: [samples]f64 = undefined;
    var wrap: [samples]f64 = undefined;
    var ratios: [samples]f64 = undefined;
    for (rows, 0..) |row, i| {
        base[i] = row.baseline;
        wrap[i] = row.wrapper;
        ratios[i] = row.wrapper / row.baseline;
    }
    var prng = std.Random.DefaultPrng.init(0x9a95);
    const random = prng.random();
    var boot: [10_000]f64 = undefined;
    for (&boot) |*value| {
        var draw: [samples]f64 = undefined;
        for (&draw) |*r| r.* = ratios[random.uintLessThan(usize, samples)];
        value.* = median(&draw);
    }
    std.mem.sort(f64, &boot, {}, std.sort.asc(f64));
    const b = median(&base);
    const w = median(&wrap);
    try out.print("{s}: baseline={d:.3} wrapper={d:.3} ns/op, ratio95=[{d:.4},{d:.4}]\n", .{ name, b, w, boot[250], boot[9749] });
    for (rows) |row| try out.print("pair {s} {d:.6} {d:.6}\n", .{ name, row.baseline, row.wrapper });
}
