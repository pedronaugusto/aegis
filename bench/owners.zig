//! Same-host alternating A/B, seven or more paired samples after warmup. Never a CI timing gate.
const std = @import("std");
const cases = @import("cases");
const samples = 32;
const iterations = 5_000_000;
const contention_iterations = 100_000;
const Sample = struct { baseline: f64, wrapper: f64 };

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &out.interface;
    inline for (.{ "secret32", "transfer32", "secret48", "transfer48", "material", "transferMaterial", "budget", "job", "contention2", "contention8" }) |name| {
        if (smoke) {
            _ = try measure(false, name, init.io, 2);
            _ = try measure(true, name, init.io, 2);
        } else {
            const rounds: usize = if (std.mem.startsWith(u8, name, "contention")) contention_iterations else iterations;
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

// Keep the timing loop out of caller-specific inlining/layout; both variants compile in identical contexts.
noinline fn measure(comptime wrapped: bool, comptime name: []const u8, io: std.Io, count: usize) !f64 {
    var accumulator: usize = 0;
    var shared: cases.Owner(usize, wrapped) = .{ .data = 0 };
    var budget: cases.Owner(cases.Counts, wrapped) = .{ .data = .{} };
    var completion: cases.Owner(cases.Completion, wrapped) = .{ .data = .{} };
    const threads: usize = if (std.mem.eql(u8, name, "contention2")) 2 else if (std.mem.eql(u8, name, "contention8")) 8 else 1;
    const start = std.Io.Clock.awake.now(io);
    if (threads > 1) {
        var group: std.Io.Group = .init;
        defer group.cancel(io);
        for (0..threads) |_| try group.concurrent(io, worker(wrapped), .{ &shared, count });
        try group.await(io);
        std.debug.assert(shared.data == count * threads);
        accumulator = shared.data;
    } else {
        for (0..count) |i| {
            const seed: u8 = @truncate(i); // safe: synthetic public seed intentionally repeats every 256 iterations
            if (std.mem.eql(u8, name, "budget")) {
                accumulator +%= @intFromBool(cases.budget(wrapped, &budget, 128));
            } else if (std.mem.eql(u8, name, "job")) {
                accumulator +%= cases.job(wrapped, &completion, i);
            } else if (std.mem.eql(u8, name, "material") or std.mem.eql(u8, name, "transferMaterial")) {
                var source: cases.Material = .{ .rsa = .{ .size = 256, .exponent_size = 3, .n = @splat(seed), .d = @splat(seed ^ 0x51) } };
                var destination: cases.Material = undefined;
                accumulator +%= if (std.mem.eql(u8, name, "material")) cases.secret(cases.Material, wrapped, &source) else cases.transfer(cases.Material, wrapped, &source, &destination);
            } else {
                const T = comptime if (std.mem.endsWith(u8, name, "32")) [32]u8 else [48]u8;
                var source: T = @splat(seed);
                source[0] ^= 0x51;
                var destination: T = undefined;
                accumulator +%= if (std.mem.startsWith(u8, name, "transfer")) cases.transfer(T, wrapped, &source, &destination) else cases.secret(T, wrapped, &source);
            }
        }
    }
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(accumulator);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count * threads));
}

fn worker(comptime wrapped: bool) fn (*cases.Owner(usize, wrapped), usize) void {
    return struct {
        fn run(owner: *cases.Owner(usize, wrapped), count: usize) void {
            for (0..count) |_| cases.increment(wrapped, owner);
        }
    }.run;
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
    const b = median(&base);
    const w = median(&wrap);
    var prng = std.Random.DefaultPrng.init(0xae615);
    const random = prng.random();
    var boot: [10_000]f64 = undefined;
    for (&boot) |*value| {
        var draw: [samples]f64 = undefined;
        for (&draw) |*r| r.* = ratios[random.uintLessThan(usize, samples)];
        value.* = median(&draw);
    }
    std.mem.sort(f64, &boot, {}, std.sort.asc(f64));
    try out.print("{s}: baseline={d:.3} wrapper={d:.3} ns/op, ratio95=[{d:.4},{d:.4}], throughput={d:.0}/{d:.0} op/s, spread=[{d:.3},{d:.3}]/[{d:.3},{d:.3}]\n", .{ name, b, w, boot[250], boot[9749], 1e9 / b, 1e9 / w, base[0], base[samples - 1], wrap[0], wrap[samples - 1] });
    for (rows) |row| try out.print("pair {s} {d:.6} {d:.6}\n", .{ name, row.baseline, row.wrapper });
}
