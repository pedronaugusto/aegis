//! Same-host alternating A/B runner for paired hand-written and wrapped workloads. Never a CI timing gate.
const std = @import("std");
const Io = std.Io;

const samples = 16;
const resamples = 10_000;

/// One workload's two sides, in nanoseconds per operation.
pub const Pair = struct { baseline: f64, wrapper: f64 };

/// Runs every named workload through `measure(comptime wrapped, comptime name, io, count)`, warmed up and
/// alternated so drift hits both sides, and prints the median of each side with a 95% bootstrap interval of
/// the median wrapper/baseline ratio. `--smoke` runs each side a few times and prints nothing.
pub fn run(comptime names: []const []const u8, comptime measure: anytype, init: std.process.Init, iterations: usize) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var buffer: [4096]u8 = undefined;
    var out = Io.File.stdout().writer(init.io, &buffer);
    inline for (names) |name| {
        if (smoke) {
            _ = try measure(false, name, init.io, 2);
            _ = try measure(true, name, init.io, 2);
        } else {
            _ = try measure(false, name, init.io, iterations / 5);
            _ = try measure(true, name, init.io, iterations / 5);
            var rows: [samples]Pair = undefined;
            for (&rows, 0..) |*row, i| {
                if (i % 2 == 0) {
                    row.baseline = try measure(false, name, init.io, iterations);
                    row.wrapper = try measure(true, name, init.io, iterations);
                } else {
                    row.wrapper = try measure(true, name, init.io, iterations);
                    row.baseline = try measure(false, name, init.io, iterations);
                }
            }
            try report(&out.interface, name, &rows);
        }
    }
    try out.interface.flush();
}

fn median(values: []f64) f64 {
    std.mem.sort(f64, values, {}, std.sort.asc(f64));
    return values[values.len / 2];
}

fn report(out: *Io.Writer, name: []const u8, rows: []const Pair) !void {
    var base: [samples]f64 = undefined;
    var wrap: [samples]f64 = undefined;
    var ratios: [samples]f64 = undefined;
    for (rows, 0..) |row, i| {
        base[i] = row.baseline;
        wrap[i] = row.wrapper;
        ratios[i] = row.wrapper / row.baseline;
    }
    var prng = std.Random.DefaultPrng.init(0xa10a12);
    const random = prng.random();
    var boot: [resamples]f64 = undefined;
    for (&boot) |*value| {
        var draw: [samples]f64 = undefined;
        for (&draw) |*r| r.* = ratios[random.uintLessThan(usize, samples)];
        value.* = median(&draw);
    }
    std.mem.sort(f64, &boot, {}, std.sort.asc(f64));
    try out.print("{s}: baseline={d:.3} wrapper={d:.3} ns/op, ratio95=[{d:.4},{d:.4}]\n", .{ name, median(&base), median(&wrap), boot[resamples / 40], boot[resamples - 1 - resamples / 40] });
    for (rows) |row| try out.print("pair {s} {d:.6} {d:.6}\n", .{ name, row.baseline, row.wrapper });
}
