//! Stable-destination initialization with acquire/release publication and retry.
const std = @import("std");
const builtin = @import("builtin");
const Condition = @import("Condition.zig");
const diagnostics = builtin.optimize == .debug;

/// One context per logical task, carried explicitly across runtime migration.
/// Never share with another simultaneous task. Release is zero-sized.
pub const InitContext = struct {
    /// Private: Debug-only active initializer identities, no threadlocal state.
    aegis_owners: if (diagnostics) [32]*const anyopaque else void = if (diagnostics) undefined else {},
    /// Private: bounded Debug stack; overflow diagnoses rather than weakening checks.
    aegis_used: if (diagnostics) usize else void = if (diagnostics) 0 else {},
    fn enter(self: *InitContext, owner: *const anyopaque) void {
        if (diagnostics) {
            for (self.aegis_owners[0..self.aegis_used]) |held| if (held == owner) @panic("recursive Once initializer");
            if (self.aegis_used == self.aegis_owners.len) @panic("Once initializer stack full");
            self.aegis_owners[self.aegis_used] = owner;
            self.aegis_used += 1;
        }
    }
    fn leave(self: *InitContext, owner: *const anyopaque) void {
        if (diagnostics) {
            std.debug.assert(self.aegis_used != 0);
            std.debug.assert(self.aegis_owners[self.aegis_used - 1] == owner);
            self.aegis_used -= 1;
        }
    }
};

/// Stable once owner; drain initializer/waiters/readers before teardown.
/// Immutable borrows do not make mutable pointees safe. No reset/poison recovery.
/// For a bounded initializer with no Io, which needs no task context, see `Lazy`.
pub fn Once(comptime T: type) type {
    return struct {
        const Self = @This();
        const State = enum(u32) { empty, running, ready };
        /// Private: publication state, ready fast path requires acquire.
        aegis_state: std.atomic.Value(State) = .init(.empty),
        /// Private: serializes elections, never held over external initializer/cleanup.
        aegis_mutex: std.Io.Mutex = .init,
        /// Private: bounded registry of initialization waiters.
        aegis_changed: Condition = .{},
        /// Private: only initialized in ready, never moved after successful callback.
        aegis_data: T = undefined,
        pub fn init() Self {
            return .{};
        }
        pub fn initLimit(limit: usize) Self {
            return .{ .aegis_changed = .initLimit(limit) };
        }
        pub fn get(self: *const Self) ?*const T {
            return if (self.aegis_state.load(.acquire) == .ready) &self.aegis_data else null;
        }
        fn InitError(comptime Context: type, comptime init_fn: anytype) type {
            const Result = @typeInfo(@TypeOf(init_fn)).@"fn".return_type.?;
            _ = Context;
            return @typeInfo(Result).error_union.error_set || std.Io.Cancelable || error{WaiterLimit};
        }
        /// The explicit task context diagnoses reentry without migrating-thread TLS.
        /// Callback must clean partial acquisitions on every error and leave no live T.
        /// Success establishes one owner directly in destination; commit cannot be canceled.
        pub fn getOrInit(self: *Self, io: std.Io, task: *InitContext, context: anytype, comptime init_fn: anytype) InitError(@TypeOf(context), init_fn)!*const T {
            if (self.aegis_state.load(.acquire) == .ready) return &self.aegis_data;
            task.enter(self);
            defer task.leave(self);
            try self.aegis_mutex.lock(io);
            while (true) {
                switch (self.aegis_state.load(.acquire)) {
                    .ready => {
                        self.aegis_mutex.unlock(io);
                        return &self.aegis_data;
                    },
                    .empty => break,
                    .running => self.aegis_changed.waitMutex(io, &self.aegis_mutex, .none) catch |err| {
                        self.aegis_mutex.unlock(io);
                        switch (err) {
                            error.Timeout => unreachable, // unreachable: Once waits without a deadline.
                            error.Canceled, error.WaiterLimit => |e| return e,
                        }
                    },
                }
            }
            self.aegis_state.store(.running, .monotonic);
            self.aegis_mutex.unlock(io);
            init_fn(io, context, &self.aegis_data) catch |err| {
                self.aegis_mutex.lockUncancelable(io);
                self.aegis_state.store(.empty, .release);
                self.aegis_changed.broadcast(io);
                self.aegis_mutex.unlock(io);
                return err;
            };
            self.aegis_mutex.lockUncancelable(io);
            self.aegis_state.store(.ready, .release);
            self.aegis_changed.broadcast(io);
            self.aegis_mutex.unlock(io);
            return &self.aegis_data;
        }
        /// Requires join/drain and no borrows. Static infallible nonblocking cleanup.
        /// Empty storage is never read or cleaned as T. Does not reset the owner.
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            if (self.aegis_state.load(.acquire) == .ready) cleanup(&self.aegis_data);
            self.* = undefined;
        }
    };
}
