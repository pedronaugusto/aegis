//! Slots of one type on a region of their own. The storage never moves, and a freed slot goes back
//! to the pool, never to the system, until the pool ends. One engine, two contracts: a bare index,
//! whose stale use reads the slot's current `T`; or a generational key, refused when stale in every
//! build.
const builtin = @import("builtin");
const std = @import("std");
const Region = @import("../Region.zig");
const Domain = @import("Domain.zig");
const index = @import("index.zig");
const assert = @import("../assert.zig");
const move = @import("../move.zig");
const overlap = @import("overlap.zig");

/// The double-free check follows Zig's runtime safety: on in Debug and ReleaseSafe.
const checked = builtin.optimize == .debug or builtin.optimize == .safe;

pub const Options = struct {
    /// The width of a slot's generation, for a keyed pool; null for a pool of bare indexes.
    generation: ?type = null,
};

pub fn SlotPool(comptime T: type, comptime Tag: type, comptime options: Options) type {
    return if (options.generation) |G| Keyed(T, Tag, G) else Indexed(T, Tag);
}

/// Slots named by a bare `Index(Tag, u32)`: four bytes, and a stale index reads the slot's
/// current value of type `T`, a logic error, never another type's bytes.
fn Indexed(comptime T: type, comptime Tag: type) type {
    return struct {
        const Self = @This();
        pub const Handle = index.Index(Tag, u32);
        /// A handle or none, in the same four bytes.
        pub const OptionalHandle = index.OptionalIndex(Tag, u32);
        pub const Error = Region.Error;
        const none = std.math.maxInt(u32);
        pub const Slot = struct {
            value: T,
            /// The next free slot while this one is free.
            next: u32,
            /// Checked builds: whether the slot holds a value.
            live: if (checked) bool else void,
        };
        /// A slot taken by `create`: its handle and its value, to build in place.
        pub const Created = struct { handle: Handle, value: *T };

        /// Private: the pool's own region; it is the region's only grower.
        region: Region,
        /// Private: the first slot.
        slots: [*]Slot,
        /// Private: the slots pushed.
        count: u32 = 0,
        /// Private: the newest freed slot, or none.
        free_head: u32 = none,
        /// Private: the slots holding a value.
        used: u32 = 0,

        /// The pool owns `region` from here on.
        pub fn init(region: Region) Self {
            return .{ .region = region, .slots = @ptrFromInt(std.mem.alignForward(usize, region.top, @alignOf(Slot))) }; // safe: the slots start at the region's top, aligned as its pushes align them
        }
        /// Returns the region; values in the slots are the caller's to have cleaned.
        pub fn deinit(p: *Self) void {
            p.region.deinit();
            p.* = undefined;
        }
        /// The newest freed slot, else one more on the region.
        pub inline fn alloc(p: *Self, value: T) Error!Handle {
            const i = try p.take();
            p.slots[i].value = value;
            return @fromBackingInt(i);
        }
        /// A slot whose value is the caller's to build in place, knowing its own handle.
        pub inline fn create(p: *Self) Error!Created {
            const i = try p.take();
            return .{ .handle = @fromBackingInt(i), .value = &p.slots[i].value };
        }
        inline fn take(p: *Self) Error!u32 {
            const i = p.free_head;
            if (i == none) return p.grow();
            const slot = &p.slots[i];
            p.free_head = slot.next;
            if (checked) slot.live = true;
            p.used += 1;
            return i;
        }
        fn grow(p: *Self) Error!u32 {
            if (p.count == none) return error.LimitExceeded;
            const slot = try p.region.create(Slot);
            if (checked) slot.live = true;
            p.count += 1;
            p.used += 1;
            return p.count - 1;
        }
        /// Room for `n` more values: the next `n` allocs take freed slots and cannot fail.
        pub fn reserve(p: *Self, n: u32) Error!void {
            while (p.count - p.used < n) {
                if (p.count == none) return error.LimitExceeded;
                const slot = try p.region.create(Slot);
                if (checked) slot.live = false;
                slot.next = p.free_head;
                p.free_head = p.count;
                p.count += 1;
            }
        }
        /// Out of range stops in every build. A freed slot's value stays until the slot is reused.
        pub fn free(p: *Self, h: Handle) void {
            const i = h.raw();
            assert.invariant(i < p.count, "slot handle out of range");
            const slot = &p.slots[i];
            if (checked) {
                if (!slot.live) @panic("slot freed twice");
                slot.live = false;
            }
            slot.next = p.free_head;
            p.free_head = i;
            p.used -= 1;
        }
        /// The slot's value, valid until the pool ends whatever is freed or grown. Out of range stops
        /// in every build.
        pub inline fn get(p: *const Self, h: Handle) *T {
            const i = h.raw();
            assert.invariant(i < p.count, "slot handle out of range");
            return &p.slots[i].value;
        }
        /// The handle of a value in the pool; a pointer that is not one stops in every build.
        pub fn handleOf(p: *const Self, item: *const T) Handle {
            const at = @intFromPtr(item) -% @intFromPtr(p.slots); // safe: compared against the pool's own extent only
            assert.invariant(at < @as(usize, p.count) * @sizeOf(Slot) and at % @sizeOf(Slot) == @offsetOf(Slot, "value"), "pointer is not a value of this pool");
            return @fromBackingInt(@intCast(at / @sizeOf(Slot)));
        }
        pub fn len(p: *const Self) usize {
            return p.used;
        }
        /// Every slot back at once, pages kept committed; every earlier handle is out of range.
        pub fn recycleAll(p: *Self) void {
            p.region.top = @intFromPtr(p.slots);
            p.count = 0;
            p.free_head = none;
            p.used = 0;
        }
    };
}

/// Slots named by a generational key carrying the pool's instance: stale, foreign and
/// out-of-range keys are errors in every build, and a worn-out slot retires.
fn Keyed(comptime T: type, comptime Tag: type, comptime G: type) type {
    if (@typeInfo(G) != .int or @typeInfo(G).int.signedness != .unsigned or @bitSizeOf(G) == 0)
        @compileError("SlotPool's generation is a nonzero unsigned integer");
    return struct {
        const Self = @This();
        const none = std.math.maxInt(usize);
        pub const Key = struct {
            pub const Brand = Tag;
            instance: Domain.Instance,
            index: usize,
            generation: G,
        };
        pub const Handle = Key;
        pub const Slot = struct {
            generation: G = 1,
            next: usize = none,
            state: enum { free, live, retired } = .free,
            value: T = undefined,
        };
        comptime {
            std.debug.assert(@sizeOf(Key) <= 48);
        }
        pub const InitError = error{InvalidInstance};
        pub const KeyError = error{ InvalidKey, AliasedStorage };
        pub const InsertError = Region.Error || error{AliasedStorage};

        /// Private: the pool's own region; it is the region's only grower.
        region: Region,
        /// Private: the first slot.
        slots: [*]Slot,
        instance: Domain.Instance,
        /// Private: the slots pushed.
        count: usize = 0,
        /// Private: the newest freed slot, or none.
        free_head: usize = none,
        /// Private: the slots holding a value.
        used: usize = 0,
        /// Private: the slots whose generations ran out.
        retired: usize = 0,

        /// The pool owns `region` from here on.
        pub fn init(region: Region, instance: Domain.Instance) InitError!Self {
            if (instance.serial == 0) return error.InvalidInstance;
            return .{ .region = region, .slots = @ptrFromInt(std.mem.alignForward(usize, region.top, @alignOf(Slot))), .instance = instance }; // safe: the slots start at the region's top, aligned as its pushes align them
        }
        fn storage(self: *const Self) []Slot {
            return self.slots[0..self.count];
        }
        /// Moves `source` into the newest freed slot, else one more on the region.
        pub inline fn insert(self: *Self, source: *T) InsertError!Key {
            if (overlap.overlapsOwner(T, source, self)) return error.AliasedStorage;
            if (overlap.overlaps(T, source, self.storage())) return error.AliasedStorage;
            if (self.free_head == none) try self.grow();
            const i = self.free_head;
            const slot = &self.slots[i];
            self.free_head = slot.next;
            move.intoPoisoning(T, source, &slot.value);
            slot.state = .live;
            self.used += 1;
            return .{ .instance = self.instance, .index = i, .generation = slot.generation };
        }
        fn grow(self: *Self) Region.Error!void {
            @branchHint(.unlikely);
            const slot = try self.region.create(Slot);
            slot.* = .{};
            self.free_head = self.count;
            self.count += 1;
        }
        pub inline fn contains(self: *const Self, key: Key) bool {
            if (self.instance.namespace != key.instance.namespace or self.instance.serial != key.instance.serial or key.index >= self.count) return false;
            const slot = &self.slots[key.index];
            return slot.state == .live and slot.generation == key.generation;
        }
        /// The value, valid until it is removed or the pool ends: growth never moves it.
        pub inline fn get(self: *Self, key: Key) KeyError!*T {
            if (!self.contains(key)) return error.InvalidKey;
            return &self.slots[key.index].value;
        }
        pub inline fn getConst(self: *const Self, key: Key) KeyError!*const T {
            if (!self.contains(key)) return error.InvalidKey;
            return &self.slots[key.index].value;
        }
        /// The key of a live value in the pool.
        pub fn handleOf(self: *const Self, item: *const T) KeyError!Key {
            const at = @intFromPtr(item) -% @intFromPtr(self.slots); // safe: compared against the pool's own extent only
            if (at >= self.count * @sizeOf(Slot) or at % @sizeOf(Slot) != @offsetOf(Slot, "value")) return error.InvalidKey;
            const i = at / @sizeOf(Slot);
            const slot = &self.slots[i];
            if (slot.state != .live) return error.InvalidKey;
            return .{ .instance = self.instance, .index = i, .generation = slot.generation };
        }
        pub inline fn remove(self: *Self, key: Key, destination: *T) KeyError!void {
            if (!self.contains(key)) return error.InvalidKey;
            if (overlap.overlapsOwner(T, destination, self) or overlap.overlaps(T, destination, self.storage())) return error.AliasedStorage;
            const slot = &self.slots[key.index];
            move.intoPoisoning(T, &slot.value, destination);
            self.invalidate(slot, key.index);
        }
        fn invalidate(self: *Self, slot: *Slot, i: usize) void {
            self.used -= 1;
            if (slot.generation == std.math.maxInt(G)) {
                slot.state = .retired;
                self.retired += 1;
            } else {
                slot.generation += 1;
                slot.state = .free;
                slot.next = self.free_head;
                self.free_head = i;
            }
        }
        pub fn len(self: *const Self) usize {
            return self.used;
        }
        /// The slots pushed so far, live, free and retired.
        pub fn capacity(self: *const Self) usize {
            return self.count;
        }
        /// Ascending slot order. Cleanup sees detached values; reentry is forbidden.
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            for (self.storage(), 0..) |*slot, i| {
                if (slot.state != .live) continue;
                var detached: T = undefined;
                move.intoPoisoning(T, &slot.value, &detached);
                self.invalidate(slot, i);
                cleanup(&detached);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            self.region.deinit();
            self.* = undefined;
        }
    };
}
