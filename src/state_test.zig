const std = @import("std");
const builtin = @import("builtin");
const shake = @import("shakedown");
const a = @import("root.zig");
const state = a.state;
const t = std.testing;

const States = enum { idle, dialing, open, closed };
const Events = enum { dial, up, down, close };
const link_edges = [_]state.Edge(States, Events){
    .{ .from = .idle, .on = .dial, .to = .dialing },
    .{ .from = .dialing, .on = .up, .to = .open },
    .{ .from = .dialing, .on = .down, .to = .closed },
    .{ .from = .open, .on = .close, .to = .closed },
    .{ .from = .open, .on = .down, .to = .dialing },
};
const Link = state.Machine(States, Events, .{ .initial = .idle, .terminal = &.{.closed}, .edges = &link_edges });

/// An owner that must exist once: moving it counts and poisons the source.
const Token = struct {
    value: u32,
    moves: u32 = 0,
    pub fn moveInto(self: *Token, destination: *Token) void {
        destination.* = .{ .value = self.value, .moves = self.moves + 1 };
        self.value = 0xdead;
    }
};

fn expected(from: States, on: Events) ?States {
    for (link_edges) |edge| if (edge.from == from and edge.on == on) return edge.to;
    return null;
}

test "A10 the table answers every state and event exactly as the declared edges" {
    inline for (@typeInfo(States).@"enum".field_values) |sf| {
        inline for (@typeInfo(Events).@"enum".field_values) |ef| {
            const from: States = @fromBackingInt(@intCast(sf));
            const on: Events = @fromBackingInt(@intCast(ef));
            try t.expectEqual(expected(from, on), Link.next(from, on));
            if (comptime expected(from, on)) |to| try t.expectEqual(to, comptime Link.after(from, on));
        }
        try t.expectEqual(@as(States, @fromBackingInt(@intCast(sf))) == .closed, Link.isTerminal(@fromBackingInt(@intCast(sf))));
    }
    try t.expectEqual(States.idle, Link.initial);
}

test "A10 a stage is its payload outside Debug and costs one flag inside" {
    const Open = Link.At(.open, u64);
    if (builtin.mode == .debug) try t.expect(@sizeOf(Open) >= @sizeOf(u64)) else {
        try t.expectEqual(@sizeOf(u64), @sizeOf(Open));
        try t.expectEqual(@alignOf(u64), @alignOf(Open));
        try t.expectEqual(0, @sizeOf(Link.At(.closed, void)));
    }
    try t.expectEqual(States.open, Open.state);
    try t.expect(Open.Machine == Link);
    try t.expect(Link.At(.open, u64) == Open);
}

test "A10 a transition moves the payload once along the declared edge" {
    var token: Token = .{ .value = 7 };
    var idle = Link.At(.idle, Token).initFrom(&token);
    try t.expectEqual(@as(u32, 0xdead), token.value);
    try t.expectEqual(@as(u32, 1), idle.getConst().moves);
    var dialing: Link.At(.dialing, Token) = undefined;
    idle.transition(.dial, &dialing);
    try t.expectEqual(@as(u32, 7), dialing.get().value);
    try t.expectEqual(@as(u32, 2), dialing.getConst().moves);
    var open: Link.At(.open, Token) = undefined;
    dialing.transition(.up, &open);
    var closed: Link.At(.closed, Token) = undefined;
    open.transition(.close, &closed);
    var out: Token = undefined;
    closed.take(&out);
    try t.expectEqual(@as(u32, 7), out.value);
    try t.expectEqual(@as(u32, 5), out.moves);
}

const Echo = state.Machine(enum { listening, done }, enum { accept, stop }, .{
    .initial = .listening,
    .terminal = &.{.done},
    .edges = &.{
        .{ .from = .listening, .on = .accept, .to = .listening },
        .{ .from = .listening, .on = .stop, .to = .done },
    },
});

test "A10 a self edge lands in a second stage and plain payloads copy" {
    var first = Echo.At(.listening, u32).init(41);
    var second: Echo.At(.listening, u32) = undefined;
    first.transition(.accept, &second);
    second.get().* += 1;
    var done: Echo.At(.done, u32) = undefined;
    second.transition(.stop, &done);
    var out: u32 = undefined;
    done.take(&out);
    try t.expectEqual(@as(u32, 42), out);
}

fn upgrade(offset: u32, source: *Token, target: *u64) error{Refused}!void {
    if (source.value == 0) return error.Refused;
    target.* = @as(u64, source.value) + offset;
    source.value = 0;
}

test "A10 a refused preparation leaves the source staged and the destination unwritten" {
    var idle = Link.At(.idle, Token).init(.{ .value = 0 });
    var dialing: Link.At(.dialing, Token) = undefined;
    idle.transition(.dial, &dialing);
    var open: Link.At(.open, u64) = undefined;
    open.payload = 0x5eed; // marker in the uninitialized destination
    try t.expectError(error.Refused, dialing.transitionWith(.up, &open, @as(u32, 5), upgrade));
    try t.expectEqual(@as(u32, 0), dialing.get().value);
    try t.expectEqual(@as(u64, 0x5eed), open.payload);
    dialing.get().value = 9;
    try dialing.transitionWith(.up, &open, @as(u32, 5), upgrade);
    try t.expectEqual(@as(u64, 14), open.get().*);
    try t.expectEqual(@as(u32, 0), dialing.payload.value);
}

fn infallible(_: void, source: *u8, target: *u16) void {
    target.* = @as(u16, source.*) * 2;
}

test "A10 an infallible preparation has no error set" {
    var idle = Link.At(.idle, u8).init(21);
    var dialing: Link.At(.dialing, u16) = undefined;
    idle.transitionWith(.dial, &dialing, {}, infallible);
    try t.expectEqual(@as(u16, 42), dialing.getConst().*);
}

test "A10 runtime illegal events are typed errors that change nothing" {
    var link = Link.Runtime(u32).init(3);
    try t.expectEqual(States.idle, link.current());
    try t.expectError(error.IllegalEvent, link.step(.up));
    try t.expectError(error.IllegalEvent, link.plan(.close));
    try t.expectEqual(States.idle, link.current());
    const first = try link.step(.dial);
    try t.expectEqual(States.idle, first.from);
    try t.expectEqual(Events.dial, first.on);
    try t.expectEqual(States.dialing, first.to);
    _ = try link.step(.up);
    _ = try link.step(.close);
    try t.expect(link.isTerminal());
    inline for (@typeInfo(Events).@"enum".field_values) |ef| try t.expectError(error.IllegalEvent, link.step(@fromBackingInt(@intCast(ef))));
    try t.expectEqual(@as(u32, 3), link.payload);
}

test "A10 a planned edge commits once and is stale after the machine moved on" {
    var link = Link.Runtime(void).init({});
    _ = try link.step(.dial);
    const pending = try link.plan(.up);
    try t.expectEqual(States.dialing, link.current());
    _ = try link.step(.down); // the peer gave up while the work was in flight
    try t.expectError(error.Stale, link.commit(pending));
    try t.expectEqual(States.closed, link.current());
    var other = Link.Runtime(void).init({});
    _ = try other.step(.dial);
    const again = try other.plan(.up);
    try other.commit(again);
    try t.expectEqual(States.open, other.current());
    try t.expectError(error.Stale, other.commit(again));
}

const Oracle = struct {
    state: States = .idle,
    fn step(self: *Oracle, on: Events) bool {
        const to = expected(self.state, on) orelse return false;
        self.state = to;
        return true;
    }
};

fn trace(_: void, case: *shake.Case) anyerror!void {
    var link = Link.Runtime(u8).init(0);
    var oracle: Oracle = .{};
    for (0..64) |_| {
        const on: Events = @fromBackingInt(@intCast(shake.gen.intRange(case.source, u8, 0, @typeInfo(Events).@"enum".field_names.len - 1)));
        const before = link.current();
        const legal = oracle.step(on);
        const result = link.step(on);
        if (legal) {
            const edge = try result;
            try t.expectEqual(before, edge.from);
            try t.expectEqual(oracle.state, edge.to);
        } else {
            try t.expectError(error.IllegalEvent, result);
            try t.expectEqual(before, link.current());
        }
        try t.expectEqual(oracle.state, link.current());
        if (link.isTerminal()) break;
    }
}

test "A10 generated event traces agree with an independent model" {
    try shake.check(t.allocator, {}, trace, .{ .cases = 512, .seed = 0xa10 });
}

test "A10 a wide machine builds and answers by its table" {
    const Wide = enum { s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15 };
    const Ev = enum { a, b, c };
    const edges = comptime blk: {
        var list: [16 * 2]state.Edge(Wide, Ev) = undefined;
        for (0..16) |i| {
            list[i * 2] = .{ .from = @fromBackingInt(@intCast(i)), .on = .a, .to = @fromBackingInt(@intCast((i + 1) % 16)) };
            list[i * 2 + 1] = .{ .from = @fromBackingInt(@intCast(i)), .on = .b, .to = @fromBackingInt(@intCast(i)) };
        }
        break :blk list;
    };
    const Ring = state.Machine(Wide, Ev, .{ .initial = .s0, .edges = &edges });
    var ring = Ring.Runtime(void).init({});
    for (0..32) |_| _ = try ring.step(.a);
    try t.expectEqual(Wide.s0, ring.current());
    try t.expectError(error.IllegalEvent, ring.step(.c));
    try t.expect(!Ring.isTerminal(.s3));
}

const Wire = state.Machine(enum { waiting, talking, done, failed }, enum(u8) { hello = 0x10, data = 0x20, bye = 0x30, oops = 0xf0 }, .{
    .initial = .waiting,
    .terminal = &.{ .done, .failed },
    .edges = &.{
        .{ .from = .waiting, .on = .hello, .to = .talking },
        .{ .from = .talking, .on = .data, .to = .talking },
        .{ .from = .talking, .on = .bye, .to = .done },
        .{ .from = .waiting, .on = .oops, .to = .failed },
        .{ .from = .talking, .on = .oops, .to = .failed },
    },
});

test "A10 events with sparse wire values and several terminal states" {
    var wire = Wire.Runtime(void).init({});
    try t.expectError(error.IllegalEvent, wire.step(.bye));
    _ = try wire.step(.hello);
    _ = try wire.step(.data);
    try t.expect(!wire.isTerminal());
    _ = try wire.step(.oops);
    try t.expectEqual(@as(@TypeOf(wire.current()), .failed), wire.current());
    try t.expect(wire.isTerminal() and Wire.isTerminal(.done) and !Wire.isTerminal(.talking));
    try t.expectError(error.IllegalEvent, wire.step(.data));
}

fn Members(comptime n: usize, comptime descending: bool) type {
    @setEvalBranchQuota(1_000_000);
    const Tag = std.math.IntFittingRange(0, n + 1);
    var names: [n][]const u8 = undefined;
    var values: [n]Tag = undefined;
    for (0..n) |i| {
        names[i] = std.fmt.comptimePrint("s{d}", .{i});
        values[i] = @intCast(if (descending) n - i else i);
    }
    return @Enum(Tag, .exhaustive, &names, &values);
}

fn Chain(comptime n: usize, comptime descending: bool) type {
    const Forward = enum { forward };
    const Ring = Members(n, descending);
    const edges = comptime blk: {
        @setEvalBranchQuota(1_000_000);
        const values = @typeInfo(Ring).@"enum".field_values;
        var list: [n]state.Edge(Ring, Forward) = undefined;
        for (&list, 0..) |*edge, i| edge.* = .{ .from = @fromBackingInt(values[i]), .on = .forward, .to = @fromBackingInt(values[(i + 1) % n]) };
        break :blk list;
    };
    return state.Machine(Ring, Forward, .{ .initial = @fromBackingInt(@typeInfo(Ring).@"enum".field_values[0]), .edges = &edges });
}

test "A10 large machines use wider cells and map sparse state values" {
    inline for (.{ .{ 300, false }, .{ 300, true }, .{ 40, true } }) |shape| {
        const Big = Chain(shape[0], shape[1]);
        var link = Big.Runtime(void).init({});
        for (0..shape[0] * 2 + 3) |_| _ = try link.step(.forward);
        const position = (shape[0] * 2 + 3) % shape[0];
        const value = if (shape[1]) shape[0] - position else position;
        try t.expectEqual(@as(usize, value), @as(usize, @backingInt(link.current())));
    }
}
