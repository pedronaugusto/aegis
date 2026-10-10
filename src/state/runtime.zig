//! A payload beside its current state, advanced by events that arrive at run time.

/// The machine's state and a payload. The table is checked in every build mode: an event the machine
/// does not declare from the current state is an error and changes nothing, since it comes from the peer
/// and not from a programmer. One driver owns a runtime machine; enum states are no thread-safety claim.
pub fn Runtime(comptime M: type, comptime P: type) type {
    return struct {
        const Self = @This();
        pub const Error = error{IllegalEvent};
        pub const CommitError = error{Stale};
        /// The consumer's data. The machine neither moves nor inspects it.
        payload: P,
        /// Private: advanced only by `step` and `commit`.
        state: M.State = M.initial,

        pub fn init(payload: P) Self {
            return .{ .payload = payload };
        }

        pub fn current(self: *const Self) M.State {
            return self.state;
        }

        pub fn isTerminal(self: *const Self) bool {
            return M.isTerminal(self.state);
        }

        /// The edge `event` would take from the current state, without taking it. For work that can fail or
        /// suspend between deciding and committing: plan, do the work, then `commit`.
        pub fn plan(self: *const Self, event: M.Event) Error!M.Edge {
            return .{ .from = self.state, .on = event, .to = M.next(self.state, event) orelse return error.IllegalEvent };
        }

        /// Takes a planned edge. `Stale` when the machine has left the state the plan was made in, as a
        /// completion does that arrives after the machine was cancelled or has moved on. The plan is a
        /// state and an event, so a machine that came back to the same state accepts it again.
        pub fn commit(self: *Self, edge: M.Edge) CommitError!void {
            if (self.state != edge.from) return error.Stale;
            const to = M.next(edge.from, edge.on) orelse @panic("state commit of an edge the machine does not declare");
            if (to != edge.to) @panic("state commit of an edge the machine does not declare");
            self.state = to;
        }

        /// Plans and takes the edge in one step. An undeclared event is an error and changes nothing.
        pub fn step(self: *Self, event: M.Event) Error!M.Edge {
            const from = self.state;
            const to = M.next(from, event) orelse return error.IllegalEvent;
            self.state = to;
            return .{ .from = from, .on = event, .to = to };
        }
    };
}
