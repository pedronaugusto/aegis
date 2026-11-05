//! One block for a set of parts whose counts are known before any is placed: a struct of the
//! parts declares them, a plan measures them from their counts, and a block of the plan's size
//! places them. The measure and the placement are one walk of the same declaration, so a block
//! always holds its parts and placing them has no failure to report: the only refusals are an
//! allocator's and a caller buffer shorter than the plan.
//!
//! A part is a field of the parts struct:
//! - `[]T` (any alignment): `count` items, counted by a `usize`;
//! - `*T`: one item, counted by nothing (`void`);
//! - `?[]T`, `?*T`, `?S`: a part present or not, counted by `?usize`, `bool` or `?Counts(S)`;
//! - a struct `S` of parts, nested: its parts follow one another, or, when `S` declares
//!   `pub const arrangement: aegis.parts.Arrangement = .overlap`, all start at one place
//!   (alternatives of which one is in use at a time), and the nest is as long as its longest;
//! - `Repeat(S)`: `len` copies of `S`, each counted by the same `each`;
//! - `void`: a part absent at compile time (a field typed `if (c) []T else void`), no bytes.
//!
//! Every part starts at its type's alignment, a nested struct at the greatest of its parts', so
//! a nested struct's size never depends on where it lies. The items are uninitialized; nothing in
//! the block points into anything else, so the parts are the caller's to fill.
const std = @import("std");
const assert = @import("assert.zig");
const units = @import("units.zig");
const Allocator = std.mem.Allocator;

/// How a nested struct of parts lies: one part after another, or all at its start.
pub const Arrangement = enum { sequence, overlap };

pub fn Block(comptime Parts: type) type {
    if (comptime kindOf(Parts) != .nested) @compileError("parts.Block lays out a struct of parts, not " ++ @typeName(Parts));
    return struct {
        const Self = @This();

        /// What sizes each part, one field per part.
        pub const Counts = CountOf(Parts);
        /// The block's alignment: the greatest of its parts'.
        pub const alignment: usize = alignOf(Parts);

        /// Private: the block's bytes, exactly its plan's size.
        memory: []align(alignment) u8,
        /// Private: the counts it was planned for.
        counts: Self.Counts,

        /// The parts measured for their counts.
        pub const Plan = struct {
            /// Private.
            counts: Self.Counts,
            /// Private: the bytes the parts take, or maxInt(usize) when they pass the address space.
            end: usize,

            /// The bytes a block of this plan takes; maxInt(usize) when they pass the address
            /// space, which no block holds.
            pub fn size(p: Plan) units.Bytes(usize) {
                return .fromRaw(p.end);
            }
            /// A block from `gpa`, of exactly the plan's size; the caller frees `bytes()`.
            pub fn alloc(p: Plan, gpa: Allocator) Allocator.Error!Self {
                if (p.end == std.math.maxInt(usize)) return error.OutOfMemory;
                const memory = try gpa.alignedAlloc(u8, comptime .fromByteUnits(alignment), p.end);
                return .{ .memory = memory, .counts = p.counts };
            }
            /// A block over the caller's memory, refused when shorter than the plan; the block is
            /// its first `size()` bytes.
            pub fn fit(p: Plan, buffer: []align(alignment) u8) error{BufferTooSmall}!Self {
                if (buffer.len < p.end) return error.BufferTooSmall;
                return .{ .memory = buffer[0..p.end], .counts = p.counts };
            }
        };

        /// Measures the parts for `counts`. A count past the address space saturates the size.
        pub fn plan(counts: Self.Counts) Plan {
            var at: usize = 0;
            walk(.measure, Parts, {}, &at, counts);
            return .{ .counts = counts, .end = at };
        }

        /// The parts, placed in the block: always, since the block is its plan's size.
        pub fn parts(b: Self) Parts {
            var at: usize = 0;
            return walk(.place, Parts, b.memory, &at, b.counts);
        }

        /// The block's bytes, for the owner of an allocated block to free.
        pub fn bytes(b: Self) []align(alignment) u8 {
            return b.memory;
        }
    };
}

/// What sizes the parts `S`, a struct nested in another's parts: one field per part, as
/// `Block(S).Counts`. A type whose parts others nest declares them and these counts, and builds
/// itself from its placed parts.
pub fn Counts(comptime S: type) type {
    if (comptime kindOf(S) != .nested) @compileError("parts.Counts counts a struct of parts, not " ++ @typeName(S));
    return CountOf(S);
}

/// `len` copies of the parts `S`, each sized by the same counts, one after another at a stride.
pub fn Repeat(comptime S: type) type {
    if (comptime kindOf(S) != .nested) @compileError("parts.Repeat repeats a struct of parts, not " ++ @typeName(S));
    return struct {
        const Self = @This();
        /// The repeated parts.
        pub const Element = S;
        /// How many copies, and the counts each takes.
        pub const Counts = struct { len: usize, each: CountOf(S) };

        /// Private: the copies' bytes.
        memory: []u8,
        /// Private: the bytes from one copy to the next, a multiple of `S`'s alignment.
        stride: usize,
        /// Private.
        count: usize,
        /// Private.
        each: CountOf(S),

        pub fn len(r: Self) usize {
            return r.count;
        }
        /// Copy `i`'s parts; past the length stops in every build.
        pub fn at(r: Self, i: usize) S {
            assert.invariant(i < r.count, "parts.Repeat read past its length");
            var offset: usize = 0;
            return walk(.place, S, r.memory[i * r.stride ..][0..r.stride], &offset, r.each);
        }
    };
}

const Kind = enum { slice, one, optional, nested, repeat, absent };

fn kindOf(comptime F: type) Kind {
    return switch (@typeInfo(F)) {
        .pointer => |p| kind: {
            if (p.attrs.@"const") @compileError("a part is written: " ++ @typeName(F) ++ " is const");
            if (@sizeOf(p.child) == 0) @compileError("a part of no bytes holds nothing: " ++ @typeName(F));
            break :kind switch (p.size) {
                .slice => .slice,
                .one => .one,
                .many, .c => @compileError("a part is a slice or a single item, not " ++ @typeName(F)),
            };
        },
        .optional => |o| switch (kindOf(o.child)) {
            .optional => @compileError("a part is optional once: " ++ @typeName(F)),
            .repeat => @compileError("an absent Repeat is one of no copies: " ++ @typeName(F)),
            .absent => @compileError("an optional part of no bytes holds nothing: " ++ @typeName(F)),
            else => .optional,
        },
        .void => .absent,
        .@"struct" => if (@hasDecl(F, "Element") and @TypeOf(F.Element) == type and F == Repeat(F.Element)) .repeat else .nested,
        else => @compileError("a part is a slice, a pointer, an optional one, a struct of parts, a Repeat or void or a Repeat, not " ++ @typeName(F)),
    };
}

fn arrangementOf(comptime F: type) Arrangement {
    return if (@hasDecl(F, "arrangement")) F.arrangement else .sequence;
}

/// What counts a part of type `F`.
fn CountOf(comptime F: type) type {
    return switch (kindOf(F)) {
        .slice => usize,
        .one => void,
        .absent => void,
        .optional => {
            const C = @typeInfo(F).optional.child;
            return if (CountOf(C) == void) bool else ?CountOf(C);
        },
        .repeat => F.Counts,
        .nested => {
            const s = @typeInfo(F).@"struct";
            var types: [s.field_names.len]type = undefined;
            var attrs: [s.field_names.len]std.lang.Type.Struct.FieldAttributes = undefined;
            for (s.field_types, 0..) |ft, i| {
                types[i] = CountOf(ft);
                attrs[i] = if (types[i] == void) .{ .default_value_ptr = &{} } else .{};
            }
            return @Struct(.auto, null, s.field_names, &types, &attrs);
        },
    };
}

fn alignOf(comptime F: type) usize {
    return switch (kindOf(F)) {
        .slice, .one => @typeInfo(F).pointer.attrs.@"align" orelse @alignOf(@typeInfo(F).pointer.child),
        .absent => 1,
        .optional => alignOf(@typeInfo(F).optional.child),
        .repeat => alignOf(F.Element),
        .nested => {
            var a: usize = 1;
            for (@typeInfo(F).@"struct".field_types) |ft| a = @max(a, alignOf(ft));
            return a;
        },
    };
}

/// Measuring adds up sizes and saturates at maxInt(usize), past which no block exists; placing
/// walks the same declaration over a block of the measured size, so its offsets are the
/// measure's and never overflow.
const Mode = enum { measure, place };

fn Out(comptime mode: Mode, comptime F: type) type {
    return if (mode == .place) F else void;
}

fn Memory(comptime mode: Mode) type {
    return if (mode == .place) []u8 else void;
}

fn alignUp(comptime mode: Mode, at: usize, comptime a: usize) usize {
    if (mode == .place) return std.mem.alignForward(usize, at, a);
    if (at > std.math.maxInt(usize) - (a - 1)) return std.math.maxInt(usize);
    return std.mem.alignForward(usize, at, a);
}

fn advance(comptime mode: Mode, at: usize, n: usize, comptime size: usize) usize {
    if (mode == .place) return at + n * size;
    // A byte's count is its size: LLVM keeps a saturating multiply by one.
    return if (size == 1) at +| n else at +| (n *| size);
}

/// The part `F` at `at`, counted by `count`; `at` moves past it.
inline fn walk(comptime mode: Mode, comptime F: type, memory: Memory(mode), at: *usize, count: CountOf(F)) Out(mode, F) {
    switch (comptime kindOf(F)) {
        .absent => return,
        .slice => {
            const p = @typeInfo(F).pointer;
            return take(mode, p.child, comptime alignOf(F), memory, at, count);
        },
        .one => {
            const p = @typeInfo(F).pointer;
            const items = take(mode, p.child, comptime alignOf(F), memory, at, 1);
            if (mode == .place) return &items[0] else return;
        },
        .optional => {
            const C = @typeInfo(F).optional.child;
            const present: ?CountOf(C) = if (CountOf(C) == void) (if (count) @as(?void, {}) else null) else count;
            if (present) |c| return walk(mode, C, memory, at, c);
            if (mode == .place) return null else return;
        },
        .repeat => {
            const S = F.Element;
            var one: usize = 0;
            walk(.measure, S, {}, &one, count.each);
            const stride = alignUp(.measure, one, comptime alignOf(S));
            const start = alignUp(mode, at.*, comptime alignOf(S));
            at.* = if (mode == .place) start + count.len * stride else start +| (count.len *| stride);
            if (mode == .place) return .{ .memory = memory[start..at.*], .stride = stride, .count = count.len, .each = count.each } else return;
        },
        .nested => {
            const s = @typeInfo(F).@"struct";
            const start = alignUp(mode, at.*, comptime alignOf(F));
            var value: Out(mode, F) = undefined;
            switch (comptime arrangementOf(F)) {
                .sequence => {
                    at.* = start;
                    inline for (s.field_names, s.field_types) |name, ft| {
                        const part = walk(mode, ft, memory, at, @field(count, name));
                        if (mode == .place) @field(value, name) = part;
                    }
                },
                .overlap => {
                    var end = start;
                    inline for (s.field_names, s.field_types) |name, ft| {
                        var member = start;
                        const part = walk(mode, ft, memory, &member, @field(count, name));
                        if (mode == .place) @field(value, name) = part;
                        end = @max(end, member);
                    }
                    at.* = end;
                },
            }
            return value;
        },
    }
}

/// `n` items of `T` at `at`, aligned to `a`.
inline fn take(comptime mode: Mode, comptime T: type, comptime a: usize, memory: Memory(mode), at: *usize, n: usize) Out(mode, []align(a) T) {
    const start = alignUp(mode, at.*, a);
    at.* = advance(mode, start, n, @sizeOf(T));
    if (mode == .measure) return else {
        const items = memory[start..at.*];
        return @as([*]align(a) T, @ptrCast(@alignCast(items.ptr)))[0..n]; // safe: the block starts at its parts' greatest alignment and `start` is aligned to `a`; `items` is n of T's size, inside the block its plan measured
    }
}
