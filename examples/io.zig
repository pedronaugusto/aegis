//! A reader handed on as a bare `*Io.Reader` loses why it failed; an end keeps the way back to
//! the cause, so a cancel stays a cancel.
const std = @import("std");
const aegis = @import("aegis");

/// Code that reads: it sees only std's interface and settles a failed read through the end.
fn firstByte(end: aegis.io.ReadEnd) error{ ReadFailed, Canceled, EndOfStream }!u8 {
    return end.reader().takeByte() catch |err| switch (err) {
        error.ReadFailed => end.settle(error.ReadFailed),
        error.EndOfStream => error.EndOfStream,
    };
}

pub fn main() !void {
    var fixed: std.Io.Reader = .fixed("z");
    // A fixed buffer fails only by ending: it records no cause, and says so.
    const end: aegis.io.ReadEnd = .causeless(&fixed);
    const byte = try firstByte(end);
    aegis.assert.invariant(byte == 'z', "the end reads through std's interface");
    aegis.assert.invariant(end.failure() == null, "a causeless end has no cause to give");
}
