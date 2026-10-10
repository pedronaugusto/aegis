//! A payload staged at one state of a machine: the stage is part of the type and costs nothing at run time.
const builtin = @import("builtin");
const checked = builtin.mode == .debug or builtin.mode == .safe;
const diagnostics = builtin.mode == .debug;

/// Moves `source` into `destination` through `moveInto` when `T` declares it, else by assignment.
fn move(comptime T: type, source: *T, destination: *T) void {
    const has_move = switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "moveInto"),
        else => false,
    };
    if (has_move) source.moveInto(destination) else destination.* = source.*;
}

/// What a transition with a preparation returns: the preparation's own errors, or nothing when it returns void.
fn Prepared(comptime prepare: anytype) type {
    const returned = @typeInfo(@TypeOf(prepare)).@"fn".return_type.?;
    return switch (@typeInfo(returned)) {
        .error_union => |info| info.error_set!void,
        .void => void,
        else => @compileError("a state preparation returns void or an error union of void"),
    };
}

/// The stage a destination pointer names, when it is a stage of `M` at `want`.
fn Destination(comptime M: type, comptime Pointer: type, comptime want: M.State) type {
    const pointee = switch (@typeInfo(Pointer)) {
        .pointer => |info| if (info.size == .one) info.child else void,
        else => void,
    };
    const stage = @typeInfo(pointee) == .@"struct" and @hasDecl(pointee, "Machine") and pointee.Machine == M and pointee.state == want;
    if (!stage) @compileError("state: the destination of this transition is a pointer to the stage at ." ++ @tagName(want));
    return pointee;
}

/// One payload at state `s` of machine `M`. The stage moves to the next only by `transition` along a
/// declared edge, which consumes this one. Zig still lets a caller copy a stage and keep using the old
/// binding; Debug catches a use after the payload moved on, and no build mode claims more than that.
/// In every build but Debug the stage is exactly its payload.
pub fn At(comptime M: type, comptime P: type, comptime s: M.State) type {
    return struct {
        const Self = @This();
        /// The machine this stage belongs to.
        pub const Machine = M;
        /// The state this stage is at.
        pub const state: M.State = s;
        /// Private: reach it through `get`, `getConst` or `take`.
        payload: P,
        /// Private: Debug-only, false once the payload has moved on.
        live: if (diagnostics) bool else void = if (diagnostics) true else {},

        /// The first stage, holding a copy of `payload`. Every later stage is reached by transition.
        pub fn init(payload: P) Self {
            if (comptime s != M.initial) @compileError("state: only the initial stage is constructed; later stages are reached by transition");
            return .{ .payload = payload };
        }

        /// The first stage, taking the payload from `source` by its `moveInto` when `P` declares one and
        /// consuming the source, for a payload that must not exist twice.
        pub fn initFrom(source: *P) Self {
            if (comptime s != M.initial) @compileError("state: only the initial stage is constructed; later stages are reached by transition");
            var self: Self = .{ .payload = undefined };
            move(P, source, &self.payload);
            return self;
        }

        fn check(self: *const Self) void {
            if (diagnostics and !self.live) @panic("state stage used after its payload moved on");
        }

        /// The payload, borrowed until this stage transitions or its payload is taken.
        pub fn get(self: *Self) *P {
            self.check();
            return &self.payload;
        }

        pub fn getConst(self: *const Self) *const P {
            self.check();
            return &self.payload;
        }

        /// Moves the payload out of a terminal stage, which ends it. A payload leaves no other stage:
        /// declare an edge to a terminal state to give up early.
        pub fn take(self: *Self, destination: *P) void {
            if (comptime !M.isTerminal(s)) @compileError("state: a payload is taken from a terminal stage; ." ++ @tagName(s) ++ " is not terminal");
            self.check();
            move(P, &self.payload, destination);
            if (diagnostics) self.live = false;
        }

        fn Next(comptime event: M.Event) type {
            return M.At(M.after(s, event), P);
        }

        fn apart(self: *const Self, destination: anytype) void {
            if (checked and @TypeOf(destination) == *Self and destination == self) @panic("state transition destination is its own source");
        }

        /// Takes the edge `event` declared from this state: the payload moves into `destination`, which is
        /// uninitialized or moved-from storage apart from this stage, and this stage is consumed. Nothing
        /// is observable before the move; a self edge needs a second stage to land in.
        pub fn transition(self: *Self, comptime event: M.Event, destination: *Next(event)) void {
            self.check();
            self.apart(destination);
            move(P, &self.payload, &destination.payload);
            if (diagnostics) {
                destination.live = true;
                self.live = false;
            }
        }

        /// Like `transition` for a destination whose payload differs. `prepare(context, source, target)`
        /// builds the target payload from the source and is the only fallible step: on an error this stage
        /// is untouched and still at its state and the destination stays uninitialized, so a failed
        /// preparation leaves nothing half done. On success it must have moved out of the source whatever
        /// the target now owns, and this stage is consumed.
        pub fn transitionWith(self: *Self, comptime event: M.Event, destination: anytype, context: anytype, comptime prepare: anytype) Prepared(prepare) {
            const D = Destination(M, @TypeOf(destination), M.after(s, event));
            self.check();
            self.apart(destination);
            const target = &@as(*D, destination).payload;
            if (comptime @typeInfo(Prepared(prepare)) == .error_union) try prepare(context, &self.payload, target) else prepare(context, &self.payload, target);
            if (diagnostics) {
                destination.live = true;
                self.live = false;
            }
        }
    };
}
