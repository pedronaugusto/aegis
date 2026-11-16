//! A hand-written intrusive free list over slots on bump memory, paired with the indexed
//! `SlotPool`. The hand-written side keeps the same required checks: a handle in range in every
//! build, and in Debug and ReleaseSafe a slot freed twice.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");
const region = @import("region.zig");

const checked = builtin.optimize == .debug or builtin.optimize == .safe;
const none = std.math.maxInt(u32);
const Tag = struct {};

pub const Slots = a.handle.SlotPool(u64, Tag, .{});
pub const DirectSlot = struct { value: u64, next: u32, live: if (checked) bool else void };
pub const Direct = struct { region: region.Direct, slots: []DirectSlot = &.{}, free_head: u32 = none, used: u32 = 0 };

pub fn Pool(comptime wrapped: bool) type {
    return if (wrapped) Slots else Direct;
}

/// The newest freed slot, else one more on the region.
inline fn take(p: *Direct) error{ OutOfMemory, LimitExceeded }!u32 {
    const i = p.free_head;
    if (i == none) return grow(p);
    const slot = &p.slots[i];
    p.free_head = slot.next;
    if (checked) slot.live = true;
    p.used += 1;
    return i;
}

fn grow(p: *Direct) error{ OutOfMemory, LimitExceeded }!u32 {
    const i = try push(p);
    if (checked) p.slots[i].live = true;
    p.used += 1;
    return i;
}

/// One more slot after the slots, uninitialized, and its position.
fn push(p: *Direct) error{ OutOfMemory, LimitExceeded }!u32 {
    const i = p.slots.len;
    if (i == none) return error.LimitExceeded;
    // The slots as they stand, then one more slot's bytes after them.
    const slots = p.slots;
    const at = try region.bump(&p.region, @sizeOf(DirectSlot), @alignOf(DirectSlot));
    // The same required check as a region's extend: in the builds that check safety, the slots end
    // at the region's top.
    if (std.debug.runtime_safety) a.assert.invariant(slots.len == 0 or at == @intFromPtr(std.mem.sliceAsBytes(slots).ptr) - @intFromPtr(p.region.memory.ptr) + slots.len * @sizeOf(DirectSlot), "a region extends only the items at its top");
    const first: [*]DirectSlot = if (slots.len == 0) @ptrCast(@alignCast(p.region.memory[at..at].ptr)) else slots.ptr; // safe: bump returned a committed slot's bytes, aligned, after the slots
    p.slots = first[0 .. slots.len + 1];
    return @intCast(i); // safe: fewer than `none` slots, a u32
}

/// The new value's index, or `none` when the memory ran out.
pub fn alloc(comptime wrapped: bool, p: *Pool(wrapped), value: u64) u32 {
    if (wrapped) return (p.alloc(value) catch return none).raw();
    const i = take(p) catch return none;
    p.slots[i].value = value;
    return i;
}

pub fn free(comptime wrapped: bool, p: *Pool(wrapped), raw: u32) void {
    if (wrapped) return p.free(@fromBackingInt(raw));
    a.assert.invariant(raw < p.slots.len, "slot handle out of range");
    const slot = &p.slots[raw];
    if (checked) {
        if (!slot.live) @panic("slot freed twice");
        slot.live = false;
    }
    slot.next = p.free_head;
    p.free_head = raw;
    p.used -= 1;
}

pub fn get(comptime wrapped: bool, p: *const Pool(wrapped), raw: u32) u64 {
    if (wrapped) return p.get(@fromBackingInt(raw)).*;
    a.assert.invariant(raw < p.slots.len, "slot handle out of range");
    return p.slots[raw].value;
}

pub const Runs = a.handle.RunPool(u64, Tag);

/// A run's items: in the pool, checked in every build, then the base plus the start.
pub fn slice(comptime wrapped: bool, p: *const Runs, start: u32, len: u32) [*]u64 {
    if (wrapped) return p.slice(.{ .start = @fromBackingInt(start), .len = len }).ptr;
    a.assert.invariant(len <= p.aegis_items.len and start <= p.aegis_items.len - len, "run outside its pool");
    return p.aegis_items.ptr + start;
}
