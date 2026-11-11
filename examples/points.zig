//! A write-ahead log that marks where it may fail in its own code: built as a program, the point
//! is compiled out and the append always succeeds; in a test, a driver (shakedown's) may make it
//! fail with an error of the append's own set, or shorten what one write takes.
const std = @import("std");
const aegis = @import("aegis");

/// The log's points: the list a test names to count them.
pub const Point = enum { append_fails, short_write };

const Log = struct {
    bytes: [64]u8 = undefined,
    len: usize = 0,

    fn append(log: *Log, record: []const u8) error{ InputOutput, NoSpaceLeft }!void {
        if (aegis.points.fault(Point.append_fails)) return error.InputOutput;
        var rest = record;
        while (rest.len != 0) {
            const room = log.bytes.len - log.len;
            if (room == 0) return error.NoSpaceLeft;
            // One write takes what fits, or less where a test shortens it.
            const n = aegis.points.shorten(Point.short_write, @min(room, rest.len));
            @memcpy(log.bytes[log.len..][0..n], rest[0..n]);
            log.len += n;
            rest = rest[n..];
        }
    }
};

pub fn main() !void {
    var log: Log = .{};
    try log.append("begin;");
    try log.append("commit;");
    aegis.assert.invariant(std.mem.eql(u8, log.bytes[0..log.len], "begin;commit;"), "outside a test no point fires");
}
