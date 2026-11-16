//! Hand-written bump memory paired with regions, their marks and their tails. The hand-written
//! side has the same fields and the same required checks: the limit, the overflow of a length,
//! and in Debug and ReleaseSafe the open tail and the order of marks.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");

const checked = builtin.optimize == .debug or builtin.optimize == .safe;

pub const Region = a.Region;
pub const Mark = Region.Mark;
pub const Tail = Region.Tail(u64);

pub const DirectState = if (checked) struct { serial: u64 = 0, open: u64 = 0, tail: u64 = 0 } else struct {};
pub const Direct = struct { memory: []u8, top: usize, reservation_len: usize, state: DirectState = .{} };
pub const DirectMark = struct { top: usize, id: if (checked) u64 else void, parent: if (checked) u64 else void };
pub const DirectTail = struct { region: *Direct, start: usize, id: if (checked) u64 else void };

pub fn Reg(comptime wrapped: bool) type {
    return if (wrapped) Region else Direct;
}
pub fn Mk(comptime wrapped: bool) type {
    return if (wrapped) Mark else DirectMark;
}
pub fn Tl(comptime wrapped: bool) type {
    return if (wrapped) Tail else DirectTail;
}

/// The hand-written commit: whole pages, in steps that double with the region from 64 KiB up to
/// 4 MiB, never past the reservation; the limit is checked first. A buffer is all committed.
pub noinline fn grow(r: *Direct, needed: usize) error{ OutOfMemory, LimitExceeded }!void {
    @branchHint(.unlikely);
    if (a.Region.can_reserve and needed <= r.reservation_len) return growReserved(r, needed);
    return error.LimitExceeded;
}

fn growReserved(r: *Direct, needed: usize) error{ OutOfMemory, LimitExceeded }!void {
    const page = std.heap.pageSize();
    const step = std.math.clamp(r.memory.len, 64 * 1024, 4 * 1024 * 1024);
    const wanted = @max(needed, r.memory.len +| step);
    const next = @min(r.reservation_len, std.mem.alignForward(usize, @min(wanted, std.math.maxInt(usize) - page), page));
    try protect(r.memory.ptr + r.memory.len, next - r.memory.len);
    r.memory = r.memory.ptr[0..next];
}

fn protect(start: [*]u8, len: usize) error{OutOfMemory}!void {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        var base: ?*anyopaque = start;
        var size: windows.SIZE_T = len;
        const status = windows.ntdll.NtAllocateVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&base), 0, &size, .{ .COMMIT = true }, .{ .READWRITE = true }); // safe: NtAllocateVirtualMemory reads the base through a PVOID pointer
        if (status != .SUCCESS) return error.OutOfMemory;
        return;
    }
    const pages: [*]align(std.heap.page_size_min) u8 = @alignCast(start); // safe: committed ends on a page inside the reservation
    switch (std.posix.errno(std.posix.system.mprotect(@ptrCast(pages), len, .{ .READ = true, .WRITE = true }))) { // safe: the system call takes the same page address untyped
        .SUCCESS => {},
        else => return error.OutOfMemory,
    }
}

pub inline fn bump(r: *Direct, len: usize, alignment: usize) error{ OutOfMemory, LimitExceeded }!usize {
    single(r);
    return place(r, len, alignment);
}

inline fn single(r: *const Direct) void {
    if (checked and r.state.tail != 0) @panic("region pushed while a tail is open");
}

inline fn place(r: *Direct, len: usize, alignment: usize) error{ OutOfMemory, LimitExceeded }!usize {
    const base = @intFromPtr(r.memory.ptr);
    const start = std.mem.alignForward(usize, base + r.top, alignment) - base;
    const next = std.math.add(usize, start, len) catch return error.LimitExceeded;
    if (next > r.memory.len) try grow(r, next);
    r.top = next;
    return start;
}

pub fn create(comptime wrapped: bool, r: *Reg(wrapped)) ?*u64 {
    if (wrapped) return r.create(u64) catch null;
    const at = bump(r, @sizeOf(u64), @alignOf(u64)) catch return null;
    const item: *u64 = @ptrCast(@alignCast(r.memory[at..][0..@sizeOf(u64)])); // safe: bump returned committed bytes aligned for u64
    return item;
}

pub fn push(comptime wrapped: bool, r: *Reg(wrapped), n: usize) ?[*]u32 {
    if (wrapped) return (r.push(u32, n) catch return null).ptr;
    return pushDirect(r, n) catch return null;
}

/// `n` items pushed on the hand-written region, uninitialized.
inline fn pushDirect(r: *Direct, n: usize) error{ OutOfMemory, LimitExceeded }![*]u32 {
    single(r);
    const len = std.math.mul(usize, n, @sizeOf(u32)) catch return error.LimitExceeded;
    const at = try place(r, len, @alignOf(u32));
    const items: [*]u32 = @ptrCast(@alignCast(r.memory[at..][0..len])); // safe: place returned committed bytes aligned for u32
    return items;
}

pub fn append(comptime wrapped: bool, t: *Tl(wrapped), value: u64) ?*u64 {
    if (wrapped) return t.append(value) catch null;
    const r = t.region;
    const at = extend(t, @sizeOf(u64)) catch return null;
    const item: *u64 = @ptrCast(@alignCast(r.memory[at..][0..@sizeOf(u64)])); // safe: the tail's next item, committed and aligned
    item.* = value;
    return item;
}

/// Moves the tail's end past `bytes` more, and returns where they start.
inline fn extend(t: *DirectTail, bytes: usize) error{ OutOfMemory, LimitExceeded }!usize {
    const r = t.region;
    if (checked and r.state.tail != t.id) @panic("region tail used after it was sealed");
    const at = r.top;
    const next = std.math.add(usize, at, bytes) catch return error.LimitExceeded;
    if (next > r.memory.len) try grow(r, next);
    r.top = next;
    return at;
}

pub fn mark(comptime wrapped: bool, r: *Reg(wrapped), out: *Mk(wrapped)) void {
    if (wrapped) {
        out.* = r.mark();
        return;
    }
    if (!checked) {
        out.* = .{ .top = r.top, .id = {}, .parent = {} };
        return;
    }
    r.state.serial += 1;
    const m: DirectMark = .{ .top = r.top, .id = r.state.serial, .parent = r.state.open };
    r.state.open = r.state.serial;
    out.* = m;
}

pub fn release(comptime wrapped: bool, r: *Reg(wrapped), m: *const Mk(wrapped)) void {
    if (wrapped) return r.release(m.*);
    const taken = m.*;
    if (checked) {
        if (r.state.tail != 0) @panic("region released with a tail open");
        if (r.state.open != taken.id or taken.top > r.top) @panic("region mark released twice, out of order, or after an outer release");
        r.state.open = taken.parent;
    }
    r.top = taken.top;
}

/// A scratch scope's whole life: mark, push a buffer, fill it, read it back, release.
pub fn scratch(comptime wrapped: bool, r: *Reg(wrapped), n: usize) u32 {
    var m: Mk(wrapped) = undefined;
    mark(wrapped, r, &m);
    defer release(wrapped, r, &m);
    const items = push(wrapped, r, n) orelse return 0;
    var sum: u32 = 0;
    for (items[0..n], 0..) |*item, i| {
        item.* = @truncate(i);
        sum +%= item.*;
    }
    return sum;
}
