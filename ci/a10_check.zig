//! Typestate mode matrix, intended-reason compile rejections and portable profiles.
const std = @import("std");
const builtin = @import("builtin");

const Run = struct { gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, zig: []const u8 };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) return error.ZigExecutableRequired;
    const run: Run = .{ .gpa = init.gpa, .arena = arena, .io = init.io, .zig = args[1] };
    try std.Io.Dir.cwd().createDirPath(init.io, ".zig-cache/a10");
    try modes(run);
    try rejections(run);
    try portable(run);
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A10: mode matrix, 16 compiler rejections and 6 portable profiles passed\n");
    try out.interface.flush();
}

fn modes(run: Run) !void {
    for ([_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
        const binary = try run.arena.print(".zig-cache/a10/contracts-{s}{s}", .{ mode, if (builtin.os.tag == .windows) ".exe" else "" });
        const compiled = try std.process.run(run.gpa, run.io, .{ .argv = &.{ run.zig, "build-exe", try run.arena.print("-O{s}", .{mode}), "--dep", "aegis", "-Mroot=ci/a10_contract.zig", "-Maegis=src/root.zig", try run.arena.print("-femit-bin={s}", .{binary}) }, .stderr_limit = .limited(16384) });
        defer run.gpa.free(compiled.stdout);
        defer run.gpa.free(compiled.stderr);
        if (compiled.term != .exited or compiled.term.exited != 0) {
            var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
            try out.interface.writeAll(compiled.stderr);
            return error.ContractCompilationFailed;
        }
        const debug = std.mem.eql(u8, mode, "Debug");
        const checked = debug or std.mem.eql(u8, mode, "ReleaseSafe");
        const When = enum { debug, checked, always };
        const cases = [_]struct { name: []const u8, message: []const u8, when: When }{
            .{ .name = "stage-reuse", .message = "state stage used after its payload moved on", .when = .debug },
            .{ .name = "take-twice", .message = "state stage used after its payload moved on", .when = .debug },
            .{ .name = "stage-alias", .message = "state transition destination is its own source", .when = .checked },
            .{ .name = "commit-forged", .message = "state commit of an edge the machine does not declare", .when = .always },
        };
        for (cases) |case| {
            const must_fail = switch (case.when) {
                .debug => debug,
                .checked => checked,
                .always => true,
            };
            const result = try std.process.run(run.gpa, run.io, .{ .argv = &.{ binary, case.name }, .stderr_limit = .limited(16384) });
            defer run.gpa.free(result.stdout);
            defer run.gpa.free(result.stderr);
            const succeeded = result.term == .exited and result.term.exited == 0;
            if (must_fail == succeeded) {
                var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
                try out.interface.print("A10 {s} {s}: expected {s}\n", .{ mode, case.name, if (must_fail) "a stop" else "no stop" });
                try out.interface.flush();
                return error.ModeContractMismatch;
            }
            if (must_fail and std.mem.find(u8, result.stderr, case.message) == null) {
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
    \\const Link = a.state.Machine(enum { idle, open, closed }, enum { dial, close, drop }, .{
    \\    .initial = .idle,
    \\    .terminal = &.{.closed},
    \\    .edges = &.{
    \\        .{ .from = .idle, .on = .dial, .to = .open },
    \\        .{ .from = .open, .on = .close, .to = .closed },
    \\    },
    \\});
    \\export fn run() void { checked() catch {}; }
    \\fn checked() !void {
    \\
;

fn rejections(run: Run) !void {
    const cases = .{
        .{ "const M = a.state.Machine(enum { x, y }, enum { e }, .{ .initial = .x, .edges = &.{ .{ .from = .x, .on = .e, .to = .y }, .{ .from = .x, .on = .e, .to = .x } } }); _ = M;", "duplicate edge from .x on .e" },
        .{ "const M = a.state.Machine(enum { x, y }, enum { e }, .{ .initial = .x, .terminal = &.{.y}, .edges = &.{ .{ .from = .x, .on = .e, .to = .y }, .{ .from = .y, .on = .e, .to = .x } } }); _ = M;", "terminal state .y has an edge out" },
        .{ "const M = a.state.Machine(enum { x, y }, enum { e }, .{ .initial = .x, .edges = &.{.{ .from = .x, .on = .e, .to = .y }} }); _ = M;", "state .y has no edge out and is not terminal" },
        .{ "const M = a.state.Machine(enum { x, y, z }, enum { e }, .{ .initial = .x, .terminal = &.{.y}, .edges = &.{ .{ .from = .x, .on = .e, .to = .y }, .{ .from = .z, .on = .e, .to = .z } } }); _ = M;", "state .z is not reachable from .x" },
        .{ "const M = a.state.Machine(enum { x, y }, enum { e }, .{ .initial = .x, .terminal = &.{ .x, .y }, .edges = &.{} }); _ = M;", "the initial state .x is terminal" },
        .{ "const M = a.state.Machine(enum { x, y }, enum { e }, .{ .initial = .x, .terminal = &.{ .y, .y }, .edges = &.{.{ .from = .x, .on = .e, .to = .y }} }); _ = M;", "terminal state .y is listed twice" },
        .{ "const M = a.state.Machine(u8, enum { e }, .{ .initial = 0, .edges = &.{} }); _ = M;", "the states must be an exhaustive enum" },
        .{ "const M = a.state.Machine(enum { x }, enum(u8) { e, _ }, .{ .initial = .x, .edges = &.{} }); _ = M;", "the events must be an exhaustive enum" },
        .{ "var s = Link.At(.idle, u8).init(1); var d: Link.At(.open, u8) = undefined; s.transition(.close, &d);", "no edge from .idle on .close" },
        .{ "var s = Link.At(.idle, u8).init(1); var d: Link.At(.closed, u8) = undefined; s.transition(.dial, &d);", "expected type" },
        .{ "var s = Link.At(.idle, u8).init(1); var d: Link.At(.closed, u8) = undefined; try s.transitionWith(.dial, &d, {}, struct { fn f(_: void, _: *u8, _: *u8) error{No}!void {} }.f);", "pointer to the stage at .open" },
        .{ "var s = Link.At(.idle, u8).init(1); var out: u8 = undefined; s.take(&out);", "a payload is taken from a terminal stage; .idle is not terminal" },
        .{ "var s = Link.At(.open, u8).init(1); _ = &s;", "only the initial stage is constructed" },
        .{ "var s = Link.At(.idle, u8).init(1); var d: Link.At(.open, u8) = undefined; try s.transitionWith(.dial, &d, {}, struct { fn f(_: void, _: *u8, _: *u8) u8 { return 0; } }.f);", "a state preparation returns void or an error union of void" },
        .{ "const Other = a.state.Machine(enum { idle, open }, enum { dial }, .{ .initial = .idle, .terminal = &.{.open}, .edges = &.{.{ .from = .idle, .on = .dial, .to = .open }} }); var s = Link.At(.idle, u8).init(1); var d: Other.At(.open, u8) = undefined; s.transition(.dial, &d);", "expected type" },
        .{ "var r = Link.Runtime(u8).init(1); _ = try r.step(.nonsense);", "no member named 'nonsense'" },
    };
    try std.Io.Dir.cwd().createDirPath(run.io, ".zig-cache/a10/negative");
    inline for (cases, 0..) |case, i| {
        const path = try run.arena.print(".zig-cache/a10/negative/{d}.zig", .{i});
        try std.Io.Dir.cwd().writeFile(run.io, .{ .sub_path = path, .data = try run.arena.print("{s}    {s}\n}}\n", .{ prologue, case[0] }) });
        for ([_][]const u8{ "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
            const result = try std.process.run(run.gpa, run.io, .{ .argv = &.{ run.zig, "build-obj", try run.arena.print("-O{s}", .{mode}), "--dep", "aegis", try run.arena.print("-Mroot={s}", .{path}), "-Maegis=src/root.zig", "-fno-emit-bin" }, .stderr_limit = .limited(32768) });
            defer run.gpa.free(result.stdout);
            defer run.gpa.free(result.stderr);
            if (result.term != .exited or result.term.exited == 0 or std.mem.find(u8, result.stderr, case[1]) == null) {
                var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
                try out.interface.print("A10 negative {d} {s}: expected {s}\n{s}", .{ i, mode, case[1], result.stderr });
                try out.interface.flush();
                return error.StateContractNotDiagnosed;
            }
        }
    }
}

fn portable(run: Run) !void {
    for ([_][]const u8{ "x86-linux-gnu", "wasm32-freestanding", "aarch64-freestanding" }) |target| {
        for ([_][]const u8{ "ReleaseSafe", "ReleaseFast" }) |mode| {
            const result = try std.process.run(run.gpa, run.io, .{ .argv = &.{ run.zig, "build-obj", try run.arena.print("-O{s}", .{mode}), "-target", target, "--dep", "aegis", "-Mroot=ci/a10_values.zig", "-Maegis=src/root.zig", "-fno-emit-bin" }, .stderr_limit = .limited(16384) });
            defer run.gpa.free(result.stdout);
            defer run.gpa.free(result.stderr);
            if (result.term != .exited or result.term.exited != 0) {
                var out = std.Io.File.stderr().writerStreaming(run.io, &.{});
                try out.interface.writeAll(result.stderr);
                return error.PortableStateCompilationFailed;
            }
        }
    }
}
