//! Memory whose live part never moves: a reservation of address space or the caller's buffer,
//! a bump top, marks released at once, and at most one growing tail at the top.
const Region = @This();
const builtin = @import("builtin");
const std = @import("std");
const assert = @import("assert.zig");
const bounded = @import("bounded.zig");
const pages = @import("pages.zig");
const units = @import("units.zig");
const view = @import("view.zig");

/// The order and tail checks follow Zig's runtime safety: on in Debug and ReleaseSafe, absent from
/// ReleaseFast and ReleaseSmall.
const checked = builtin.optimize == .debug or builtin.optimize == .safe;

/// Whether this target reserves address space. Elsewhere (wasm, freestanding) a region is a
/// caller's buffer, `fixed`, with the same type and operations.
pub const can_reserve = builtin.os.tag == .windows or builtin.os.tag == .linux or builtin.os.tag.isDarwin() or builtin.os.tag.isBSD();

/// Commits grow by at least this much, doubling with the region up to `max_step`.
const min_step = 64 * 1024;
const max_step = 4 * 1024 * 1024;

/// Private: the committed bytes, whole pages from the reservation's start; the caller's whole
/// buffer, for a fixed region. Every position below is an offset into it.
memory: []u8,
/// Private: one past the live memory.
top: usize,
/// Private: the reservation's length, a whole number of pages; zero for a fixed region, which has
/// none.
reservation_len: usize,
/// Private: checked builds' record of the open marks and the open tail.
state: State = .{},

const State = if (checked) struct {
    /// The last identity given to a mark or a tail.
    serial: u64 = 0,
    /// The newest open mark, or zero.
    open: u64 = 0,
    /// The open tail, or zero.
    tail: u64 = 0,
} else struct {};

/// Past the limit or a fixed region's end is `LimitExceeded`; a commit the system refuses is
/// `OutOfMemory`, with the region unchanged.
pub const Error = error{ OutOfMemory, LimitExceeded };

/// Test builds only: makes the next commits fail as a refusing system does.
pub const testing = if (builtin.is_test) struct {
    pub var refuse_commit = false;
} else struct {};

/// Reserves `limit` bytes of address space, rounded up to whole pages, and commits nothing yet.
/// The reservation is the limit: the region never holds more.
pub fn reserve(limit: bounded.Limit(usize)) error{OutOfMemory}!Region {
    if (!can_reserve) @compileError("Region.reserve: this target has no virtual memory to reserve; use Region.fixed");
    const page = std.heap.pageSize();
    if (limit.aegis_maximum > std.math.maxInt(usize) - page) return error.OutOfMemory;
    const length = std.mem.alignForward(usize, @max(limit.aegis_maximum, 1), page);
    // Nothing committed yet: the reservation's start, with no bytes. (A slice cut with
    // comptime-known bounds would be a zero-length array's, which has no address.)
    var none: []u8 = try pages.reserve(length);
    none.len = 0;
    return .{ .memory = none, .top = 0, .reservation_len = length };
}

/// The caller's memory, which the region never commits, moves or frees: wasm, freestanding, or a
/// bound known in advance. Past its end is `LimitExceeded`.
pub fn fixed(buffer: []u8) Region {
    return .{ .memory = buffer, .top = 0, .reservation_len = 0 };
}

/// Returns a reservation to the system; a fixed region forgets its buffer.
pub fn deinit(r: *Region) void {
    if (can_reserve and r.reservation_len != 0) pages.release(r.memory, r.reservation_len);
    r.* = undefined;
}

/// `n` items of `T`, aligned and uninitialized. They never move, and stay valid until a
/// `release` passes below them or the region ends.
pub inline fn push(r: *Region, comptime T: type, n: usize) Error![]T {
    r.single();
    const len = std.math.mul(usize, n, @sizeOf(T)) catch return error.LimitExceeded;
    const start = try r.bump(len, @alignOf(T));
    return view.items(T, r.memory[start..][0..len], n);
}

/// One `T`, aligned and uninitialized.
pub inline fn create(r: *Region, comptime T: type) Error!*T {
    return &(try r.push(T, 1))[0];
}

/// `items`, the newest push at the top, grown in place by `n` uninitialized items: they never
/// move. An empty `items` is a fresh push. Items that do not end at the top stop the program in
/// the builds that check safety, as a slice past its end does.
pub fn extend(r: *Region, comptime T: type, items: []T, n: usize) Error![]T {
    r.single();
    const more = std.math.mul(usize, n, @sizeOf(T)) catch return error.LimitExceeded;
    // Aligned as a push is, the new items start where `items` end when they end at the top.
    const at = try r.bump(more, @alignOf(T));
    if (std.debug.runtime_safety) assert.invariant(items.len == 0 or at == r.offset(std.mem.sliceAsBytes(items)) + items.len * @sizeOf(T), "a region extends only the items at its top");
    // Where the items start: fresh at `at`, or where they already are.
    const first = if (items.len == 0) view.items(T, r.memory[at..at], 0) else items;
    return view.grown(T, first, items.len + n);
}

/// The first `n` of `items`, the newest push at the top, with the rest given back to the region.
/// Items that do not end at the top, or an `n` past them, stop the program in every build.
pub fn truncate(r: *Region, comptime T: type, items: []T, n: usize) []T {
    if (items.len == 0) return items;
    const start = r.offset(std.mem.sliceAsBytes(items));
    assert.invariant(start + items.len * @sizeOf(T) == r.top and n <= items.len, "a region truncates only the items at its top, within them");
    r.top = start + n * @sizeOf(T);
    return items[0..n];
}

/// A copy of `items`.
pub fn dupe(r: *Region, comptime T: type, items: []const T) Error![]T {
    const copy = try r.push(T, items.len);
    @memcpy(copy, items);
    return copy;
}

/// The top, to release back to. Marks nest: the newest open mark is released first.
pub const Mark = struct {
    /// Private: the top to go back to.
    top: usize,
    /// Private: checked builds' identity of this mark and of the mark open when it was taken.
    id: if (checked) u64 else void,
    parent: if (checked) u64 else void,
};

pub fn mark(r: *Region) Mark {
    if (!checked) return .{ .top = r.top, .id = {}, .parent = {} };
    r.state.serial += 1;
    defer r.state.open = r.state.serial;
    return .{ .top = r.top, .id = r.state.serial, .parent = r.state.open };
}

/// Frees everything pushed since `m`: one store in ReleaseFast and ReleaseSmall. Debug and
/// ReleaseSafe stop the program for a mark that is not the newest open one (released twice, or
/// already freed by an outer release) and for a tail still open.
pub fn release(r: *Region, m: Mark) void {
    if (checked) {
        if (r.state.tail != 0) @panic("region released with a tail open");
        if (r.state.open != m.id or m.top > r.top) @panic("region mark released twice, out of order, or after an outer release");
        r.state.open = m.parent;
    }
    r.top = m.top;
}

/// Decommits whole pages above the top; the reservation stays. A fixed region keeps its buffer.
pub fn trim(r: *Region) void {
    if (can_reserve and r.reservation_len != 0) r.trimReserved();
}

fn trimReserved(r: *Region) void {
    const keep = std.mem.alignForward(usize, r.top, std.heap.pageSize());
    if (keep >= r.memory.len) return;
    if (pages.decommit(r.memory, keep)) r.memory = r.memory[0..keep];
}

/// The bytes below the top.
pub fn used(r: *const Region) units.Bytes(usize) {
    return .fromRaw(r.top);
}

/// The bytes the system has committed: the whole buffer, for a fixed region.
pub fn committed(r: *const Region) units.Bytes(usize) {
    return .fromRaw(r.memory.len);
}

/// The bytes the region may hold: its reservation, or its buffer's length.
pub fn capacity(r: *const Region) units.Bytes(usize) {
    return .fromRaw(@max(r.reservation_len, r.memory.len));
}

/// The live bytes: everything pushed and not released, from the region's first byte.
pub fn live(r: *const Region) []u8 {
    return r.memory[0..r.top];
}

/// The region's one growing value, at the top: its items never move as it grows, and nothing else
/// is pushed on the region until it is sealed (stopped in Debug and ReleaseSafe).
pub fn tail(r: *Region, comptime T: type) Error!Tail(T) {
    r.single();
    const start = try r.bump(0, @alignOf(T));
    if (!checked) return .{ .region = r, .start = start, .id = {} };
    r.state.serial += 1;
    r.state.tail = r.state.serial;
    return .{ .region = r, .start = start, .id = r.state.serial };
}

pub fn Tail(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: the region it grows on.
        region: *Region,
        /// Private: the offset of the first item.
        start: usize,
        /// Private: checked builds' identity of the tail.
        id: if (checked) u64 else void,

        fn open(t: *const Self) void {
            if (checked and t.region.state.tail != t.id) @panic("region tail used after it was sealed");
        }
        /// Room for `n` more items at the end, uninitialized.
        pub inline fn addMany(t: *Self, n: usize) Error![]T {
            t.open();
            const r = t.region;
            const bytes = std.math.mul(usize, n, @sizeOf(T)) catch return error.LimitExceeded;
            const at = r.top;
            const next = std.math.add(usize, at, bytes) catch return error.LimitExceeded;
            if (next > r.memory.len) try r.commit(next);
            r.top = next;
            return view.items(T, r.memory[at..][0..bytes], n);
        }
        /// The pointer stays valid as the tail grows.
        pub inline fn append(t: *Self, value: T) Error!*T {
            const item = &(try t.addMany(1))[0];
            item.* = value;
            return item;
        }
        pub fn appendSlice(t: *Self, values: []const T) Error![]T {
            const room = try t.addMany(values.len);
            @memcpy(room, values);
            return room;
        }
        pub fn len(t: *const Self) usize {
            t.open();
            return (t.region.top - t.start) / @sizeOf(T);
        }
        pub fn items(t: *const Self) []T {
            return view.items(T, t.region.memory[t.start..t.region.top], t.len());
        }
        /// Drops the items from `n` on; `n` is at most `len`, in every build.
        pub fn shrink(t: *Self, n: usize) void {
            if (n > t.len()) @panic("region tail shrunk past its length");
            t.region.top = t.start + n * @sizeOf(T);
        }
        /// Closes the tail: its items stay where they are, and pushes resume above them.
        pub fn seal(t: *Self) []T {
            const sealed = t.items();
            if (checked) t.region.state.tail = 0;
            return sealed;
        }
    };
}

/// A bump allocator over the region. `resize` and `remap` succeed in place for the top
/// allocation only; `free` gives back the top allocation and is otherwise a no-op until a
/// `release`. Two lists growing on one region copy, as on an arena: give each its own region,
/// or a tail.
pub fn allocator(r: *Region) std.mem.Allocator {
    return .{ .ptr = r, .vtable = &vtable };
}

const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    const r = view.context(Region, context);
    r.single();
    const start = r.bump(len, alignment.toByteUnits()) catch return null;
    return r.memory[start..].ptr;
}

fn resize(context: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    const r = view.context(Region, context);
    const start = r.offset(memory);
    if (start + memory.len != r.top) return new_len <= memory.len;
    r.single();
    const next = std.math.add(usize, start, new_len) catch return false;
    if (next > r.memory.len) r.commit(next) catch return false;
    r.top = next;
    return true;
}

fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
}

fn free(context: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    const r = view.context(Region, context);
    const start = r.offset(memory);
    if (start + memory.len != r.top) return;
    r.single();
    r.top = start;
}

/// Stops a second grower while a tail is open, in Debug and ReleaseSafe.
inline fn single(r: *const Region) void {
    if (checked and r.state.tail != 0) @panic("region pushed while a tail is open");
}

/// Where `memory`, an allocation the region made, starts.
inline fn offset(r: *const Region, memory: []u8) usize {
    return @intFromPtr(memory.ptr) - @intFromPtr(r.memory.ptr);
}

/// Moves the top past `len` bytes aligned to `alignment`, and returns where they start.
inline fn bump(r: *Region, len: usize, alignment: usize) Error!usize {
    const base = @intFromPtr(r.memory.ptr);
    const start = std.mem.alignForward(usize, base + r.top, alignment) - base;
    const next = std.math.add(usize, start, len) catch return error.LimitExceeded;
    if (next > r.memory.len) try r.commit(next);
    r.top = next;
    return start;
}

/// Commits at least up to `needed`, past the committed bytes, or fails with the region unchanged.
/// A fixed region's whole buffer is committed and its reservation length is zero, so it only ever
/// reaches its end here.
noinline fn commit(r: *Region, needed: usize) Error!void {
    @branchHint(.unlikely);
    if (can_reserve and needed <= r.reservation_len) return r.commitReserved(needed);
    return error.LimitExceeded;
}

/// Pages are committed whole, from the committed end (on a page) to a page at or past `needed`,
/// never past the reservation, so the one compare of a push also holds the limit.
fn commitReserved(r: *Region, needed: usize) Error!void {
    const page = std.heap.pageSize();
    const step = std.math.clamp(r.memory.len, min_step, max_step);
    const wanted = @max(needed, r.memory.len +| step);
    const next = @min(r.reservation_len, std.mem.alignForward(usize, @min(wanted, std.math.maxInt(usize) - page), page));
    if (builtin.is_test and testing.refuse_commit) return error.OutOfMemory;
    try pages.commit(r.memory, r.reservation_len, next);
    r.memory = pages.grown(r.memory, next);
}
