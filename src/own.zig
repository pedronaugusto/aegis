//! Explicit single-task owners. Cleanup is static, infallible and nonblocking.
const builtin = @import("builtin");
const std = @import("std");
const moves = @import("move.zig");
const units = @import("units.zig");
const diagnostics = builtin.optimize == .debug;
const State = if (diagnostics) struct { live: bool = true, address: ?*const anyopaque = null } else struct {};

fn bind(state: *State, address: *const anyopaque) void {
    if (diagnostics) {
        std.debug.assert(state.live);
        if (state.address) |old| std.debug.assert(old == address);
        state.address = address;
    }
}
fn consume(state: *State) void {
    if (diagnostics) state.live = false;
}

/// Never copy a bound owner. Borrows end on mutation, transfer or cleanup.
/// This cannot detect pre-binding copies, reflection or omitted deinit.
/// Blocking/fallible teardown requires the consumer's explicit finish/join first.
pub fn Owned(comptime T: type, comptime cleanup: fn (*T) void) type {
    return Owner(T, false, cleanup);
}

/// `Owned` for a resource released through `Io`, such as an open file or a socket: `deinit(io)` runs
/// `cleanup(&payload, io)`. The owner stores no `Io`; the one that releases it passes its own, as every
/// aegis guard does. Cleanup is still infallible and exactly once, so a release that can fail belongs in
/// an explicit `finish(io)` first. Everything else is `Owned`'s: the same size, the same Debug witness,
/// `initFrom`, `borrow`, `borrowMut`, `moveInto` and `take`.
pub fn OwnedIo(comptime T: type, comptime cleanup: fn (*T, std.Io) void) type {
    return Owner(T, true, cleanup);
}

fn Owner(comptime T: type, comptime with_io: bool, comptime cleanup: if (with_io) fn (*T, std.Io) void else fn (*T) void) type {
    return struct {
        const Self = @This();
        /// Private: access only through a live owner.
        data: T,
        /// Private: Debug-only live/address witness.
        state: State = .{},
        pub fn init(value: T) Self {
            return .{ .data = value };
        }
        /// Takes the payload out of `source` by its `moveInto` when `T` declares one, else by assignment,
        /// and consumes `source`. For a payload that must not exist twice, such as a Budget reservation:
        /// `init` would copy it and leave the source able to release it again.
        pub fn initFrom(source: *T) Self {
            var self: Self = .{ .data = undefined };
            moves.into(T, source, &self.data);
            return self;
        }
        pub fn borrow(self: *Self) *const T {
            bind(&self.state, self);
            return &self.data;
        }
        pub fn borrowMut(self: *Self) *T {
            bind(&self.state, self);
            return &self.data;
        }
        /// Transfers into uninitialized disjoint wrapper storage; destination binds on first use.
        pub fn moveInto(self: *Self, destination: *Self) void {
            bind(&self.state, self);
            std.debug.assert(self != destination);
            destination.* = .{ .data = undefined };
            moves.into(T, &self.data, &destination.data);
            consume(&self.state);
        }
        /// Transfers into a fresh owner returned by value, as `moveInto` does: binds and consumes `self`; the
        /// result binds at its first use, so it may be moved freely until then, as after `init`.
        pub fn move(self: *Self) Self {
            if (comptime moves.declares(T)) @compileError("move returns its owner by value; a payload that moves by moveInto moves by moveInto");
            var destination: Self = undefined;
            self.moveInto(&destination);
            return destination;
        }
        /// What `lend` gives.
        pub const Lending = Lent(T);
        /// A copy of the payload that is not the caller's to release, as `borrow` lends it. It ends on
        /// mutation, transfer or cleanup of the owner; nothing checks a `Lent` that outlives it.
        pub fn lend(self: *Self) Lending {
            if (comptime moves.declares(T)) @compileError("lend copies its payload; a payload that moves by moveInto is reached by borrow");
            bind(&self.state, self);
            return .{ .data = self.data };
        }
        /// Transfers payload into uninitialized disjoint storage; deinit is no longer owed.
        pub fn take(self: *Self, destination: *T) void {
            bind(&self.state, self);
            moves.into(T, &self.data, destination);
            consume(&self.state);
        }
        /// Runs exactly once, without implicit waiting, allocation or unwind on abort. An owner released
        /// through `Io` takes it here: `deinit(io)`.
        pub const deinit = if (with_io) deinitIo else deinitPlain;
        fn deinitPlain(self: *Self) void {
            bind(&self.state, self);
            consume(&self.state);
            cleanup(&self.data);
        }
        fn deinitIo(self: *Self, io: std.Io) void {
            bind(&self.state, self);
            consume(&self.state);
            cleanup(&self.data, io);
        }
    };
}

/// Why `readFile` failed: opening the file, reading its length, reading it, memory, or a file longer
/// than the limit. A cancel is `Canceled` wherever it lands, the length's read included.
pub const ReadFileError = std.Io.File.OpenError || std.Io.File.StatError || std.Io.File.Reader.Error || std.mem.Allocator.Error || error{
    /// The file holds more than the limit's bytes.
    StreamTooLong,
};

/// The bytes of the file at `sub_path` in `dir`, at most `limit` of them; the caller owns them and frees
/// them with `gpa`. The file's length is read first and its error returned, so a cancel that lands there
/// is `Canceled`: std's `Dir.readFileAlloc` takes a failed length as a guess and reads on, losing it. A
/// file longer than `limit` is `StreamTooLong` before anything is allocated, and one that grows past it
/// while it is read is too.
pub fn readFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8, gpa: std.mem.Allocator, limit: units.Bytes(u64)) ReadFileError![]u8 {
    var file = try dir.openFile(io, sub_path, .{ .allow_directory = builtin.os.tag != .windows });
    defer file.close(io);
    const length = (try file.stat(io)).size;
    if (length > limit.raw()) return error.StreamTooLong;
    // The reader knows the length, so it never asks again.
    var reader: std.Io.File.Reader = .initSize(file, io, &.{}, length);
    // std reads one byte past a limit to tell a longer stream; a limit past `usize` is all memory.
    const most = @min(std.math.cast(usize, limit.raw()) orelse std.math.maxInt(usize), std.math.maxInt(usize) - 1);
    return reader.interface.allocRemaining(gpa, .limited(most)) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        error.OutOfMemory, error.StreamTooLong => |e| return e,
    };
}

/// A copy of a resource an owner keeps, lent out: the type says it is not the holder's to release, and it
/// has no `deinit`. It ends on mutation, transfer or cleanup of the owner, as a borrow does; nothing checks
/// one that outlives it. What an accessor hands out of a handle its owner closes.
pub fn Lent(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: reached through `get`.
        data: T,
        pub fn get(self: Self) T {
            return self.data;
        }
    };
}

/// Result obligation with explicit discharge, not a resource destructor.
/// Release has no obligation tracking; omitted deinit escapes even in Debug.
pub fn MustUse(comptime T: type, comptime obligation: []const u8) type {
    return struct {
        const Self = @This();
        /// Private: take rather than copying.
        data: T,
        /// Private: Debug-only discharge state.
        pending: if (diagnostics) bool else void = if (diagnostics) true else {},
        /// Private: Debug-only teardown state.
        live: if (diagnostics) bool else void = if (diagnostics) true else {},
        pub fn init(value: T) Self {
            return .{ .data = value };
        }
        fn check(self: *Self) void {
            if (diagnostics) {
                std.debug.assert(self.live);
                std.debug.assert(self.pending);
            }
        }
        pub fn take(self: *Self, destination: *T) void {
            self.check();
            destination.* = self.data;
            if (diagnostics) self.pending = false;
        }
        /// Non-resource results only. A static public reason documents intentional discard.
        pub fn acknowledge(self: *Self, comptime reason: []const u8) void {
            if (reason.len == 0) @compileError("acknowledge requires a reason");
            self.check();
            if (diagnostics) self.pending = false;
        }
        pub fn deinit(self: *Self) void {
            if (diagnostics) {
                std.debug.assert(self.live);
                if (self.pending) @panic(obligation);
                self.live = false;
            }
        }
    };
}
