//! Reads the layout table each ci/layouts.zig object carries and writes it out, one file per
//! profile and mode. The objects compiling at all is the check; this makes it readable.
//! Arguments: the output directory, then a name and an object for each build.
const std = @import("std");
const layouts = @import("layouts.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 4 or (args.len - 2) % 2 != 0) return error.DirectoryAndObjectsRequired;
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, args[1]);
    var pairs = std.mem.window([]const u8, args[2..], 2, 2);
    while (pairs.next()) |pair| {
        const object = try dir.readFileAlloc(init.io, pair[1], init.gpa, .limited(64 * 1024 * 1024));
        defer init.gpa.free(object);
        const begin = std.mem.find(u8, object, layouts.begin_marker) orelse return error.MissingLayoutReport;
        const start = begin + layouts.begin_marker.len;
        const end = std.mem.findPos(u8, object, start, layouts.end_marker) orelse return error.TruncatedLayoutReport;
        try dir.writeFile(init.io, .{ .sub_path = try init.arena.allocator().print("{s}/{s}.md", .{ args[1], pair[0] }), .data = object[start .. end + 1] });
    }
}
