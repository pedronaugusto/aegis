//! Leaf initialization under the election mutex, with no task context and the initializer's own errors.
const std = @import("std");
const Io = std.Io;
const interior = @import("interior.zig");

/// The first caller initializes `T` in place while later callers wait for it; every caller then reads the
/// same published value. The initializer is a leaf: `fn (context, *T) E!void` or `void`, bounded and
/// nonblocking, and it gets no Io, so it cannot wait or reach another Lazy. It runs with the election mutex
/// held, so a waiter blocks uncancelably for that bounded time. For an initializer that waits, allocates
/// through Io or must be canceled, use `Once`.
///
/// A `T` that declares `pub const interior_lock = true` (every aegis guard does) is handed out mutable,
/// since all of its mutation is behind its own lock; any other `T` is handed out const.
/// Stable after publication. Drain initializers, waiters and readers before teardown.
pub fn Lazy(comptime T: type) type {
    return struct {
        const Self = @This();
        const State = enum(u8) { empty, ready };
        /// The pointer handed out: mutable only for a type that locks itself.
        pub const Ref = interior.Handout(T);
        /// Private: publication state; the ready fast path reads it with acquire.
        state: std.atomic.Value(State) = .init(.empty),
        /// Private: serializes elections and holds the initializer.
        mutex: Io.Mutex = .init,
        /// Private: initialized only in ready, never moved after a successful initializer.
        data: T = undefined,

        pub fn init() Self {
            return .{};
        }

        /// The initialized value, or null while empty. Never waits.
        pub fn get(self: *Self) ?Ref {
            return if (self.state.load(.acquire) == .ready) &self.data else null;
        }

        /// The result of `getOrInit`: the initializer's errors and nothing added.
        pub fn Result(comptime init_fn: anytype) type {
            const returned = @typeInfo(@TypeOf(init_fn)).@"fn".return_type.?;
            return switch (@typeInfo(returned)) {
                .error_union => |info| info.error_set!Ref,
                .void => Ref,
                else => @compileError("a Lazy initializer returns void or an error union of void"),
            };
        }

        /// Initializes on first use. On an initializer error the value stays empty, the error is returned
        /// and the next caller tries again; the initializer cleans every partial acquisition itself.
        pub fn getOrInit(self: *Self, io: Io, context: anytype, comptime init_fn: anytype) Result(init_fn) {
            if (self.state.load(.acquire) == .ready) return &self.data;
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            if (self.state.load(.monotonic) == .empty) {
                if (comptime @typeInfo(@typeInfo(@TypeOf(init_fn)).@"fn".return_type.?) == .error_union) {
                    try init_fn(context, &self.data);
                } else init_fn(context, &self.data);
                self.state.store(.ready, .release);
            }
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
