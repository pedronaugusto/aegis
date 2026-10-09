//! A8/A9 intended-reason compilation failures, including secret and owner rejection.
const std = @import("std");
const module_args = @import("module_args.zig");
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) return error.ZigExecutableRequired;
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/a8-a9-negative");
    const cases = .{
        .{ "const A = a.handle.Index(struct {}, u32); const B = a.handle.Index(struct {}, u32); const x: B = try A.from(0, 1); _ = x;", "expected type" },
        .{ "const P = a.handle.Pool(u32, struct {}); const Q = a.handle.Pool(u32, struct {}); var p: P = undefined; const k: Q.Key = undefined; _ = try p.get(k);", "expected type" },
        .{ "const U = a.input.Untrusted(u32); const Parser = struct { fn run(_: void, _: u32) error{Invalid}!bool { return true; } }; _ = try U.init(1).parse({}, Parser.run);", "distinct refined result" },
        .{ "const U = a.input.Untrusted(u32); const Parser = struct { fn run(_: void, x: u32) error{Invalid}!u32 { return x; } }; _ = try U.init(1).parse({}, Parser.run);", "distinct refined result" },
        .{ "const U = a.input.Untrusted(u32); const Parser = struct { fn run(_: void, x: u32) anyerror!struct { x: u32 } { return .{.x=x}; } }; _ = try U.init(1).parse({}, Parser.run);", "named error set" },
        .{ "const U = a.input.Untrusted(u32); const Parser = struct { fn run(_: void, _: u32) error{Invalid}!a.input.Untrusted(u64) { return .init(1); } }; _ = try U.init(1).parse({}, Parser.run);", "distinct refined result" },
        .{ "const Owned = struct { x: u32, pub fn deinit(_: *@This()) void {} }; const U = a.input.Untrusted(Owned); _ = U.init(.{.x=1});", "nonowning by-value" },
        .{ "const Parsed = struct { x: u32 }; const Consumer = struct { fn use(_: Parsed) void {} }; Consumer.use(a.input.Untrusted(u32).init(1));", "expected type" },
        .{ "const Frame = struct { offset: u32 }; var ctx: a.err.Context(Frame, 4) = .{}; _ = &ctx;", "explicit admission" },
        .{ "const Frame = struct { pub const aegis_public_frame = true; bytes: []const u8 }; var ctx: a.err.Context(Frame, 4) = .{}; _ = &ctx;", "pointers, slices" },
        .{ "const Frame = struct { pub const aegis_public_frame = true; pointer: *const u32 }; var ctx: a.err.Context(Frame, 4) = .{}; _ = &ctx;", "pointers, slices" },
        .{ "const Frame = struct { pub const aegis_public_frame = true; material: a.Secret([32]u8) }; var ctx: a.err.Context(Frame, 4) = .{}; _ = &ctx;", "no owners or formatters" },
        .{ "const Frame = struct { pub const aegis_public_frame = true; choice: a.secret.Choice }; var ctx: a.err.Context(Frame, 4) = .{}; _ = &ctx;", "no owners or formatters" },
        .{ "const Frame = struct { pub const aegis_public_frame = true; value: u32, pub fn format(_: @This(), _: *std.Io.Writer) std.Io.Writer.Error!void {} }; var ctx: a.err.Context(Frame, 4) = .{}; _ = &ctx;", "no owners or formatters" },
        .{ "const F = a.err.Failure(anyerror, u32, 1); var x: F = undefined; _ = &x;", "named error set" },
        .{ "_ = a.err.PublicSource.classify(\"   \", \"value\" );", "classification requires a reason" },
    };
    inline for (cases, 0..) |case, i| {
        const path = try arena.print(".zig-cache/a8-a9-negative/{d}.zig", .{i});
        try dir.writeFile(init.io, .{ .sub_path = path, .data = try arena.print("const std=@import(\"std\"); const a=@import(\"aegis\"); export fn run() void {{ checked() catch {{}}; }} fn checked() !void {{ {s} }}\n", .{case[0]}) });
        for ([_][]const u8{ "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
            const result = try std.process.run(init.gpa, init.io, .{ .argv = try module_args.expand(init.arena.allocator(), &.{ args[1], "build-obj", try arena.print("-O{s}", .{mode}), "--dep", "aegis", try arena.print("-Mroot={s}", .{path}), "-Maegis=src/root.zig", "-fno-emit-bin" }), .stderr_limit = .limited(32768) });
            defer init.gpa.free(result.stdout);
            defer init.gpa.free(result.stderr);
            if (result.term != .exited or result.term.exited == 0 or std.mem.find(u8, result.stderr, case[1]) == null) {
                var out = std.Io.File.stderr().writer(init.io, &.{});
                try out.interface.print("A8/A9 negative {d} {s}: expected {s}\n{s}", .{ i, mode, case[1], result.stderr });
                try out.interface.flush();
                return error.SafetyContractNotDiagnosed;
            }
        }
    }
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A8/A9: 48 intended-reason compiler rejections passed\n");
    try out.interface.flush();
}
