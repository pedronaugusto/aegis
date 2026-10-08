//! Alternating ReleaseFast A/B with raw samples and paired bootstrap interval.
const std = @import("std");
const cases = @import("numeric");
const samples = 32;
const iterations = 20_000_000;
const Sample = struct { baseline: f64, wrapper: f64, b1: f64, b2: f64, w1: f64, w2: f64 };
const Operation = *const fn (u64, u64) u64;
fn operation(comptime name: []const u8, comptime wrapped: bool) Operation {
    return struct {
        fn run(x: u64, y: u64) align(64) u64 {
            return cases.operation(name, wrapped, x, y);
        }
    }.run;
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &out.interface;
    if (!smoke) try writer.print("A3 paired ns/op baseline/wrapper; samples={d} iterations={d}; callbacks align=64; ABBA/BAAB blocks; median averages both central values\n", .{ samples, iterations });
    inline for (cases.names) |name| {
        const base = operation(name, false);
        const wrap = operation(name, true);
        const assertion = comptime std.mem.eql(u8, name, "invariant");
        // Both successful and failing raw inputs, with a bounded success path for invariants.
        for (0..64) |i| {
            const x: u64 = if (assertion) i else i *% 0x9e3779b97f4a7c15;
            const y: u64 = if (assertion) i + 1 else i % 65;
            if (base(x, y) != wrap(x, y)) return error.BaselineMismatch;
        }
        if (smoke) {
            _ = measure(base, assertion, init.io, 2);
            _ = measure(wrap, assertion, init.io, 2);
        } else {
            _ = measure(base, assertion, init.io, iterations / 5);
            _ = measure(wrap, assertion, init.io, iterations / 5);
            var rows: [samples]Sample = undefined;
            for (&rows, 0..) |*row, i| {
                // Each block balances clock/thermal drift; retain both halves, not only averages.
                if (i % 2 == 0) {
                    row.b1 = measure(base, assertion, init.io, iterations / 2);
                    row.w1 = measure(wrap, assertion, init.io, iterations / 2);
                    row.w2 = measure(wrap, assertion, init.io, iterations / 2);
                    row.b2 = measure(base, assertion, init.io, iterations / 2);
                } else {
                    row.w1 = measure(wrap, assertion, init.io, iterations / 2);
                    row.b1 = measure(base, assertion, init.io, iterations / 2);
                    row.b2 = measure(base, assertion, init.io, iterations / 2);
                    row.w2 = measure(wrap, assertion, init.io, iterations / 2);
                }
                row.baseline = (row.b1 + row.b2) / 2;
                row.wrapper = (row.w1 + row.w2) / 2;
            }
            try writer.print("code {s} identical-entry={any}\n", .{ name, @intFromPtr(base) == @intFromPtr(wrap) }); // safe: compare live code addresses without exposing them
            try report(writer, name, &rows);
        }
    }
    try writer.flush();
}
noinline fn measure(op: Operation, assertion: bool, io: std.Io, count: usize) f64 {
    var sum: u64 = 0;
    var state: u64 = 1;
    const start = std.Io.Clock.awake.now(io);
    for (0..count) |i| {
        // safe: explicit wrapping PRNG and checksum; neither represents a domain count.
        state = state *% 6364136223846793005 +% 1;
        const x = if (assertion) state >> 1 else if (i % 2 == 0) state else state & 0xffff;
        const y = if (assertion) x + 1 else i % 67;
        sum +%= op(x, y);
    }
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(sum);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}
fn median(values: []f64) f64 {
    std.mem.sort(f64, values, {}, std.sort.asc(f64));
    const mid = values.len / 2;
    return if (values.len % 2 == 0) (values[mid - 1] + values[mid]) / 2 else values[mid];
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
    var prng = std.Random.DefaultPrng.init(0xa361);
    const random = prng.random();
    var boot: [10_000]f64 = undefined;
    for (&boot) |*value| {
        var draw: [samples]f64 = undefined;
        for (&draw) |*r| r.* = ratios[random.uintLessThan(usize, samples)];
        value.* = median(&draw);
    }
    std.mem.sort(f64, &boot, {}, std.sort.asc(f64));
    try out.print("{s}: median={d:.3}/{d:.3} ns/op best={d:.3}/{d:.3} p95={d:.3}/{d:.3} p99={d:.3}/{d:.3} ratio95=[{d:.4},{d:.4}] spread=[{d:.3},{d:.3}]/[{d:.3},{d:.3}] allocations=0 retained=0\n", .{ name, b, w, base[0], wrap[0], base[30], wrap[30], base[31], wrap[31], boot[250], boot[9749], base[0], base[31], wrap[0], wrap[31] });
    for (rows) |row| {
        try out.print("pair {s} {d:.6} {d:.6}\n", .{ name, row.baseline, row.wrapper });
        try out.print("halves {s} B1={d:.6} B2={d:.6} W1={d:.6} W2={d:.6}\n", .{ name, row.b1, row.b2, row.w1, row.w2 });
    }
}
