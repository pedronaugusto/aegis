//! A machine whose states carry their own payloads: a tagged union whose tag is the state.
const std = @import("std");
const move = @import("../move.zig");

/// What a release takes: the context it was given and the union in place, at the state being left.
fn Release(comptime Context: type, comptime U: type) type {
    return fn (Context, *U) void;
}

/// The machine's state as the tag of `U`, a union whose member at each state is what that state holds.
/// The tag and the payload cannot disagree, so no optional owner sits beside a flag. An edge is taken
/// only along the table, checked in every build mode: an event the current state does not declare, or one
/// that leads to a state other than the one `next` is at, is an error and changes nothing, since events
/// come from the peer. Taking an edge first ends the payload being left, in place, by the caller's
/// `release`, then stores `next`: an owner is never copied out of the machine, so one used where it is
/// held is released at the address it was used at. One driver owns a carrying machine; the union's tag
/// is no thread-safety claim.
pub fn Carrying(comptime M: type, comptime U: type) type {
    const info = switch (@typeInfo(U)) {
        .@"union" => |u| u,
        else => @compileError("state: a carrying machine's value is a tagged union whose tag is the machine's state"),
    };
    if (info.tag_type != M.State) @compileError("state: a carrying machine's union is tagged by the machine's state");
    return struct {
        const Self = @This();
        pub const Machine = M;
        pub const Value = U;
        pub const Error = error{IllegalEvent};
        pub const CommitError = error{Stale};

        /// What state `s` holds.
        pub fn Payload(comptime s: M.State) type {
            return @FieldType(U, @tagName(s));
        }

        /// Private: changed only by `step` and `commit`; read it through `current`, `at` and `atConst`.
        value: U,

        /// The machine at its initial state, holding a copy of `payload`.
        pub fn init(payload: Payload(M.initial)) Self {
            return .{ .value = @unionInit(U, @tagName(M.initial), payload) };
        }

        /// The machine at its initial state, taking the payload from `source` by its `moveInto` when it
        /// declares one and consuming the source, for a payload that must not exist twice.
        pub fn initFrom(source: *Payload(M.initial)) Self {
            var self: Self = .{ .value = @unionInit(U, @tagName(M.initial), undefined) };
            move.into(Payload(M.initial), source, &@field(self.value, @tagName(M.initial)));
            return self;
        }

        pub fn current(self: *const Self) M.State {
            return std.meta.activeTag(self.value);
        }

        pub fn isTerminal(self: *const Self) bool {
            return M.isTerminal(self.current());
        }

        /// The payload of state `s`, borrowed until the next edge, or null at any other state.
        pub fn at(self: *Self, comptime s: M.State) ?*Payload(s) {
            if (self.current() != s) return null;
            return &@field(self.value, @tagName(s));
        }

        pub fn atConst(self: *const Self, comptime s: M.State) ?*const Payload(s) {
            if (self.current() != s) return null;
            return &@field(self.value, @tagName(s));
        }

        /// The edge `event` would take from the current state, without taking it. For work that can fail or
        /// suspend between deciding and committing: plan, do the work, then `commit`.
        pub fn plan(self: *const Self, event: M.Event) Error!M.Edge {
            const from = self.current();
            return .{ .from = from, .on = event, .to = M.next(from, event) orelse return error.IllegalEvent };
        }

        /// Takes a planned edge into `next`, which is at the edge's destination: `release(context, &value)`
        /// ends the payload being left, in place, then `next` is stored. `Stale` when the machine has left the
        /// state the plan was made in; nothing is released then, and `next` is still the caller's.
        pub fn commit(self: *Self, edge: M.Edge, next: U, context: anytype, comptime release: Release(@TypeOf(context), U)) CommitError!void {
            if (self.current() != edge.from) return error.Stale;
            const to = M.next(edge.from, edge.on) orelse @panic("state commit of an edge the machine does not declare");
            if (to != edge.to) @panic("state commit of an edge the machine does not declare");
            if (std.meta.activeTag(next) != to) @panic("state commit into a value at a state other than the edge's");
            release(context, &self.value);
            self.value = next;
        }

        /// Plans and takes the edge in one step: `release(context, &value)` ends the payload being left, in
        /// place, then `next` is stored. An event the current state does not declare, or one that leads
        /// elsewhere than `next`'s state, is an error: nothing is released, and `next` is still the caller's.
        pub fn step(self: *Self, event: M.Event, next: U, context: anytype, comptime release: Release(@TypeOf(context), U)) Error!M.Edge {
            const from = self.current();
            const to = M.next(from, event) orelse return error.IllegalEvent;
            if (std.meta.activeTag(next) != to) return error.IllegalEvent;
            release(context, &self.value);
            self.value = next;
            return .{ .from = from, .on = event, .to = to };
        }
    };
}
