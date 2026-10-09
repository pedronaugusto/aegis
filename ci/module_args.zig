//! CLI projections of the published namespace module graph, shared by proof tools.
const std = @import("std");
pub const names = [_][]const u8{ "int", "id", "units", "assert", "secret", "sync", "handle", "input", "err" };
pub fn expand(arena: std.mem.Allocator, original: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    for (original) |arg| {
        if (!std.mem.eql(u8, arg, "-Maegis=src/root.zig")) {
            try args.append(arena, arg);
            continue;
        }
        for (names) |name| try args.appendSlice(arena, &.{ "--dep", name });
        try args.append(arena, arg);
        // Base kernels are shared by declaration identity, never copied into namespaces.
        try args.appendSlice(arena, &.{ "--dep", "scalar", "-Mint=src/int.zig", "--dep", "scalar", "-Mid=src/id.zig", "--dep", "scalar", "--dep", "int", "-Munits=src/units.zig", "-Massert=src/assert.zig", "-Msecret=src/secret.zig", "-Msync=src/sync.zig", "-Mhandle=src/handle.zig", "-Minput=src/input.zig", "-Merr=src/err.zig", "-Mscalar=src/scalar.zig" });
    }
    return args.toOwnedSlice(arena);
}
