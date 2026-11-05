//! A compressor's memory as one block: its parts are declared once, the options give their
//! counts, and the plan of those counts is both what `memory` reports and what the block holds.
//! `init` allocates the plan and `initBuffer` fits it into the caller's memory; both hand the
//! block to one core, which places the parts and cannot fail, so neither entry asserts that the
//! other's arithmetic agrees with it.
const std = @import("std");
const aegis = @import("aegis");

const Compressor = struct {
    hash: []u32,
    window: []align(64) u8,
    /// Present only when the options ask for a dictionary.
    dictionary: ?[]u8,
    /// The memory `init` allocated; empty after `initBuffer`.
    owned: []align(64) u8,

    const Parts = struct { hash: []u32, window: []align(64) u8, dictionary: ?[]u8 };
    const Block = aegis.parts.Block(Parts);

    const Options = struct { hash_bits: u5 = 12, window: usize = 1 << 15, dictionary: ?usize = null };

    fn plan(options: Options) Block.Plan {
        return Block.plan(.{ .hash = @as(usize, 1) << options.hash_bits, .window = options.window, .dictionary = options.dictionary });
    }

    /// The bytes `initBuffer` needs; `Overflow` past the address space.
    fn memory(options: Options) error{Overflow}!aegis.units.Bytes(usize) {
        return plan(options).size();
    }

    fn init(gpa: std.mem.Allocator, options: Options) std.mem.Allocator.Error!Compressor {
        const block = try plan(options).alloc(gpa);
        var c = assemble(block);
        c.owned = block.bytes();
        return c;
    }

    fn initBuffer(buffer: []align(64) u8, options: Options) error{BufferTooSmall}!Compressor {
        return assemble(try plan(options).fit(buffer));
    }

    /// The one core: a block always holds its parts.
    fn assemble(block: Block) Compressor {
        const p = block.parts();
        @memset(p.hash, 0);
        return .{ .hash = p.hash, .window = p.window, .dictionary = p.dictionary, .owned = &.{} };
    }

    fn deinit(c: *Compressor, gpa: std.mem.Allocator) void {
        if (c.owned.len != 0) gpa.free(c.owned);
        c.* = undefined;
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var owned = try Compressor.init(gpa, .{ .dictionary = 4096 });
    defer owned.deinit(gpa);
    aegis.assert.invariant(owned.dictionary.?.len == 4096 and owned.hash.len == 4096, "the parts the options asked for");

    // The caller's memory: exactly `memory(options)` bytes, and one fewer is refused.
    const options: Compressor.Options = .{ .hash_bits = 10 };
    const n = (try Compressor.memory(options)).raw();
    const buffer = try gpa.alignedAlloc(u8, .@"64", n);
    defer gpa.free(buffer);
    const in_place = try Compressor.initBuffer(buffer, options);
    aegis.assert.invariant(in_place.dictionary == null and @intFromPtr(in_place.window.ptr) % 64 == 0, "no dictionary; the window aligned");
    if (Compressor.initBuffer(buffer[0 .. n - 1], options)) |_| aegis.assert.never("a short buffer is refused") else |_| {}
}
