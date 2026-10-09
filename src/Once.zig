//! Stable-destination initialization with acquire/release publication and retry.
const std = @import("std");
const builtin = @import("builtin");
const Condition = @import("Condition.zig");
const diagnostics = builtin.mode == .debug;

/// One context per logical task, carried explicitly across runtime migration.
/// Never share with another simultaneous task. Release is zero-sized.
pub const InitContext = struct {
    /// Private: Debug-only active initializer identities, no threadlocal state.
    owners: if (diagnostics) [32]*const anyopaque else void = if (diagnostics) undefined else {},
    /// Private: bounded Debug stack; overflow diagnoses rather than weakening checks.
    used: if (diagnostics) usize else void = if (diagnostics) 0 else {},
    fn enter(self: *InitContext, owner: *const anyopaque) void {
        if (diagnostics) {
            for (self.owners[0..self.used]) |held| if (held == owner) @panic("recursive Once initializer");
            if (self.used == self.owners.len) @panic("Once initializer stack full");
            self.owners[self.used] = owner;
            self.used += 1;
        }
    }
    fn leave(self: *InitContext, owner: *const anyopaque) void {
        if (diagnostics) {
            std.debug.assert(self.used != 0);
            std.debug.assert(self.owners[self.used - 1] == owner);
            self.used -= 1;
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
        state: std.atomic.Value(State) = .init(.empty),
        /// Private: serializes elections, never held over external initializer/cleanup.
        mutex: std.Io.Mutex = .init,
        /// Private: bounded registry of initialization waiters.
        changed: Condition = .{},
        /// Private: only initialized in ready, never moved after successful callback.
        data: T = undefined,
        pub fn init() Self {
            return .{};
        }
        pub fn initLimit(limit: usize) Self {
            return .{ .changed = .initLimit(limit) };
        }
        pub fn get(self: *const Self) ?*const T {
            return if (self.state.load(.acquire) == .ready) &self.data else null;
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
            if (self.state.load(.acquire) == .ready) return &self.data;
            task.enter(self);
            defer task.leave(self);
            try self.mutex.lock(io);
            while (true) {
                switch (self.state.load(.acquire)) {
                    .ready => {
                        self.mutex.unlock(io);
                        return &self.data;
                    },
                    .empty => break,
                    .running => self.changed.waitMutex(io, &self.mutex, .none) catch |err| {
                        self.mutex.unlock(io);
                        switch (err) {
                            error.Timeout => unreachable, // unreachable: Once waits without a deadline.
                            error.Canceled, error.WaiterLimit => |e| return e,
                        }
                    },
                }
            }
            self.state.store(.running, .monotonic);
            self.mutex.unlock(io);
            init_fn(io, context, &self.data) catch |err| {
                self.mutex.lockUncancelable(io);
                self.state.store(.empty, .release);
                self.changed.broadcast(io);
                self.mutex.unlock(io);
                return err;
            };
            self.mutex.lockUncancelable(io);
            self.state.store(.ready, .release);
            self.changed.broadcast(io);
            self.mutex.unlock(io);
            return &self.data;
        }
        /// Requires join/drain and no borrows. Static infallible nonblocking cleanup.
        /// Empty storage is never read or cleaned as T. Does not reset the owner.
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            if (self.state.load(.acquire) == .ready) cleanup(&self.data);
            self.* = undefined;
        }
    };
}
