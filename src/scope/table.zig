//! The creator's table of scopes, and the scope handles it opens.
const std = @import("std");
const slot = @import("slot.zig");
const refs = @import("ref.zig");
const checked = slot.checked;
const none = std.math.maxInt(usize);

/// The scopes of one brand that a creator keeps: a connection holding its request scopes, a server its
/// connection scopes. The creator owns the table and the slots under it. Both must outlive every
/// reference made in their scopes and stay where they are while any scope is open.
///
/// Not thread-safe: opening and ending are one owner's calls, or externally synchronized. A reference's
/// check reads its generation atomically, so using it from another thread is well defined, but it only
/// means something when the caller's own synchronization orders the end of the scope against that use.
pub fn Table(comptime Brand: type) type {
    return struct {
        const Self = @This();
        /// The scope handle this table opens.
        pub const Scope = ScopeOf(Brand);
        /// Storage for one scope's record; zero-sized outside Debug and ReleaseSafe.
        pub const Slot = slot.Slot;
        /// `Full` while every slot is open; `Exhausted` once every slot has used all its generations.
        pub const OpenError = error{ Full, Exhausted };
        /// Private: the caller's slot storage.
        slots: if (checked) []Slot else void,
        /// Private: the first free slot, threaded through the slots.
        free_head: if (checked) usize else void,
        /// Private: slots that used up their generations.
        used_up: if (checked) usize else void,
        /// Private: scopes opened and not yet ended.
        open_count: if (checked) usize else void,

        /// A table over `slots`, which it takes over for as long as it lives. The number of slots is the
        /// number of scopes that can be open and checked at once; it is not an admission limit, since
        /// ReleaseFast and ReleaseSmall keep no record and open without limit.
        pub fn init(slots: []Slot) Self {
            if (!checked) return .{ .slots = {}, .free_head = {}, .used_up = {}, .open_count = {} };
            for (slots, 0..) |*each, i| each.* = .{ .next = if (i + 1 < slots.len) i + 1 else none };
            return .{ .slots = slots, .free_head = if (slots.len == 0) none else 0, .used_up = 0, .open_count = 0 };
        }

        /// Opens a scope with the slot's current generation.
        pub fn open(self: *Self) OpenError!Scope {
            if (!checked) return .{ .table = {}, .index = {}, .generation = {} };
            const index = self.free_head;
            if (index == none) return if (self.slots.len != 0 and self.used_up == self.slots.len) error.Exhausted else error.Full;
            const opened = &self.slots[index];
            self.free_head = opened.next;
            self.open_count += 1;
            return .{ .table = self, .index = index, .generation = opened.generation.load(.monotonic) };
        }

        /// Ends with the table. Debug and ReleaseSafe stop the program if a scope is still open: its
        /// references would outlive the records that check them.
        pub fn deinit(self: *Self) void {
            if (checked and self.open_count != 0) @panic("scope table torn down with a scope still open");
            self.* = undefined;
        }
    };
}

/// One open scope of brand `Brand`. Copying it is allowed and ending it twice is not: the second `end`
/// finds the generation already moved on. Zero-sized outside Debug and ReleaseSafe.
fn ScopeOf(comptime Brand: type) type {
    return struct {
        const Self = @This();
        /// The brand: the kind of scope this is.
        pub const brand = Brand;
        /// Private: the creator's table; checked builds only.
        table: if (checked) *Table(Brand) else void,
        /// Private: this scope's slot in the table; checked builds only.
        index: if (checked) usize else void,
        /// Private: the generation this scope holds; checked builds only.
        generation: if (checked) u64 else void,

        /// This scope's record, after checking the scope has not ended.
        fn record(self: Self, comptime message: []const u8) *slot.Slot {
            const found = &self.table.slots[self.index];
            if (found.generation.load(.monotonic) != self.generation) @panic(message);
            return found;
        }

        /// A reference to `pointer` that is good while this scope is open. The scope vouches for the memory:
        /// the creator frees or resets it when the scope ends.
        pub fn ref(self: Self, pointer: anytype) refs.Ref(Brand, @TypeOf(pointer)) {
            if (!checked) return .{ .ptr = pointer, .slot = {}, .generation = {} };
            return .{ .ptr = pointer, .slot = self.record("scope used after it ended"), .generation = self.generation };
        }

        /// Binds a reference made in another scope, of any brand, to this one. This is the one way a
        /// reference moves between scopes, and it says so: the source must still be good, and from here
        /// on the memory is vouched for by this scope.
        pub fn reborrow(self: Self, source: anytype) refs.Ref(Brand, @TypeOf(source).Pointer) {
            return self.ref(source.get());
        }

        /// Ends the scope: every reference made in it is stale from here on. Debug and ReleaseSafe stop the
        /// program if it already ended.
        pub fn end(self: Self) void {
            if (!checked) return;
            const ending = self.record("scope ended twice");
            const next_generation = self.generation + 1;
            ending.generation.store(next_generation, .monotonic);
            self.table.open_count -= 1;
            if (next_generation == slot.retired) {
                self.table.used_up += 1;
            } else {
                ending.next = self.table.free_head;
                self.table.free_head = self.index;
            }
        }
    };
}
