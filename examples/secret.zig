//! A session key held inline: borrowed to use, moved into its long-lived home, wiped at the end.
const std = @import("std");
const aegis = @import("aegis");

pub fn main() !void {
    // The key a handshake derived, held from the moment it exists.
    var derived = aegis.Secret([32]u8).init(@splat(0x5a));
    // A borrow reads it in place; nothing copies it out.
    aegis.assert.post(derived.expose()[0] == 0x5a, "the key reads through a borrow");

    // Its long-lived home takes it by `moveInto`, which wipes the source: one live copy, not two.
    var session_key: aegis.Secret([32]u8) = undefined;
    derived.moveInto(&session_key);
    defer session_key.deinit(); // wipes every byte, in every build mode

    // `{f}` on a Secret does not compile, and its `format` refuses without writing a byte.
    var line: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&line);
    if (session_key.format(&writer)) |_| unreachable else |err| aegis.assert.invariant(err == error.SecretNotFormattable, "formatting fails closed");
    aegis.assert.post(writer.buffered().len == 0, "nothing was written");
}
