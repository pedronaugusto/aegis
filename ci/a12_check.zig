//! Scope intended-reason compile rejections; the mode matrix is ci/modes.zig's. The build
//! passes the Zig the rejections compile with; it compiles the portable profiles too.
const std = @import("std");

const Run = struct { gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, zig: []const u8 };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) return error.ZigExecutableRequired;
    const run: Run = .{ .gpa = init.gpa, .arena = arena, .io = init.io, .zig = args[1] };
    try rejections(run);
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A12: 8 compiler rejections passed\n");
    try out.interface.flush();
}

const prologue =
    \\const std = @import("std");
    \\const a = @import("aegis");
    \\const Request = struct {};
    \\const Connection = struct {};
    \\export fn run() void { checked() catch {}; }
    \\fn checked() !void {
    \\    var slots: [1]a.scope.Table(Request).Slot = undefined;
    \\    var table = a.scope.Table(Request).init(&slots);
    \\    var other_slots: [1]a.scope.Table(Connection).Slot = undefined;
    \\    var other = a.scope.Table(Connection).init(&other_slots);
    \\    var value: u32 = 0;
    \\    _ = .{ &table, &other, &value };
    \\
;

fn rejections(run: Run) !void {
    const cases = .{
        .{ "const request = try table.open(); const wrong: a.scope.Ref(Connection, *u32) = request.ref(&value); _ = wrong;", "expected type" },
        .{ "const request = try table.open(); const wrong: a.scope.Table(Connection).Scope = request; _ = wrong;", "expected type" },
        .{ "_ = a.scope.Ref(Request, u32);", "scope.Ref wraps a single-item pointer or a slice" },
        .{ "_ = a.scope.Ref(Request, [*]u8);", "scope.Ref wraps a single-item pointer or a slice" },
        .{ "_ = a.scope.Ref(Request, ?*u32);", "scope.Ref wraps a single-item pointer or a slice" },
        .{ "const connection = try other.open(); _ = connection.reborrow(@as(u32, 5));", "Pointer" },
        .{ "const request = try table.open(); const view = request.ref(@as(*const u32, &value)); view.get().* = 1;", "constant" },
        .{ "const request: a.scope.Table(Request).Scope = table.open();", "expected type" },
    };
    try std.Io.Dir.cwd().createDirPath(run.io, ".zig-cache/a12/negative");
    inline for (cases, 0..) |case, i| {
        const path = try run.arena.print(".zig-cache/a12/negative/{d}.zig", .{i});
        try std.Io.Dir.cwd().writeFile(run.io, .{ .sub_path = path, .data = try run.arena.print("{s}    {s}\n}}\n", .{ prologue, case[0] }) });
        for ([_][]const u8{ "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
            const result = try std.process.run(run.gpa, run.io, .{ .argv = &.{ run.zig, "build-obj", try run.arena.print("-O{s}", .{mode}), "--dep", "aegis", try run.arena.print("-Mroot={s}", .{path}), "-Maegis=src/root.zig", "-fno-emit-bin" }, .stderr_limit = .limited(32768) });
            defer run.gpa.free(result.stdout);
            defer run.gpa.free(result.stderr);
            if (result.term != .exited or result.term.exited == 0 or std.mem.find(u8, result.stderr, case[1]) == null) {
                var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
                try out.interface.print("A12 negative {d} {s}: expected {s}\n{s}", .{ i, mode, case[1], result.stderr });
                try out.interface.flush();
                return error.ScopeContractNotDiagnosed;
            }
        }
    }
}
