//! A tokenizer's memory on one region: the tokens grow as a tail whose items never move, a
//! scratch buffer lives between a mark and its release, and the region's limit is the input's
//! own limit, so a hostile input stops at a named error instead of growing without end.
const std = @import("std");
const aegis = @import("aegis");

const Region = aegis.Region;
const Token = struct { start: u32, len: u32 };

fn tokenize(r: *Region, text: []const u8) Region.Error![]Token {
    var tokens = try r.tail(Token);
    var start: usize = 0;
    for (text, 0..) |byte, i| {
        if (byte != ' ') continue;
        if (i > start) _ = try tokens.append(.{ .start = @intCast(start), .len = @intCast(i - start) });
        start = i + 1;
    }
    if (text.len > start) _ = try tokens.append(.{ .start = @intCast(start), .len = @intCast(text.len - start) });
    return tokens.seal();
}

pub fn main() !void {
    // The limit is the work's own: 1 MiB of tokens, reserved as address space and committed as used.
    var r = try Region.reserve(.init(1 << 20));
    defer r.deinit();

    const text = "regions never move";
    const tokens = try tokenize(&r, text);
    aegis.assert.invariant(tokens.len == 3, "three words");
    const first = &tokens[0];

    // Scratch memory for one step, freed at once by its mark; what came before stays.
    const m = r.mark();
    const upper = try r.dupe(u8, text);
    for (upper) |*byte| byte.* = std.ascii.toUpper(byte.*);
    aegis.assert.invariant(std.mem.eql(u8, upper[0..7], "REGIONS"), "the scratch copy");
    r.release(m);
    aegis.assert.invariant(first == &tokens[0] and first.len == 7, "the tokens never moved");

    // Past the limit is a named error, never a move.
    if (r.push(u8, 2 << 20)) |_| unreachable else |err| aegis.assert.invariant(err == error.LimitExceeded, "the limit holds");

    // Where there is no virtual memory (wasm, freestanding), the same type runs on a buffer.
    var buffer: [256]u8 align(@alignOf(Token)) = undefined;
    var on_buffer = Region.fixed(&buffer);
    defer on_buffer.deinit();
    aegis.assert.invariant((try tokenize(&on_buffer, text)).len == 3, "the same code on a buffer");
}
