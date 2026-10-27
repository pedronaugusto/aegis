//! A lock-free cell for one scalar of a distinct domain: ids, counts, byte counts, durations, instants and plain
//! enums, read and written whole and never as the integer behind them; or for one pointer, published and taken
//! whole (`*T`, `?*T`).
const std = @import("std");
const Order = std.lang.AtomicOrder;

/// Whether `T` is a single-item pointer or an optional one: a cell that holds an address.
fn pointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |info| info.size == .one,
        .optional => |info| switch (@typeInfo(info.child)) {
            .pointer => |inner| inner.size == .one,
            else => false,
        },
        else => false,
    };
}

/// What the cell holds: the pointer itself, or the integer behind the domain.
fn Backing(comptime T: type) type {
    if (comptime pointer(T)) return T;
    const Repr = switch (@typeInfo(T)) {
        .@"enum" => |info| info.tag_type,
        else => @compileError("an atomic cell holds an enum with an integer backing (an id, a count, a unit or a plain enum) or a single-item pointer"),
    };
    switch (@bitSizeOf(Repr)) {
        8, 16, 32, 64 => {},
        else => @compileError("an atomic cell needs an 8, 16, 32 or 64-bit backing"),
    }
    return Repr;
}

/// Whether `T.add` and `T.sub` take a `T` and so can be applied atomically. An address has no arithmetic here.
fn adds(comptime T: type) bool {
    if (comptime pointer(T)) return false;
    return @hasDecl(T, "add") and @hasDecl(T, "sub") and
        @typeInfo(@TypeOf(T.add)).@"fn".param_types[1] == T and
        @typeInfo(@TypeOf(T.sub)).@"fn".param_types[1] == T;
}

fn AddResult(comptime T: type, comptime name: []const u8) type {
    if (!adds(T)) @compileError(name ++ " needs a domain whose add and sub take its own type");
    return T.AddError!T;
}
fn SubResult(comptime T: type, comptime name: []const u8) type {
    if (!adds(T)) @compileError(name ++ " needs a domain whose add and sub take its own type");
    return T.SubError!T;
}

/// The cell is one `std.atomic.Value` of the backing integer, so it has the size and alignment of that integer and
/// its loads, stores and exchanges compile to the same instructions. Orderings are std's.
///
/// Arithmetic is available where the domain has its own checked `add` and `sub` of its own type (`Count`, `Bytes`,
/// `Bits`, `Duration`): `fetchAdd` and `fetchSub` apply them atomically and report the domain's overflow error
/// without changing the cell, as the checked forms do, at the price of a compare-and-swap loop. `fetchAddWrapping`
/// and `fetchSubWrapping` are the hardware instruction, for a counter whose width cannot be reached or whose
/// wraparound is meant. `fetchMax` and `fetchMin` order by the backing integer, which is `compare` for every aegis
/// scalar.
///
/// A pointer cell (`Atomic(*Node)`, `Atomic(?*Batch)`) holds the address itself: `load`, `store`, `swap` and the
/// compare-and-swaps publish and take it whole, for a lock-free list head or a latest-value slot. It has no
/// ordering or arithmetic: `fetchMax`, `fetchMin` and the adds refuse it. Who owns what it points at is the
/// program's, as with any pointer.
pub fn Atomic(comptime T: type) type {
    const Repr = Backing(T);
    return struct {
        const Self = @This();
        /// Private: the backing integer or the pointer, only ever read and written whole.
        cell: std.atomic.Value(Repr),
        inline fn raw(value: T) Repr {
            return if (comptime pointer(T)) value else @backingInt(value);
        }
        inline fn cooked(value: Repr) T {
            return if (comptime pointer(T)) value else @fromBackingInt(value);
        }
        pub fn init(value: T) Self {
            return .{ .cell = .init(raw(value)) };
        }
        pub inline fn load(self: *const Self, order: Order) T {
            return cooked(self.cell.load(order));
        }
        pub inline fn store(self: *Self, value: T, order: Order) void {
            self.cell.store(raw(value), order);
        }
        /// Replaces the value and returns the one it replaced.
        pub inline fn swap(self: *Self, value: T, order: Order) T {
            return cooked(self.cell.swap(raw(value), order));
        }
        /// Replaces `expected` with `new`; null on success, else the value found.
        pub inline fn cmpxchgStrong(self: *Self, expected: T, new: T, success: Order, failure: Order) ?T {
            const found = self.cell.cmpxchgStrong(raw(expected), raw(new), success, failure) orelse return null;
            return cooked(found);
        }
        /// As `cmpxchgStrong`, and it may fail without a difference, for use in a loop.
        pub inline fn cmpxchgWeak(self: *Self, expected: T, new: T, success: Order, failure: Order) ?T {
            const found = self.cell.cmpxchgWeak(raw(expected), raw(new), success, failure) orelse return null;
            return cooked(found);
        }
        /// Raises the value to `value` if it is lower; returns the value before.
        pub inline fn fetchMax(self: *Self, value: T, order: Order) T {
            comptime if (pointer(T)) @compileError("fetchMax orders scalars; an address has no order here");
            return @fromBackingInt(self.cell.fetchMax(@backingInt(value), order));
        }
        /// Lowers the value to `value` if it is higher; returns the value before.
        pub inline fn fetchMin(self: *Self, value: T, order: Order) T {
            comptime if (pointer(T)) @compileError("fetchMin orders scalars; an address has no order here");
            return @fromBackingInt(self.cell.fetchMin(@backingInt(value), order));
        }
        /// Adds `delta` with the domain's checked `add` and returns the value before. On overflow the cell is
        /// untouched and the domain's error returns. `order` is the ordering of the successful exchange.
        pub inline fn fetchAdd(self: *Self, delta: T, order: Order) AddResult(T, "fetchAdd") {
            var seen = self.cell.load(.monotonic);
            while (true) {
                const before: T = @fromBackingInt(seen);
                const after = try before.add(delta);
                seen = self.cell.cmpxchgWeak(seen, @backingInt(after), order, .monotonic) orelse return before;
            }
        }
        /// As `fetchAdd`, with the domain's checked `sub`.
        pub inline fn fetchSub(self: *Self, delta: T, order: Order) SubResult(T, "fetchSub") {
            var seen = self.cell.load(.monotonic);
            while (true) {
                const before: T = @fromBackingInt(seen);
                const after = try before.sub(delta);
                seen = self.cell.cmpxchgWeak(seen, @backingInt(after), order, .monotonic) orelse return before;
            }
        }
        /// Adds `delta` as one hardware instruction and wraps at the width of the backing integer.
        pub inline fn fetchAddWrapping(self: *Self, delta: T, order: Order) T {
            comptime if (!adds(T)) @compileError("fetchAddWrapping needs a domain whose add and sub take its own type");
            return @fromBackingInt(self.cell.fetchAdd(@backingInt(delta), order));
        }
        /// Subtracts `delta` as one hardware instruction and wraps at the width of the backing integer.
        pub inline fn fetchSubWrapping(self: *Self, delta: T, order: Order) T {
            comptime if (!adds(T)) @compileError("fetchSubWrapping needs a domain whose add and sub take its own type");
            return @fromBackingInt(self.cell.fetchSub(@backingInt(delta), order));
        }
    };
}
