//! Necessary handwritten operations paired with scope tables, scopes and references.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");

const checked = builtin.optimize == .debug or builtin.optimize == .safe;
const none = std.math.maxInt(usize);
const Brand = struct {};

pub const Table = a.scope.Table(Brand);
pub const Scope = Table.Scope;
pub const Ref = a.scope.Ref(Brand, *u64);
pub const SliceRef = a.scope.Ref(Brand, []u8);

/// The hand-written records: a generation per slot, a free list through the slots, and what a scope and
/// a reference carry. Outside Debug and ReleaseSafe they are empty and a reference is a bare pointer.
pub const DirectSlot = if (checked) struct { generation: std.atomic.Value(u64) = .init(1), next: usize = none } else struct {};
pub const DirectTable = if (checked) struct { slots: []DirectSlot, free_head: usize, used_up: usize, open_count: usize } else struct {};
pub const DirectScope = if (checked) struct { table: *DirectTable, index: usize, generation: u64 } else struct {};
pub const DirectRef = if (checked) struct { ptr: *u64, slot: *const DirectSlot, generation: u64 } else struct { ptr: *u64 };
pub const DirectSliceRef = if (checked) struct { ptr: []u8, slot: *const DirectSlot, generation: u64 } else struct { ptr: []u8 };

pub fn Tab(comptime wrapped: bool) type {
    return if (wrapped) Table else DirectTable;
}
pub fn Sco(comptime wrapped: bool) type {
    return if (wrapped) Scope else DirectScope;
}
pub fn Reference(comptime wrapped: bool) type {
    return if (wrapped) Ref else DirectRef;
}
pub fn Sliced(comptime wrapped: bool) type {
    return if (wrapped) SliceRef else DirectSliceRef;
}

pub fn get(comptime wrapped: bool, reference: *const Reference(wrapped)) *u64 {
    if (wrapped) return reference.get();
    if (checked and reference.slot.generation.load(.monotonic) != reference.generation) @panic("scope reference used after its scope ended");
    return reference.ptr;
}

pub fn getSlice(comptime wrapped: bool, reference: *const Sliced(wrapped)) []u8 {
    if (wrapped) return reference.get();
    if (checked and reference.slot.generation.load(.monotonic) != reference.generation) @panic("scope reference used after its scope ended");
    return reference.ptr;
}

pub fn make(comptime wrapped: bool, scope: *const Sco(wrapped), pointer: *u64, out: *Reference(wrapped)) void {
    if (wrapped) {
        out.* = scope.ref(pointer);
        return;
    }
    if (checked) {
        const table = scope.table;
        const index = scope.index;
        const generation = scope.generation;
        const record = &table.slots[index];
        if (record.generation.load(.monotonic) != generation) @panic("scope used after it ended");
        out.* = .{ .ptr = pointer, .slot = record, .generation = generation };
    } else out.* = .{ .ptr = pointer };
}

pub fn reborrow(comptime wrapped: bool, scope: *const Sco(wrapped), source: *const Reference(wrapped), out: *Reference(wrapped)) void {
    if (wrapped) {
        out.* = scope.reborrow(source.*);
        return;
    }
    const mine = scope.*;
    const held = source.*;
    make(false, &mine, get(false, &held), out);
}

fn openDirect(table: *DirectTable) error{ Full, Exhausted }!DirectScope {
    if (!checked) return .{};
    const index = table.free_head;
    if (index == none) return if (table.slots.len != 0 and table.used_up == table.slots.len) error.Exhausted else error.Full;
    const opened = &table.slots[index];
    table.free_head = opened.next;
    table.open_count += 1;
    return .{ .table = table, .index = index, .generation = opened.generation.load(.monotonic) };
}

pub fn open(comptime wrapped: bool, table: *Tab(wrapped), out: *Sco(wrapped)) bool {
    out.* = (if (wrapped) table.open() else openDirect(table)) catch return false;
    return true;
}

pub fn end(comptime wrapped: bool, scope: *const Sco(wrapped)) void {
    if (wrapped) return scope.end();
    if (!checked) return;
    const table = scope.table;
    const index = scope.index;
    const generation = scope.generation;
    const ending = &table.slots[index];
    if (ending.generation.load(.monotonic) != generation) @panic("scope ended twice");
    const next_generation = generation + 1;
    ending.generation.store(next_generation, .monotonic);
    table.open_count -= 1;
    if (next_generation == std.math.maxInt(u64)) {
        table.used_up += 1;
    } else {
        ending.next = table.free_head;
        table.free_head = index;
    }
}

/// A request's whole life: open a scope, make a reference into memory it vouches for, use it, end the scope.
pub fn cycle(comptime wrapped: bool, table: *Tab(wrapped), pointer: *u64) u64 {
    var scope: Sco(wrapped) = undefined;
    if (!open(wrapped, table, &scope)) return 0;
    var reference: Reference(wrapped) = undefined;
    make(wrapped, &scope, pointer, &reference);
    pointer.* +%= 1;
    const seen = get(wrapped, &reference).*;
    end(wrapped, &scope);
    return seen;
}
