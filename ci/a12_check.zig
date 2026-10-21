//! Scope mode matrix, intended-reason compile rejections and portable profiles.
//! The build compiles the contract program in each mode and passes the binaries
//! after the Zig, in the order of `modes`; it compiles the portable profiles too.
const std = @import("std");

const Run = struct { gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, zig: []const u8, binaries: []const []const u8 };

const modes = [_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2 + modes.len) return error.ContractBinariesRequired;
    const run: Run = .{ .gpa = init.gpa, .arena = arena, .io = init.io, .zig = args[1], .binaries = args[2..] };
    try matrix(run);
    try rejections(run);
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A12: mode matrix and 8 compiler rejections passed\n");
    try out.interface.flush();
}

/// Every case stops in Debug and ReleaseSafe and runs to the end in ReleaseFast and ReleaseSmall.
fn matrix(run: Run) !void {
    for (modes, run.binaries) |mode, binary| {
        const checked = std.mem.eql(u8, mode, "Debug") or std.mem.eql(u8, mode, "ReleaseSafe");
        const cases = [_]struct { name: []const u8, message: []const u8 }{
            .{ .name = "ref-expired", .message = "scope reference used after its scope ended" },
            .{ .name = "ref-after-reuse", .message = "scope reference used after its scope ended" },
            .{ .name = "end-twice", .message = "scope ended twice" },
            .{ .name = "ref-after-end", .message = "scope used after it ended" },
            .{ .name = "reborrow-expired", .message = "scope reference used after its scope ended" },
            .{ .name = "table-open", .message = "scope table torn down with a scope still open" },
        };
        for (cases) |case| {
            const result = try std.process.run(run.gpa, run.io, .{ .argv = &.{ binary, case.name }, .stderr_limit = .limited(16384) });
            defer run.gpa.free(result.stdout);
            defer run.gpa.free(result.stderr);
            const succeeded = result.term == .exited and result.term.exited == 0;
            if (checked == succeeded) {
                var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
                try out.interface.print("A12 {s} {s}: expected {s}\n", .{ mode, case.name, if (checked) "a stop" else "no stop" });
                try out.interface.flush();
                return error.ModeContractMismatch;
            }
            if (checked and std.mem.find(u8, result.stderr, case.message) == null) {
                var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
                try out.interface.writeAll(result.stderr);
                return error.UnexpectedContractFailure;
            }
        }
    }
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
