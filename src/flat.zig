//! One flat layout for a Zig value: a block with no pointers in it, read in place through a
//! `View`, written at its exact size, and checked before untrusted bytes become one.
//!
//! The image is little-endian. A part of fixed size (a scalar, a fixed array, a struct or an
//! optional of such) lies inline where it is used. A part of variable size (a slice, a tagged
//! union, a struct holding one, an optional of one) lies inline as a `u32` offset, measured from
//! the offset's own position and always forward, to its payload: a struct's head, then its
//! variable fields' payloads in field order; a union's tag and its variant; a slice's count and
//! its elements, an offset table first when they are variable. An optional variable part is
//! offset 0 when null. Nothing points backward, so a check of an image ends, and no value of a
//! laid-out type with offsets ever exists outside the image: reads go through `View`.
const builtin = @import("builtin");
const std = @import("std");
const Region = @import("Region.zig");
const bounded = @import("bounded.zig");
const input = @import("input.zig");
const assert = @import("assert.zig");

const little = builtin.cpu.arch.endian() == .little;

/// What an image may hold before `verify` refuses it: finite, never zero as unlimited.
pub const Limits = struct {
    /// Nested variable parts, the root at depth zero.
    depth: bounded.Limit(usize),
    /// Payloads and slice elements visited, counted again where two offsets share one.
    items: bounded.Limit(usize),
};

pub const VerifyError = error{
    /// A part runs past the end of the image.
    Truncated,
    /// The image or a payload is not aligned as its type needs.
    Misaligned,
    /// An offset of zero where the part is not optional.
    BadOffset,
    /// A bool that is neither 0 nor 1, an enum or union tag of no field, an integer past its
    /// type's range, or an optional's presence byte past 1.
    BadValue,
    /// Deeper or larger than `Limits` allows.
    LimitExceeded,
};

/// An image past 4 GiB, where its offsets end.
pub const Error = error{LimitExceeded};

/// Where a builder writes: an image growing in a region's tail, which never moves.
pub const Image = struct {
    /// Private.
    tail: *Region.Tail(u8),
    /// Private: where the image starts in the tail, aligned for every part.
    start: usize,
    /// Private: the builders open, the root's at one.
    open: usize = 0,
    /// Private: how deep builders may nest.
    depth: bounded.Limit(usize),

    /// Starts an image at the end of `tail`, aligned to 16 bytes.
    pub fn init(tail: *Region.Tail(u8), depth: bounded.Limit(usize)) Region.Error!Image {
        const at = @intFromPtr(tail.items().ptr) + tail.len();
        @memset(try tail.addMany(std.mem.alignForward(usize, at, max_align) - at), 0);
        return .{ .tail = tail, .start = tail.len(), .depth = depth };
    }
    /// The image written so far; every builder ended.
    pub fn finish(image: *Image) []align(max_align) const u8 {
        assert.invariant(image.open == 0, "Flat image finished with a builder open");
        return @alignCast(image.tail.items()[image.start..]); // safe: the image starts aligned to max_align
    }
    fn bytes(image: *const Image) []u8 {
        return image.tail.items()[image.start..];
    }
    fn len(image: *const Image) usize {
        return image.tail.len() - image.start;
    }
    /// `n` zero bytes at an aligned end; returns where they start.
    fn grow(image: *Image, align_to: usize, n: usize) Error!usize {
        const at = std.mem.alignForward(usize, image.len(), align_to);
        const end = std.math.add(usize, at, n) catch return error.LimitExceeded;
        if (end >= too_big) return error.LimitExceeded;
        @memset(image.tail.addMany(end - image.len()) catch return error.LimitExceeded, 0);
        return at;
    }
};

/// The greatest alignment a part takes, and so an image's.
const max_align = 16;
/// The alignment every image needs.
pub const alignment = max_align;

/// A position in an image being measured or written. An image ends below 4 GiB, where its
/// offsets end, so a measure stops counting at `too_big` and never overflows.
const Pos = u64;
const too_big: Pos = 1 << 32;
fn add(a: Pos, b: Pos) Pos {
    return @min(a +| b, too_big);
}
fn times(n: usize, stride: usize) Pos {
    return @min(@as(Pos, n) *| stride, too_big);
}
fn aligned(at: Pos, align_to: usize) Pos {
    return if (at >= too_big) too_big else std.mem.alignForward(Pos, at, align_to);
}

pub fn Flat(comptime T: type) type {
    comptime check(T);
    return struct {
        /// A `T` in an image: a pointer to its payload.
        pub const View = struct {
            /// Private.
            ptr: [*]const u8,

            /// A field of a struct, or the active variant of a union (another variant stops in
            /// every build). A scalar or fixed part is its value; a slice of bytes, and of wider
            /// plain numbers on a little-endian target, is a real slice into the image; anything
            /// else variable is a view.
            pub fn get(v: View, comptime field: std.meta.FieldEnum(T)) Read(@FieldType(T, @tagName(field))) {
                const i = @backingInt(field);
                switch (@typeInfo(T)) {
                    .@"struct" => return readInline(@FieldType(T, @tagName(field)), v.ptr + headOffsets(T)[i]),
                    .@"union" => {
                        assert.invariant(v.tag() == @field(std.meta.Tag(T), @tagName(field)), "Flat union read as a variant it does not hold");
                        return readInline(@FieldType(T, @tagName(field)), v.ptr + variantOffset(T, @FieldType(T, @tagName(field))));
                    },
                    else => @compileError("get reads a struct's field or a union's variant"),
                }
            }
            /// A union's tag.
            pub fn tag(v: View) std.meta.Tag(T) {
                if (@typeInfo(T) != .@"union") @compileError("tag reads a union");
                return readInline(std.meta.Tag(T), v.ptr);
            }
            /// A slice's or an array's length.
            pub fn len(v: View) usize {
                return switch (@typeInfo(T)) {
                    .pointer => readInt(u32, v.ptr),
                    .array => |a| a.len,
                    else => @compileError("len reads a slice or an array"),
                };
            }
            /// An element; past the length stops in every build.
            pub fn at(v: View, i: usize) Read(Element(T)) {
                assert.invariant(i < v.len(), "Flat element past its slice");
                return readInline(Element(T), v.ptr + elementsOffset(T) + i * inlineSize(Element(T)));
            }
            /// A plain `T`, its slices allocated from `gpa`. Parts made before an allocation fails
            /// are left to `gpa`: pass an arena.
            pub fn materialize(v: View, gpa: std.mem.Allocator) error{OutOfMemory}!T {
                return materializePayload(T, v.ptr, gpa);
            }
        };

        /// A view of an image this program wrote; nothing is checked.
        pub fn view(image: []align(max_align) const u8) View {
            return .{ .ptr = image.ptr };
        }

        /// Checks every part of `bytes` against `T` and returns a view of it, so a hostile image
        /// never becomes a read out of bounds. This proves safety, not integrity: an edited image
        /// can still describe a valid value.
        pub fn verify(bytes: input.Untrusted([]const u8), limits: Limits) VerifyError!View {
            return bytes.parse(limits, verifyImage);
        }
        fn verifyImage(limits: Limits, bytes: []const u8) VerifyError!View {
            if (@intFromPtr(bytes.ptr) % max_align != 0) return error.Misaligned;
            var visited: usize = 0;
            var checker: Checker = .{ .bytes = bytes, .limits = limits, .visited = &visited };
            try checker.payload(T, 0, 0);
            return .{ .ptr = bytes.ptr };
        }

        /// The exact size of `value`'s image, computed without writing.
        pub fn size(value: T) Error!usize {
            const end = writePayload(T, value, null, 0);
            if (end >= too_big) return error.LimitExceeded;
            return @intCast(end);
        }
        /// Writes `value`'s image into `out`, which holds `size(value)` bytes at least and is
        /// aligned to `alignment`; returns the size.
        pub fn write(value: T, out: []align(max_align) u8) Error!usize {
            const n = try size(value);
            assert.invariant(out.len >= n, "Flat image written to a buffer short of its size");
            @memset(out[0..n], 0);
            _ = writePayload(T, value, out, 0);
            return n;
        }

        /// Streams a `T` into `image`, part by part, when no `T` exists to write whole: a parser's.
        /// The root's builder is the first in an image. A struct or a slice streams; anything else
        /// is written whole.
        pub fn builder(image: *Image) Error!Builder {
            assert.invariant(image.open == 0 and image.len() == 0, "Flat root builder on an image that has one");
            return Builder.open(image, payloadAlign(T));
        }

        pub const Builder = struct {
            /// Private.
            image: *Image,
            /// Private: where the payload starts.
            at: usize,
            /// Private: the builders open when this one opened, itself included.
            depth: usize,
            /// Private: a struct's fields set, a slice's elements appended.
            done: u64 = 0,

            /// Every field of a struct, one bit each.
            const all: u64 = switch (@typeInfo(T)) {
                .@"struct" => |s| if (s.field_names.len == 0) 0 else std.math.maxInt(u64) >> @intCast(64 - s.field_names.len),
                else => 0,
            };

            fn open(image: *Image, align_to: usize) Error!Builder {
                switch (@typeInfo(T)) {
                    .@"struct", .pointer => {},
                    else => @compileError("Flat streams a struct or a slice; write anything else whole: " ++ @typeName(T)),
                }
                if (image.depth.exceeds(image.open)) return error.LimitExceeded;
                const at = try image.grow(align_to, headSize(T));
                image.open += 1;
                return .{ .image = image, .at = at, .depth = image.open };
            }
            fn innermost(b: *const Builder) void {
                assert.invariant(b.image.open == b.depth, "Flat builder used while a part inside it is open, or after its end");
            }
            /// Writes a field whole.
            pub fn set(b: *Builder, comptime field: std.meta.FieldEnum(T), value: @FieldType(T, @tagName(field))) Error!void {
                if (@typeInfo(T) != .@"struct") @compileError("set writes a struct's field");
                b.innermost();
                const bit = @as(u64, 1) << @backingInt(field);
                assert.invariant(b.done & bit == 0, "Flat field set twice");
                const F = @FieldType(T, @tagName(field));
                const slot = b.at + headOffsets(T)[@backingInt(field)];
                if (variable(F)) {
                    if (!optionalNull(F, value)) {
                        // Measured where it will lie: a nested part's alignment depends on it.
                        const P = Payload(F);
                        const target = std.mem.alignForward(usize, b.image.len(), payloadAlign(P));
                        const stop = writePayload(P, unwrap(F, value), null, target);
                        if (stop >= too_big) return error.LimitExceeded;
                        _ = try b.image.grow(1, @intCast(stop - b.image.len()));
                        writeOffset(b.image.bytes(), slot, target);
                        _ = writePayload(P, unwrap(F, value), b.image.bytes(), target);
                    }
                } else _ = writeInline(F, value, b.image.bytes(), slot, 0);
                b.done |= bit;
            }
            /// Opens a variable field to stream into; the field is set when its builder ends.
            pub fn begin(b: *Builder, comptime field: std.meta.FieldEnum(T)) Error!Flat(Payload(@FieldType(T, @tagName(field)))).Builder {
                if (@typeInfo(T) != .@"struct") @compileError("begin opens a struct's field");
                const F = @FieldType(T, @tagName(field));
                if (!variable(F)) @compileError("begin opens a variable field; set writes a fixed one");
                b.innermost();
                const bit = @as(u64, 1) << @backingInt(field);
                assert.invariant(b.done & bit == 0, "Flat field set twice");
                const nested = try Flat(Payload(F)).Builder.open(b.image, payloadAlign(Payload(F)));
                writeOffset(b.image.bytes(), b.at + headOffsets(T)[@backingInt(field)], nested.at);
                b.done |= bit;
                return nested;
            }
            /// Appends an element of fixed size to a slice.
            pub fn append(b: *Builder, value: Element(T)) Error!void {
                if (@typeInfo(T) != .pointer) @compileError("append adds to a slice");
                if (variable(Element(T))) @compileError("a slice of variable elements is set whole");
                b.innermost();
                if (b.done == std.math.maxInt(u32)) return error.LimitExceeded;
                const at = try b.image.grow(inlineAlign(Element(T)), inlineSize(Element(T)));
                _ = writeInline(Element(T), value, b.image.bytes(), at, 0);
                b.done += 1;
            }
            pub fn appendSlice(b: *Builder, values: []const Element(T)) Error!void {
                for (values) |value| try b.append(value);
            }
            /// Rewrites element `i` of the slice, one already appended: a count or an index
            /// known only once a later part is written, as a container's is when it closes.
            /// Past what was appended stops in every build.
            pub fn put(b: *Builder, i: usize, value: Element(T)) void {
                if (@typeInfo(T) != .pointer) @compileError("put rewrites a slice's element");
                if (variable(Element(T))) @compileError("a slice of variable elements is set whole");
                b.innermost();
                assert.invariant(i < b.done, "Flat element put past what was appended");
                _ = writeInline(Element(T), value, b.image.bytes(), b.at + elementsOffset(T) + i * inlineSize(Element(T)), 0);
            }
            /// Closes the part: a slice's count is written, and a struct must have every field set
            /// (stopped in every build otherwise).
            pub fn end(b: *Builder) void {
                b.innermost();
                switch (@typeInfo(T)) {
                    .pointer => writeInt(u32, b.image.bytes()[b.at..][0..4], @intCast(b.done)),
                    .@"struct" => assert.invariant(b.done == all, "Flat builder ended with a field unset"),
                    else => comptime unreachable,
                }
                b.image.open -= 1;
                b.depth = 0;
            }
        };
    };
}

// Layout ------------------------------------------------------------------------------------

/// Refuses what has no flat form: pointers that are not slices, functions, opaque types,
/// untagged unions, a struct of more than 64 fields (a builder tracks them in one word), and
/// `usize` and `isize`, whose width is the target's, so one image would not read on another.
fn check(comptime F: type) void {
    @setEvalBranchQuota(100_000);
    comptime var seen: []const type = &.{};
    checkIn(F, &seen);
}
fn checkIn(comptime F: type, comptime seen: *[]const type) void {
    for (seen.*) |s| if (s == F) return;
    seen.* = seen.* ++ .{F};
    switch (@typeInfo(F)) {
        .bool, .void => {},
        .int => if (F == usize or F == isize) @compileError("Flat lays out integers of a stated width, not " ++ @typeName(F)),
        .float => |f| if (f.bits == 80) @compileError("Flat lays out no f80"),
        .@"enum" => |e| checkIn(e.tag_type, seen),
        .array => |a| checkIn(a.child, seen),
        .optional => |o| checkIn(o.child, seen),
        .pointer => |p| {
            if (p.size != .slice) @compileError("Flat lays out no pointer but a slice: " ++ @typeName(F));
            checkIn(p.child, seen);
        },
        .@"struct" => |s| {
            if (s.field_names.len > 64) @compileError("Flat lays out a struct of at most 64 fields");
            for (s.field_types) |ft| checkIn(ft, seen);
        },
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("Flat lays out a tagged union only: " ++ @typeName(F));
            for (u.field_types) |ft| checkIn(ft, seen);
        },
        else => @compileError("Flat lays out no " ++ @typeName(F)),
    }
}

/// Whether a part has a payload away from where it is used.
inline fn variable(comptime F: type) bool {
    return comptime variableOf(F);
}
fn variableOf(comptime F: type) bool {
    @setEvalBranchQuota(100_000);
    return comptime switch (@typeInfo(F)) {
        .int, .float, .bool, .@"enum", .void => false,
        .array => |a| variable(a.child),
        .optional => |o| variable(o.child),
        .pointer, .@"union" => true,
        .@"struct" => |s| for (s.field_types) |ft| {
            if (variable(ft)) break true;
        } else false,
        else => unreachable,
    };
}

/// The type whose payload a variable part's offset names: an optional's child, else itself.
fn Payload(comptime F: type) type {
    return if (@typeInfo(F) == .optional) @typeInfo(F).optional.child else F;
}
fn optionalNull(comptime F: type, value: F) bool {
    return @typeInfo(F) == .optional and value == null;
}
fn unwrap(comptime F: type, value: F) Payload(F) {
    return if (@typeInfo(F) == .optional) value.? else value;
}

fn Element(comptime F: type) type {
    return switch (@typeInfo(F)) {
        .pointer => |p| p.child,
        .array => |a| a.child,
        else => @compileError("elements are a slice's or an array's"),
    };
}

/// The integer a scalar is stored as: its bytes, little-endian.
fn Repr(comptime F: type) type {
    return switch (@typeInfo(F)) {
        .int => |i| @Int(i.signedness, @sizeOf(F) * 8),
        .float => @Int(.unsigned, @sizeOf(F) * 8),
        .bool => u8,
        .@"enum" => |e| Repr(e.tag_type),
        else => unreachable,
    };
}

inline fn inlineSize(comptime F: type) usize {
    return comptime inlineSizeOf(F);
}
fn inlineSizeOf(comptime F: type) usize {
    @setEvalBranchQuota(100_000);
    if (comptime variable(F)) return 4;
    return comptime switch (@typeInfo(F)) {
        .void => 0,
        .int, .float, .bool, .@"enum" => @sizeOf(Repr(F)),
        .array => |a| a.len * inlineSize(a.child),
        .optional => |o| std.mem.alignForward(usize, std.mem.alignForward(usize, 1, inlineAlign(o.child)) + inlineSize(o.child), inlineAlign(F)),
        .@"struct" => headSize(F),
        else => unreachable,
    };
}

inline fn inlineAlign(comptime F: type) usize {
    return comptime inlineAlignOf(F);
}
fn inlineAlignOf(comptime F: type) usize {
    @setEvalBranchQuota(100_000);
    if (comptime variable(F)) return 4;
    return comptime switch (@typeInfo(F)) {
        .void => 1,
        .int, .float, .bool, .@"enum" => @sizeOf(Repr(F)),
        .array => |a| inlineAlign(a.child),
        .optional => |o| inlineAlign(o.child),
        .@"struct" => headAlign(F),
        else => unreachable,
    };
}

/// A struct's head: each field inline, at its alignment, in declaration order.
inline fn headOffsets(comptime F: type) [@typeInfo(F).@"struct".field_names.len]usize {
    return comptime headOffsetsOf(F);
}
fn headOffsetsOf(comptime F: type) [@typeInfo(F).@"struct".field_names.len]usize {
    @setEvalBranchQuota(100_000);
    return comptime blk: {
        const s = @typeInfo(F).@"struct";
        var offsets: [s.field_names.len]usize = undefined;
        var at: usize = 0;
        for (s.field_types, 0..) |ft, i| {
            at = std.mem.alignForward(usize, at, inlineAlign(ft));
            offsets[i] = at;
            at += inlineSize(ft);
        }
        break :blk offsets;
    };
}
inline fn headAlign(comptime F: type) usize {
    return comptime headAlignOf(F);
}
fn headAlignOf(comptime F: type) usize {
    @setEvalBranchQuota(100_000);
    return comptime blk: {
        var a: usize = 1;
        for (@typeInfo(F).@"struct".field_types) |ft| a = @max(a, inlineAlign(ft));
        break :blk a;
    };
}

/// The fixed part of a payload: a struct's head, a slice's count, an array's elements, a
/// union's tag. A slice's elements and a union's variant follow it.
inline fn headSize(comptime F: type) usize {
    return comptime headSizeOf(F);
}
fn headSizeOf(comptime F: type) usize {
    @setEvalBranchQuota(100_000);
    return comptime switch (@typeInfo(F)) {
        .@"struct" => |s| if (s.field_names.len == 0) 0 else std.mem.alignForward(usize, headOffsets(F)[s.field_names.len - 1] + inlineSize(s.field_types[s.field_names.len - 1]), headAlign(F)),
        .pointer => 4,
        .array => |a| a.len * inlineSize(a.child),
        .@"union" => inlineSize(std.meta.Tag(F)),
        else => unreachable,
    };
}

inline fn payloadAlign(comptime F: type) usize {
    return comptime payloadAlignOf(F);
}
fn payloadAlignOf(comptime F: type) usize {
    @setEvalBranchQuota(100_000);
    return comptime switch (@typeInfo(F)) {
        .@"struct" => headAlign(F),
        .pointer => |p| @max(4, inlineAlign(p.child)),
        .array => |a| inlineAlign(a.child),
        .@"union" => |u| blk: {
            var a = inlineAlign(std.meta.Tag(F));
            for (u.field_types) |ft| a = @max(a, inlineAlign(ft));
            break :blk a;
        },
        else => unreachable,
    };
}

/// Where a slice's or an array's first element lies in its payload.
inline fn elementsOffset(comptime F: type) usize {
    return comptime switch (@typeInfo(F)) {
        .pointer => |p| std.mem.alignForward(usize, 4, inlineAlign(p.child)),
        .array => 0,
        else => unreachable,
    };
}
/// Where a union's variant lies in its payload.
inline fn variantOffset(comptime F: type, comptime V: type) usize {
    return comptime std.mem.alignForward(usize, inlineSize(std.meta.Tag(F)), inlineAlign(V));
}

// Writing -----------------------------------------------------------------------------------

fn writeInt(comptime I: type, out: *[@sizeOf(I)]u8, value: I) void {
    std.mem.writeInt(I, out, value, .little);
}
fn readInt(comptime I: type, at: [*]const u8) I {
    return std.mem.readInt(I, at[0..@sizeOf(I)], .little);
}

fn writeOffset(out: []u8, slot: Pos, target: Pos) void {
    writeInt(u32, out[@intCast(slot)..][0..4], @intCast(target - slot));
}

/// Writes `value` inline at `at`, and a variable part's payload at `cursor`; returns where the
/// payloads end. With no `out`, only measures. Written positions lie below `too_big`: the
/// image was measured first.
fn writeInline(comptime F: type, value: F, out: ?[]u8, at: Pos, cursor: Pos) Pos {
    if (variable(F)) {
        if (optionalNull(F, value)) return cursor;
        const target = aligned(cursor, payloadAlign(Payload(F)));
        if (out) |o| writeOffset(o, at, target);
        return writePayload(Payload(F), unwrap(F, value), out, target);
    }
    const o = out orelse return cursor;
    const i: usize = @intCast(at);
    switch (@typeInfo(F)) {
        .void => {},
        .int => writeInt(Repr(F), o[i..][0..@sizeOf(Repr(F))], value),
        .float => writeInt(Repr(F), o[i..][0..@sizeOf(Repr(F))], @bitCast(value)),
        .bool => o[i] = @intFromBool(value),
        .@"enum" => writeInt(Repr(F), o[i..][0..@sizeOf(Repr(F))], @backingInt(value)),
        .array => |a| for (value, 0..) |item, n| {
            _ = writeInline(a.child, item, o, at + n * inlineSize(a.child), cursor);
        },
        .optional => |opt| if (value) |present| {
            o[i] = 1;
            _ = writeInline(opt.child, present, o, at + std.mem.alignForward(usize, 1, inlineAlign(opt.child)), cursor);
        },
        .@"struct" => |s| inline for (s.field_names, 0..) |name, n| {
            _ = writeInline(s.field_types[n], @field(value, name), o, at + headOffsets(F)[n], cursor);
        },
        else => comptime unreachable,
    }
    return cursor;
}

/// Writes `value`'s payload at `at`, aligned; returns where it and everything after it ends,
/// or `too_big`.
fn writePayload(comptime F: type, value: F, out: ?[]u8, at: Pos) Pos {
    switch (@typeInfo(F)) {
        .@"struct" => |s| {
            var cursor = add(at, headSize(F));
            inline for (s.field_names, 0..) |name, i| cursor = writeInline(s.field_types[i], @field(value, name), out, at + headOffsets(F)[i], cursor);
            return cursor;
        },
        .pointer => |p| {
            const stride = inlineSize(p.child);
            const first = add(at, elementsOffset(F));
            var cursor = add(first, times(value.len, stride));
            if (cursor >= too_big) return too_big;
            if (out) |o| writeInt(u32, o[@intCast(at)..][0..4], @intCast(value.len));
            for (value, 0..) |item, i| {
                cursor = writeInline(p.child, item, out, first + i * stride, cursor);
                if (cursor >= too_big) return too_big;
            }
            return cursor;
        },
        .array => |a| {
            var cursor = add(at, headSize(F));
            for (value, 0..) |item, i| cursor = writeInline(a.child, item, out, at + i * inlineSize(a.child), cursor);
            return cursor;
        },
        .@"union" => |u| {
            _ = writeInline(std.meta.Tag(F), value, out, at, 0);
            switch (value) {
                inline else => |variant, t| {
                    const V = u.field_types[@backingInt(t)];
                    const v_at = at + variantOffset(F, V);
                    return writeInline(V, variant, out, v_at, add(v_at, inlineSize(V)));
                },
            }
        },
        else => comptime unreachable,
    }
}

// Reading -----------------------------------------------------------------------------------

/// Whether a slice of `E` reads as a real slice into the image: plain numbers stored as they lie
/// in memory, so bytes on every target and wider numbers on a little-endian one.
inline fn direct(comptime E: type) bool {
    return comptime switch (@typeInfo(E)) {
        .int => |i| i.bits == @sizeOf(E) * 8 and (little or @sizeOf(E) == 1),
        .float => |f| little and (f.bits == 16 or f.bits == 32 or f.bits == 64),
        else => false,
    };
}

/// What reading a part gives: a fixed part's value, a real slice of plain numbers, an optional's
/// child or null, or a view.
fn Read(comptime F: type) type {
    if (!variable(F)) return F;
    if (@typeInfo(F) == .optional) return ?Read(@typeInfo(F).optional.child);
    if (@typeInfo(F) == .pointer and direct(Element(F))) return []const Element(F);
    return Flat(F).View;
}

fn readInline(comptime F: type, at: [*]const u8) Read(F) {
    if (variable(F)) {
        const offset = readInt(u32, at);
        if (@typeInfo(F) == .optional) {
            if (offset == 0) return null;
            return readPayload(Payload(F), at + offset);
        }
        return readPayload(F, at + offset);
    }
    return switch (@typeInfo(F)) {
        .void => {},
        .int => @intCast(readInt(Repr(F), at)),
        .float => @bitCast(readInt(Repr(F), at)),
        .bool => at[0] != 0,
        .@"enum" => @fromBackingInt(@intCast(readInt(Repr(F), at))),
        .array => |a| blk: {
            var out: F = undefined;
            for (&out, 0..) |*item, i| item.* = readInline(a.child, at + i * inlineSize(a.child));
            break :blk out;
        },
        .optional => |o| if (at[0] == 0) null else readInline(o.child, at + std.mem.alignForward(usize, 1, inlineAlign(o.child))),
        .@"struct" => |s| blk: {
            var out: F = undefined;
            inline for (s.field_names, 0..) |name, i| @field(out, name) = readInline(s.field_types[i], at + headOffsets(F)[i]);
            break :blk out;
        },
        else => unreachable,
    };
}

fn readPayload(comptime F: type, at: [*]const u8) Read(F) {
    if (@typeInfo(F) == .pointer and direct(Element(F))) {
        const E = Element(F);
        const items: [*]const E = @ptrCast(@alignCast(at + elementsOffset(F))); // safe: elements lie aligned in an aligned image, as written or verified
        return items[0..readInt(u32, at)];
    }
    return .{ .ptr = at };
}

fn materializeInline(comptime F: type, at: [*]const u8, gpa: std.mem.Allocator) error{OutOfMemory}!F {
    if (!variable(F)) return readInline(F, at);
    const offset = readInt(u32, at);
    if (@typeInfo(F) == .optional) {
        if (offset == 0) return null;
        return try materializePayload(Payload(F), at + offset, gpa);
    }
    return materializePayload(F, at + offset, gpa);
}

fn materializePayload(comptime F: type, at: [*]const u8, gpa: std.mem.Allocator) error{OutOfMemory}!F {
    switch (@typeInfo(F)) {
        .@"struct" => |s| {
            var out: F = undefined;
            inline for (s.field_names, 0..) |name, i| @field(out, name) = try materializeInline(s.field_types[i], at + headOffsets(F)[i], gpa);
            return out;
        },
        .pointer => |p| {
            const items = try gpa.alloc(p.child, readInt(u32, at));
            for (items, 0..) |*item, i| item.* = try materializeInline(p.child, at + elementsOffset(F) + i * inlineSize(p.child), gpa);
            return items;
        },
        .array => |a| {
            var out: F = undefined;
            for (&out, 0..) |*item, i| item.* = try materializeInline(a.child, at + i * inlineSize(a.child), gpa);
            return out;
        },
        .@"union" => |u| {
            const t = readInline(std.meta.Tag(F), at);
            switch (t) {
                inline else => |known| {
                    const V = u.field_types[@backingInt(known)];
                    return @unionInit(F, @tagName(known), try materializeInline(V, at + variantOffset(F, V), gpa));
                },
            }
        },
        else => unreachable,
    }
}

// Verifying ---------------------------------------------------------------------------------

const Checker = struct {
    bytes: []const u8,
    limits: Limits,
    visited: *usize,

    fn count(c: *const Checker, n: usize) VerifyError!void {
        const total = std.math.add(usize, c.visited.*, n) catch return error.LimitExceeded;
        try c.limits.items.check(total);
        c.visited.* = total;
    }
    fn room(c: *const Checker, at: usize, n: usize) VerifyError!void {
        if (at > c.bytes.len or n > c.bytes.len - at) return error.Truncated;
    }

    /// Checks a part's inline bytes at `at`, which its container found in bounds, and a variable
    /// part's payload.
    fn inlinePart(c: *const Checker, comptime F: type, at: usize, depth: usize) VerifyError!void {
        if (variable(F)) {
            const offset = readInt(u32, c.bytes.ptr + at);
            if (offset == 0) return if (@typeInfo(F) == .optional) {} else error.BadOffset;
            return c.payload(Payload(F), std.math.add(usize, at, offset) catch return error.Truncated, depth + 1);
        }
        switch (@typeInfo(F)) {
            .void, .float => {},
            .int => if (std.math.cast(F, readInt(Repr(F), c.bytes.ptr + at)) == null) return error.BadValue,
            .bool => if (c.bytes[at] > 1) return error.BadValue,
            .@"enum" => |e| {
                const raw = readInt(Repr(F), c.bytes.ptr + at);
                if (e.mode == .nonexhaustive) {
                    if (std.math.cast(e.tag_type, raw) == null) return error.BadValue;
                    return;
                }
                inline for (e.field_values) |known| {
                    if (raw == known) return;
                }
                return error.BadValue;
            },
            .array => |a| for (0..a.len) |i| try c.inlinePart(a.child, at + i * inlineSize(a.child), depth),
            .optional => |o| switch (c.bytes[at]) {
                0 => {},
                1 => try c.inlinePart(o.child, at + std.mem.alignForward(usize, 1, inlineAlign(o.child)), depth),
                else => return error.BadValue,
            },
            .@"struct" => |s| inline for (s.field_types, 0..) |ft, i| try c.inlinePart(ft, at + headOffsets(F)[i], depth),
            else => unreachable,
        }
    }

    fn payload(c: *const Checker, comptime F: type, at: usize, depth: usize) VerifyError!void {
        try c.limits.depth.check(depth);
        try c.count(1);
        if (at % payloadAlign(F) != 0) return error.Misaligned;
        try c.room(at, headSize(F));
        switch (@typeInfo(F)) {
            .@"struct" => |s| inline for (s.field_types, 0..) |ft, i| try c.inlinePart(ft, at + headOffsets(F)[i], depth),
            .array => |a| for (0..a.len) |i| try c.inlinePart(a.child, at + i * inlineSize(a.child), depth),
            .pointer => |p| {
                const n: usize = readInt(u32, c.bytes.ptr + at);
                const first = at + elementsOffset(F);
                const stride = inlineSize(p.child);
                if (stride != 0) {
                    const total = std.math.mul(usize, n, stride) catch return error.Truncated;
                    try c.room(first, total);
                }
                try c.count(n);
                if (!plain(p.child)) for (0..n) |i| try c.inlinePart(p.child, first + i * stride, depth);
            },
            .@"union" => |u| {
                const Tag = std.meta.Tag(F);
                try c.inlinePart(Tag, at, depth);
                const t = readInline(Tag, c.bytes.ptr + at);
                switch (t) {
                    inline else => |known| {
                        const V = u.field_types[@backingInt(known)];
                        try c.room(at + variantOffset(F, V), inlineSize(V));
                        try c.inlinePart(V, at + variantOffset(F, V), depth);
                    },
                }
            },
            else => unreachable,
        }
    }
};

/// Whether every bit pattern of `E`'s bytes is a valid `E`, so a slice of it needs no walk.
inline fn plain(comptime E: type) bool {
    return comptime switch (@typeInfo(E)) {
        .int => |i| i.bits == @sizeOf(E) * 8,
        .float, .void => true,
        else => false,
    };
}
