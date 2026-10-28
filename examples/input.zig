//! A length-prefixed header off the wire: bytes marked untrusted until a parser turns them
//! into a type of their own, its errors the parser's and nothing added.
const aegis = @import("aegis");

const Header = struct { kind: u8, body: []const u8 };
const HeaderError = error{ Truncated, TooLong };

/// The one place a `Header` is made: everything it checks, the type now says.
fn parseHeader(limit: usize, bytes: []const u8) HeaderError!Header {
    if (bytes.len < 2) return error.Truncated;
    if (bytes[1] > limit) return error.TooLong;
    if (bytes.len - 2 < bytes[1]) return error.Truncated;
    return .{ .kind = bytes[0], .body = bytes[2..][0..bytes[1]] };
}

fn handle(header: Header) usize {
    return header.body.len;
}

pub fn main() !void {
    const received = [_]u8{ 7, 3, 'a', 'b', 'c' };
    const wire = aegis.input.Untrusted([]const u8).init(&received);
    // `handle(wire)` does not compile: only a parsed header reaches it.
    const header = try wire.parse(@as(usize, 16), parseHeader);
    aegis.assert.invariant(handle(header) == 3 and header.kind == 7, "parsed into its own type");

    const short = aegis.input.Untrusted([]const u8).init(received[0..3]);
    if (short.parse(@as(usize, 16), parseHeader)) |_| unreachable else |err| aegis.assert.invariant(err == error.Truncated, "the parser's error, unchanged");
}
