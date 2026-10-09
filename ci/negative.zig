//! Negative compilation must fail for the intended shape-validation reason.
const std = @import("std");
const module_args = @import("module_args.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ZigExecutableRequired;
    for ([_][]const u8{ "slice", "pointer", "aggregate", "optional", "union", "function", "nested", "resource", "format", "bytes_format" }) |name| {
        const root = try init.arena.allocator().print("-Mroot=ci/negative/{s}.zig", .{name});
        const result = try std.process.run(init.gpa, init.io, .{ .argv = try module_args.expand(init.arena.allocator(), &.{ args[1], "build-obj", "--dep", "aegis", root, "-Maegis=src/root.zig", "-fno-emit-bin", "--cache-dir", ".zig-cache/negative", "--global-cache-dir", ".zig-cache/global" }), .stdout_limit = .limited(4096), .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited == 0) return error.UnsupportedShapeAccepted;
        const message = if (std.mem.endsWith(u8, name, "format")) "SecretNotFormattable" else "Secret requires";
        if (std.mem.find(u8, result.stderr, message) == null) return error.UnexpectedCompilationFailure;
    }
    const scalar_cases = .{
        .{ "order_cycle", "cyclic lock order" },
        .{ "zero_ring", "ring capacity must be nonzero" },
        .{ "id_domain", "expected type" },
        .{ "count_domain", "expected type" },
        .{ "byte_unit", "expected type" },
        .{ "clock_domain", "expected type" },
        .{ "duration_unit", "expected type" },
        .{ "instant_add", "expected type" },
        .{ "integer_policy", "expected type" },
        .{ "range_bounds", "min <= max" },
        .{ "float_cast", "integer source" },
        .{ "zero_width", "nonzero-width" },
        .{ "signed_counter", "unsigned representation" },
        .{ "partial_encoding", "whole-byte" },
        .{ "id_repr", "ABI scalar requires" },
        .{ "unit_repr", "ABI scalar requires" },
        .{ "range_repr", "ABI scalar requires" },
    };
    inline for (scalar_cases) |case| {
        const root = try init.arena.allocator().print("-Mroot=ci/negative/{s}.zig", .{case[0]});
        const result = try std.process.run(init.gpa, init.io, .{ .argv = try module_args.expand(init.arena.allocator(), &.{ args[1], "build-obj", "--dep", "aegis", root, "-Maegis=src/root.zig", "-fno-emit-bin", "--cache-dir", ".zig-cache/negative", "--global-cache-dir", ".zig-cache/global" }), .stdout_limit = .limited(4096), .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited == 0) return error.UnsafeScalarMixAccepted;
        if (std.mem.find(u8, result.stderr, case[1]) == null) {
            var out = std.Io.File.stderr().writer(init.io, &.{});
            try out.interface.writeAll(result.stderr);
            return error.UnexpectedCompilationFailure;
        }
    }
}
