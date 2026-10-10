//! Caller-ranked locks with a bounded, explicitly carried logical-task context.
const std = @import("std");
const builtin = @import("builtin");
const Condition = @import("Condition.zig");
const diagnostics = builtin.optimize == .debug;

/// after indices describe a strict partial order, not numeric priority.
pub const Rank = struct { name: []const u8, after: []const usize = &.{} };

/// Validates a finite acyclic relation at comptime. No global policy or threadlocal state.
pub fn Order(comptime ranks: []const Rank) type {
    const relation = comptime blk: {
        @setEvalBranchQuota(100000);
        var edges: [ranks.len][ranks.len]bool = @splat(@splat(false));
        for (ranks, 0..) |rank, i| {
            for (ranks[0..i]) |earlier| if (std.mem.eql(u8, rank.name, earlier.name)) @compileError("duplicate order rank");
            for (rank.after) |before| {
                if (before >= ranks.len) @compileError("order rank outside relation");
                edges[before][i] = true;
            }
        }
        for (0..ranks.len) |k| for (0..ranks.len) |i| for (0..ranks.len) |j| {
            edges[i][j] = edges[i][j] or (edges[i][k] and edges[k][j]);
        };
        for (0..ranks.len) |i| if (edges[i][i]) @compileError("cyclic lock order");
        break :blk edges;
    };
    return struct {
        const Held = struct { owner: *const anyopaque, rank: usize };
        pub const CheckError = error{ SameOwner, Inversion, Unordered, StackOverflow, Suspended };
        /// One context per logical task, never simultaneously shared. Release is zero-sized.
        pub const Context = struct {
            /// Private: bounded diagnostic stack and suspension state.
            stack: if (diagnostics) [32]Held else void = if (diagnostics) undefined else {},
            used: if (diagnostics) usize else void = if (diagnostics) 0 else {},
            suspended: if (diagnostics) bool else void = if (diagnostics) false else {},
            /// Diagnostic preflight, before any base lock/Io call. Release always succeeds.
            pub fn check(self: *const Context, owner: *const anyopaque, comptime rank: usize) CheckError!void {
                if (rank >= ranks.len) @compileError("order rank outside relation");
                if (diagnostics) {
                    if (self.suspended) return error.Suspended;
                    for (self.stack[0..self.used]) |held| {
                        if (held.owner == owner) return error.SameOwner;
                    }
                    for (self.stack[0..self.used]) |held| if (relation[rank][held.rank]) return error.Inversion;
                    for (self.stack[0..self.used]) |held| if (!relation[held.rank][rank]) return error.Unordered;
                    if (self.used == self.stack.len) return error.StackOverflow;
                }
            }
            fn require(self: *Context, owner: *const anyopaque, comptime rank: usize) void {
                self.check(owner, rank) catch |err| @panic(@errorName(err));
            }
            fn push(self: *Context, owner: *const anyopaque, comptime rank: usize) void {
                if (diagnostics) {
                    self.stack[self.used] = .{ .owner = owner, .rank = rank };
                    self.used += 1;
                }
            }
            fn pop(self: *Context, owner: *const anyopaque) void {
                if (diagnostics) {
                    std.debug.assert(!self.suspended);
                    std.debug.assert(self.used != 0);
                    std.debug.assert(self.stack[self.used - 1].owner == owner);
                    self.used -= 1;
                }
            }
        };
        /// The owner stores only its base lock/data; diagnostic policy lives in the task and guards.
        pub fn Ordered(comptime LockType: type, comptime rank: usize) type {
            if (rank >= ranks.len) @compileError("order rank outside relation");
            return struct {
                const Self = @This();
                /// Private: access only through an ordered guard.
                base: LockType,
                /// As the base lock's: all access is behind its lock.
                pub const interior_lock = LockType.interior_lock;
                pub fn init(base: LockType) Self {
                    return .{ .base = base };
                }
                /// The data of a sole owner, with no lock, no Io and no rank check, as the base lock's `teardown`.
                pub fn teardown(self: *Self) @typeInfo(@TypeOf(LockType.teardown)).@"fn".return_type.? {
                    return self.base.teardown();
                }
                /// As the base lock's `isHeld`, for the locks that have one.
                pub fn isHeld(self: *const Self) bool {
                    return self.base.isHeld();
                }
                fn wrap(self: *Self, context: *Context, base: anytype) Capability(@TypeOf(base), Context) {
                    context.push(self, rank);
                    return .{ .base = base, .context = if (diagnostics) context else {} };
                }
                pub fn acquireOrdered(self: *Self, io: std.Io, context: *Context) LockType.AcquireError!Capability(LockType.Guard, Context) {
                    context.require(self, rank);
                    return self.wrap(context, try self.base.acquire(io));
                }
                /// `acquireOrdered` for a cleanup path that cannot take an error: cancellation does not
                /// interrupt the wait, as the base lock's `acquireUncancelable`. The rank check is the same.
                pub fn acquireOrderedUncancelable(self: *Self, io: std.Io, context: *Context) Capability(LockType.Guard, Context) {
                    context.require(self, rank);
                    return self.wrap(context, self.base.acquireUncancelable(io));
                }
                pub fn readOrdered(self: *Self, io: std.Io, context: *Context) LockType.AcquireError!Capability(LockType.ReadGuard, Context) {
                    context.require(self, rank);
                    return self.wrap(context, try self.base.read(io));
                }
                pub fn writeOrdered(self: *Self, io: std.Io, context: *Context) LockType.AcquireError!Capability(LockType.WriteGuard, Context) {
                    context.require(self, rank);
                    return self.wrap(context, try self.base.write(io));
                }
                /// As `readOrdered`, uncancelable; only the admission ceiling can still refuse.
                pub fn readOrderedUncancelable(self: *Self, io: std.Io, context: *Context) LockType.AdmissionError!Capability(LockType.ReadGuard, Context) {
                    context.require(self, rank);
                    return self.wrap(context, try self.base.readUncancelable(io));
                }
                /// As `writeOrdered`, uncancelable; only the admission ceiling can still refuse.
                pub fn writeOrderedUncancelable(self: *Self, io: std.Io, context: *Context) LockType.AdmissionError!Capability(LockType.WriteGuard, Context) {
                    context.require(self, rank);
                    return self.wrap(context, try self.base.writeUncancelable(io));
                }
            };
        }
    };
}

fn Capability(comptime Base: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        /// Private: uncopied base capability and Debug task witness.
        base: Base,
        context: if (diagnostics) *Context else void,
        pub fn value(self: *const Self) @typeInfo(@TypeOf(Base.value)).@"fn".return_type.? {
            return self.base.value();
        }
        pub fn deinit(self: *Self, io: std.Io) void {
            if (diagnostics) self.context.pop(@ptrCast(self.base.owner)); // safe: ordered owner has base as its first/only field
            self.base.deinit(io);
        }
        /// Rank remains reserved throughout suspension; context cannot acquire another lock.
        pub fn waitCondition(self: *Self, condition: *Condition, io: std.Io, timeout: std.Io.Timeout) Condition.WaitError!void {
            if (diagnostics) self.context.suspended = true;
            defer if (diagnostics) {
                self.context.suspended = false;
            };
            return condition.waitMutex(io, &self.base.owner.mutex, timeout);
        }
    };
}
