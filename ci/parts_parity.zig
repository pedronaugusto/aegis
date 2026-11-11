//! Paired exports: a compressor's hand-written plan and carving of one block, and the same through
//! `parts.Block`. The parts: a hash table, the sequences, the literals and a 64-byte aligned
//! window, one after another. The hand-written plan saturates as a careful one does, so a count
//! past the address space is a size no block holds; its carving is the same offsets, unchecked
//! past the bounds of the block it was measured for.
const std = @import("std");
const a = @import("aegis");

const Sequence = extern struct { lit: u32, len: u16, off: u16 };
const Parts = struct { hash: []u32, seqs: []Sequence, lits: []u8, window: []align(64) u8 };
const Block = a.parts.Block(Parts);
/// The counts a caller passes, as the exports take them.
pub const Counts = extern struct { hash: usize, seqs: usize, lits: usize, window: usize };

fn alignUp(at: usize, comptime n: usize) usize {
    if (at > std.math.maxInt(usize) - (n - 1)) return std.math.maxInt(usize);
    return std.mem.alignForward(usize, at, n);
}

fn directSize(c: *const Counts) usize {
    var at: usize = 0;
    at = alignUp(at, 4) +| (c.hash *| 4);
    at = alignUp(at, 4) +| (c.seqs *| 8);
    at = alignUp(at, 1) +| c.lits;
    at = alignUp(at, 64) +| c.window;
    return at;
}

fn take(comptime T: type, comptime n: usize, memory: []u8, at: *usize, count: usize) []align(n) T {
    const start = std.mem.alignForward(usize, at.*, n);
    at.* = start + count * @sizeOf(T);
    const items = memory[start..at.*];
    return @as([*]align(n) T, @ptrCast(@alignCast(items.ptr)))[0..count]; // safe: the hand-written carving's cast, as the block's
}

fn directParts(memory: []align(64) u8, c: *const Counts) Parts {
    var at: usize = 0;
    const hash = take(u32, 4, memory, &at, c.hash);
    const seqs = take(Sequence, 4, memory, &at, c.seqs);
    const lits = take(u8, 1, memory, &at, c.lits);
    const window = take(u8, 64, memory, &at, c.window);
    return .{ .hash = hash, .seqs = seqs, .lits = lits, .window = window };
}

fn counts(c: *const Counts) Block.Counts {
    return .{ .hash = c.hash, .seqs = c.seqs, .lits = c.lits, .window = c.window };
}

export fn baselinePartsPlan(c: *const Counts) usize {
    const k = c.*;
    return directSize(&k);
}
export fn wrapperPartsPlan(c: *const Counts) usize {
    return if (Block.plan(counts(c)).size()) |n| n.raw() else |_| std.math.maxInt(usize);
}

/// The last part's address and the window's length, after carving a block measured for `c`.
export fn baselinePartsPlace(memory: [*]align(64) u8, c: *const Counts) usize {
    // The counts read once, as a caller keeps them.
    const k = c.*;
    const size = directSize(&k);
    // A careful carving refuses a plan past the address space, as the block's `size` does.
    if (size == std.math.maxInt(usize)) return 0;
    const p = directParts(memory[0..size], &k);
    return @intFromPtr(p.window.ptr) +% p.lits.len;
}
export fn wrapperPartsPlace(memory: [*]align(64) u8, c: *const Counts) usize {
    const plan = Block.plan(counts(c));
    // The memory is the plan's size, so `fit`'s refusal folds away; a plan past the address
    // space is refused, as the careful carving refuses it.
    const n = plan.size() catch return 0;
    const block = plan.fit(memory[0..n.raw()]) catch return 0;
    const p = block.parts();
    return @intFromPtr(p.window.ptr) +% p.lits.len;
}

comptime {
    std.debug.assert(Block.alignment == 64);
}
