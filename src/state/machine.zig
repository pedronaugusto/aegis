//! The validated topology: one deterministic edge per state and event, every state reachable.
const builtin = @import("builtin");
const std = @import("std");
const stage = @import("stage.zig");
const runtime = @import("runtime.zig");
const edge = @import("edge.zig");

/// The specification a machine is built from. Terminal states end the machine and have no edges out.
pub fn Spec(comptime S: type, comptime E: type) type {
    return struct { initial: S, terminal: []const S = &.{}, edges: []const edge.Edge(S, E) };
}

fn count(comptime T: type, comptime what: []const u8) usize {
    const info = @typeInfo(T);
    if (info != .@"enum" or info.@"enum".mode != .exhaustive) @compileError("state.Machine: " ++ what ++ " must be an exhaustive enum");
    if (info.@"enum".field_names.len == 0) @compileError("state.Machine: " ++ what ++ " has no members");
    return info.@"enum".field_names.len;
}

fn index(comptime T: type, comptime value: T) usize {
    @setEvalBranchQuota(64 + 4 * @typeInfo(T).@"enum".field_values.len);
    for (@typeInfo(T).@"enum".field_values, 0..) |v, i| if (v == @backingInt(value)) return i;
    unreachable;
}

/// Whether the enum's values are 0, 1, 2, ... in declaration order, so a value is its own position.
fn dense(comptime T: type) bool {
    for (@typeInfo(T).@"enum".field_values, 0..) |v, i| if (v != i) return false;
    return true;
}

/// A value's position among the enum's members, at run time.
inline fn position(comptime T: type, value: T) usize {
    if (comptime dense(T)) return @backingInt(value);
    const values = @typeInfo(T).@"enum".field_values;
    @setEvalBranchQuota(64 + 4 * values.len);
    inline for (values, 0..) |v, i| if (@backingInt(value) == v) return i;
    unreachable;
}

/// A table cell: a state's position or one past the last, in whole bytes so a lookup is a plain byte load.
fn Position(comptime states: usize) type {
    return @Int(.unsigned, (@bitSizeOf(std.math.IntFittingRange(0, states)) + 7) / 8 * 8);
}

fn Table(comptime S: type, comptime E: type) type {
    return [count(S, "the states")][count(E, "the events")]?S;
}

fn name(comptime value: anytype) []const u8 {
    return "." ++ @tagName(value);
}

/// The transition table, or the first reason the specification is not a machine.
fn build(comptime S: type, comptime E: type, comptime spec: Spec(S, E)) Table(S, E) {
    const states = count(S, "the states");
    const events = count(E, "the events");
    @setEvalBranchQuota(10_000 + 8 * states * states * events + 8 * spec.edges.len * (spec.terminal.len + 1));
    var table: Table(S, E) = undefined;
    for (&table) |*row| row.* = @splat(null);
    for (spec.edges) |declared| {
        const slot = &table[index(S, declared.from)][index(E, declared.on)];
        if (slot.* != null) @compileError("state.Machine: duplicate edge from " ++ name(declared.from) ++ " on " ++ name(declared.on));
        slot.* = declared.to;
    }
    var ends: [states]bool = @splat(false);
    for (spec.terminal) |t| {
        if (ends[index(S, t)]) @compileError("state.Machine: terminal state " ++ name(t) ++ " is listed twice");
        ends[index(S, t)] = true;
    }
    if (ends[index(S, spec.initial)]) @compileError("state.Machine: the initial state " ++ name(spec.initial) ++ " is terminal");
    var reached: [states]bool = @splat(false);
    reached[index(S, spec.initial)] = true;
    var changed = true;
    while (changed) {
        changed = false;
        for (table, 0..) |row, from| {
            if (!reached[from]) continue;
            for (row) |maybe| {
                const to = index(S, maybe orelse continue);
                if (!reached[to]) {
                    reached[to] = true;
                    changed = true;
                }
            }
        }
    }
    for (@typeInfo(S).@"enum".field_values, 0..) |field, i| {
        const value: S = @fromBackingInt(@intCast(field));
        var edges_out: usize = 0;
        for (table[i]) |maybe| edges_out += @intFromBool(maybe != null);
        if (ends[i] and edges_out != 0) @compileError("state.Machine: terminal state " ++ name(value) ++ " has an edge out");
        if (!ends[i] and edges_out == 0) @compileError("state.Machine: state " ++ name(value) ++ " has no edge out and is not terminal");
        if (!reached[i]) @compileError("state.Machine: state " ++ name(value) ++ " is not reachable from " ++ name(spec.initial));
    }
    return table;
}

/// A deterministic state machine over exhaustive enums `S` and `E`. Specification mistakes are compile
/// errors: a duplicate edge from the same state on the same event, a terminal state with an edge out, a
/// state with no edge out that is not terminal, a state no edge reaches from the initial one, or an
/// initial state that is terminal. Machines that differ by role or version declare their own enums.
///
/// The table proves the shape of the protocol and nothing about the world: that an event is genuine,
/// ordered or authorized is the consumer's check, made before it takes the edge.
pub fn Machine(comptime S: type, comptime E: type, comptime spec: Spec(S, E)) type {
    const table = comptime build(S, E, spec);
    const states = count(S, "the states");
    const events = count(E, "the events");
    const Cell = Position(states);
    const none: Cell = states;
    const cells = comptime blk: {
        var out: [states][events]Cell = undefined;
        for (table, 0..) |row, from| for (row, 0..) |maybe, on| {
            out[from][on] = if (maybe) |to| index(S, to) else none;
        };
        break :blk out;
    };
    const ends = comptime blk: {
        var out: [states]bool = @splat(false);
        for (spec.terminal) |t| out[index(S, t)] = true;
        break :blk out;
    };
    const members = comptime blk: {
        var out: [states]S = undefined;
        for (@typeInfo(S).@"enum".field_values, 0..) |v, i| out[i] = @fromBackingInt(v);
        break :blk out;
    };
    return struct {
        const Self = @This();
        pub const State = S;
        pub const Event = E;
        pub const Edge = edge.Edge(S, E);
        pub const initial: S = spec.initial;

        /// The state `event` leads to from `from`, or null when no edge is declared: one load from a table
        /// validated when the machine was analyzed, with no branch on the state or the event.
        pub inline fn next(from: S, event: E) ?S {
            // safe: both positions come from valid enum values and the cell from the validated table, so
            // the bounds and range checks cannot fail; Debug keeps them
            @setRuntimeSafety(builtin.mode == .debug);
            const cell = cells[position(S, from)][position(E, event)];
            if (cell == none) return null;
            // safe: the cell is a state's position, which is its value in a dense enum, so it fits the tag
            return if (comptime dense(S)) @fromBackingInt(@as(@typeInfo(S).@"enum".tag_type, @intCast(cell))) else members[cell];
        }

        /// The state `event` leads to from `from`, known at comptime; an undeclared edge does not compile.
        pub fn after(comptime from: S, comptime event: E) S {
            return table[index(S, from)][index(E, event)] orelse
                @compileError("state: no edge from " ++ name(from) ++ " on " ++ name(event));
        }

        /// Whether `value` ends the machine: a comparison for one terminal state, a table lookup for several.
        pub inline fn isTerminal(value: S) bool {
            if (comptime spec.terminal.len == 0) return false;
            if (comptime spec.terminal.len == 1) return value == spec.terminal[0];
            // safe: the position comes from a valid enum value, so the bounds check cannot fail; Debug keeps it
            @setRuntimeSafety(builtin.mode == .debug);
            return ends[position(S, value)];
        }

        /// A payload staged at `state`: the stage is part of the type, so a function that takes
        /// `At(.open, Payload)` cannot be called with a payload that has not reached `.open`.
        pub fn At(comptime state: S, comptime Payload: type) type {
            return stage.At(Self, Payload, state);
        }

        /// A payload beside its current state, advanced by events that arrive at run time and checked
        /// against the table in every build mode.
        pub fn Runtime(comptime Payload: type) type {
            return runtime.Runtime(Self, Payload);
        }
    };
}
