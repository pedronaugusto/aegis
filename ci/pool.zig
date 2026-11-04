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
pub const Direct = struct { region: region.Direct, slots: [*]DirectSlot, count: u32 = 0, free_head: u32 = none, used: u32 = 0 };

pub fn Pool(comptime wrapped: bool) type {
    return if (wrapped) Slots else Direct;
}

fn grow(p: *Direct) error{ OutOfMemory, LimitExceeded }!u32 {
    if (p.count == none) return error.LimitExceeded;
    const slot: *DirectSlot = @ptrFromInt(try region.bump(&p.region, @sizeOf(DirectSlot), @alignOf(DirectSlot))); // safe: bump returned a committed slot's bytes, aligned
    if (checked) slot.live = true;
    p.count += 1;
    p.used += 1;
    return p.count - 1;
}

/// The new value's index, or `none` when the memory ran out.
pub fn alloc(comptime wrapped: bool, p: *Pool(wrapped), value: u64) u32 {
    if (wrapped) return (p.alloc(value) catch return none).raw();
    const i = p.free_head;
    const taken = if (i == none) grow(p) catch return none else taken: {
        const slot = &p.slots[i];
        p.free_head = slot.next;
        if (checked) slot.live = true;
        p.used += 1;
        break :taken i;
    };
    p.slots[taken].value = value;
    return taken;
}

pub fn free(comptime wrapped: bool, p: *Pool(wrapped), raw: u32) void {
    if (wrapped) return p.free(@fromBackingInt(raw));
    a.assert.invariant(raw < p.count, "slot handle out of range");
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
    a.assert.invariant(raw < p.count, "slot handle out of range");
    return p.slots[raw].value;
}

pub const Runs = a.handle.RunPool(u64, Tag);

/// A run's items: in the pool, checked in every build, then the base plus the start.
pub fn slice(comptime wrapped: bool, p: *const Runs, start: u32, len: u32) [*]u64 {
    if (wrapped) return p.slice(.{ .start = @fromBackingInt(start), .len = len }).ptr;
    a.assert.invariant(len <= p.end and start <= p.end - len, "run outside its pool");
    return p.items + start;
}
