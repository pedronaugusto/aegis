//! A parser's scratch state that belongs to one task at a time: checked against its owner in
//! Debug and ReleaseSafe, plain data in ReleaseFast and ReleaseSmall, handed on explicitly.
const aegis = @import("aegis");

const Scratch = struct { depth: u32 = 0, tokens: u32 = 0 };

/// The caller issues each task's identity and keeps them unique.
const reader: aegis.TaskIdentity = @fromBackingInt(@as(usize, 1));
const writer: aegis.TaskIdentity = @fromBackingInt(@as(usize, 2));

pub fn main() !void {
    var scratch = aegis.Confined(Scratch).init(reader, .{});
    scratch.value(reader).tokens += 3;

    // Handed on at a quiescent point the caller synchronizes; from here only `writer` may use it.
    scratch.handOff(reader, writer);
    scratch.value(writer).depth += 1;
    aegis.assert.invariant(scratch.valueConst(writer).tokens == 3, "the state moved with the hand-off");
    // `scratch.value(reader)` now stops a Debug or ReleaseSafe build: `reader` gave it away.
}
