//! A8/A9 portable compilation and strict paired release instruction/layout gate.
const std = @import("std");
const builtin = @import("builtin");
const emitted = @import("codegen.zig");
const names = [_][]const u8{ "handle_get", "handle_insert", "handle_remove", "handle_index", "input_parse", "context_push", "input_diagnostics", "dense_sum" };
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) return error.ZigExecutableRequired;
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/a8-a9");
    for ([_][]const u8{ "x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-linux-musl", "x86_64-windows-gnu", "aarch64-windows-gnu", "x86_64-macos", "aarch64-macos", "x86-linux-gnu", "wasm32-freestanding", "aarch64-freestanding" }) |target| {
        for ([_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
            const stem = try arena.print(".zig-cache/a8-a9/{s}-{s}", .{ target, mode });
            const paired = std.mem.endsWith(u8, target, "linux-gnu") and (std.mem.startsWith(u8, target, "x86_64") or std.mem.startsWith(u8, target, "aarch64")) and (std.mem.eql(u8, mode, "ReleaseFast") or std.mem.eql(u8, mode, "ReleaseSmall"));
            var argv: std.ArrayList([]const u8) = .empty;
            try argv.appendSlice(arena, &.{ args[1], "build-obj", try arena.print("-O{s}", .{mode}), "-target", target, "-mcpu=baseline", "-fllvm", "-fstrip", "--dep", "aegis", "-Mroot=ci/safety_parity.zig", "-Maegis=src/root.zig", try arena.print("-femit-bin={s}.o", .{stem}) });
            if (paired) try argv.appendSlice(arena, &.{ try arena.print("-femit-llvm-ir={s}.ll", .{stem}), try arena.print("-femit-asm={s}.s", .{stem}) });
            const result = try std.process.run(init.gpa, init.io, .{ .argv = argv.items, .stderr_limit = .limited(32768) });
            defer init.gpa.free(result.stdout);
            defer init.gpa.free(result.stderr);
            if (result.term != .exited or result.term.exited != 0) {
                var out = std.Io.File.stderr().writer(init.io, &.{});
                try out.interface.writeAll(result.stderr);
                return error.SafetyProfileCompilationFailed;
            }
            if (paired) try compare(init, target, mode, stem);
        }
    }
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A8/A9: 40 profiles compiled; 32 Fast/Small layout/instruction pairs equal; retirement checked by the A8 tests\n");
    try out.interface.flush();
}
fn compare(init: std.process.Init, target: []const u8, mode: []const u8, stem: []const u8) !void {
    const arena = init.arena.allocator();
    const dir = std.Io.Dir.cwd();
    const assembly = try dir.readFileAlloc(init.io, try arena.print("{s}.s", .{stem}), arena, .limited(32 * 1024 * 1024));
    const ir = try dir.readFileAlloc(init.io, try arena.print("{s}.ll", .{stem}), arena, .limited(32 * 1024 * 1024));
    const object = try dir.readFileAlloc(init.io, try arena.print("{s}.o", .{stem}), arena, .limited(32 * 1024 * 1024));
    for (names) |name| {
        const base = try emitted.exportName(arena, "baseline", name);
        const wrap = try emitted.exportName(arena, "wrapper", name);
        const bs = try emitted.symbolSize(object, base);
        const ws = try emitted.symbolSize(object, wrap);
        const ba = try emitted.assemblyAlias(arena, assembly, base);
        const wa = try emitted.assemblyAlias(arena, assembly, wrap);
        if (bs != ws or (!std.mem.eql(u8, ba, wa) and !std.mem.eql(u8, try emitted.instructions(arena, assembly, ba, target), try emitted.instructions(arena, assembly, wa, target)))) {
            var out = std.Io.File.stderr().writer(init.io, &.{});
            try out.interface.print("{s} {s} {s}: {d}/{d} bytes or instructions differ\n", .{ target, mode, name, bs, ws });
            try out.interface.flush();
            return error.SafetyAbstractionMismatch;
        }
        // Every resolving fixture must retain its required validation even in Fast/Small.
        const body = try emitted.function(arena, ir, try emitted.alias(arena, ir, wrap));
        if (std.mem.eql(u8, name, "handle_get") and std.mem.find(u8, body, "icmp") == null) return error.KeyChecksStripped;
    }
}
