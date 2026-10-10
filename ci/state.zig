//! Necessary handwritten operations paired with typestate machines, stages and the runtime table.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");

pub const Link = a.state.Machine(enum(u8) { idle, dialing, open, closed }, enum(u8) { dial, up, down, close }, .{
    .initial = .idle,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .idle, .on = .dial, .to = .dialing },
        .{ .from = .dialing, .on = .up, .to = .open },
        .{ .from = .dialing, .on = .down, .to = .closed },
        .{ .from = .open, .on = .close, .to = .closed },
        .{ .from = .open, .on = .down, .to = .dialing },
    },
});
pub const State = Link.State;
pub const Event = Link.Event;

/// A client handshake: eight states, seven events.
pub const Handshake = a.state.Machine(enum(u8) { start, hello_sent, hello_received, certificate, key_exchange, finished_sent, established, closed }, enum(u8) { send_hello, recv_hello, recv_cert, recv_key, recv_finished, close, alert }, .{
    .initial = .start,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .start, .on = .send_hello, .to = .hello_sent },
        .{ .from = .hello_sent, .on = .recv_hello, .to = .hello_received },
        .{ .from = .hello_received, .on = .recv_cert, .to = .certificate },
        .{ .from = .hello_received, .on = .recv_key, .to = .key_exchange },
        .{ .from = .certificate, .on = .recv_key, .to = .key_exchange },
        .{ .from = .key_exchange, .on = .recv_finished, .to = .finished_sent },
        .{ .from = .finished_sent, .on = .recv_finished, .to = .established },
        .{ .from = .established, .on = .close, .to = .closed },
        .{ .from = .hello_sent, .on = .alert, .to = .closed },
        .{ .from = .hello_received, .on = .alert, .to = .closed },
        .{ .from = .certificate, .on = .alert, .to = .closed },
        .{ .from = .key_exchange, .on = .alert, .to = .closed },
        .{ .from = .finished_sent, .on = .alert, .to = .closed },
    },
});

/// The hand-written table of `Link`: row by state, column by event, the next state or `link_no`, one past the last state.
const link_no: u8 = 4;
const link_table = [4][4]u8{
    .{ 1, link_no, link_no, link_no }, // idle: dial
    .{ link_no, 2, 3, link_no }, // dialing: up, down
    .{ link_no, link_no, 1, 3 }, // open: down, close
    .{ link_no, link_no, link_no, link_no }, // closed
};
/// The hand-written table of `Handshake`.
const handshake_no: u8 = 8;
const handshake_table = [8][7]u8{
    .{ 1, handshake_no, handshake_no, handshake_no, handshake_no, handshake_no, handshake_no }, // start: send_hello
    .{ handshake_no, 2, handshake_no, handshake_no, handshake_no, handshake_no, 7 }, // hello_sent: recv_hello, alert
    .{ handshake_no, handshake_no, 3, 4, handshake_no, handshake_no, 7 }, // hello_received: recv_cert, recv_key, alert
    .{ handshake_no, handshake_no, handshake_no, 4, handshake_no, handshake_no, 7 }, // certificate: recv_key, alert
    .{ handshake_no, handshake_no, handshake_no, handshake_no, 5, handshake_no, 7 }, // key_exchange: recv_finished, alert
    .{ handshake_no, handshake_no, handshake_no, handshake_no, 6, handshake_no, 7 }, // finished_sent: recv_finished, alert
    .{ handshake_no, handshake_no, handshake_no, handshake_no, handshake_no, 7, handshake_no }, // established: close
    .{ handshake_no, handshake_no, handshake_no, handshake_no, handshake_no, handshake_no, handshake_no }, // closed
};

/// The transition function of `Link` as a developer would write it by hand with a table.
pub inline fn directLink(s: State, e: Event) ?State {
    @setRuntimeSafety(builtin.mode == .debug);
    const to = link_table[@backingInt(s)][@backingInt(e)];
    return if (to == link_no) null else @fromBackingInt(to);
}

/// The transition function of `Handshake` with a table.
pub inline fn directHandshake(s: Handshake.State, e: Handshake.Event) ?Handshake.State {
    @setRuntimeSafety(builtin.mode == .debug);
    const to = handshake_table[@backingInt(s)][@backingInt(e)];
    return if (to == handshake_no) null else @fromBackingInt(to);
}

/// The transition function of `Link` as a nested switch: exhaustive switches, no else prong, so a new state or
/// event cannot be forgotten.
pub inline fn switchLink(s: State, e: Event) ?State {
    return switch (s) {
        .idle => switch (e) {
            .dial => .dialing,
            .up, .down, .close => null,
        },
        .dialing => switch (e) {
            .up => .open,
            .down => .closed,
            .dial, .close => null,
        },
        .open => switch (e) {
            .close => .closed,
            .down => .dialing,
            .dial, .up => null,
        },
        .closed => null,
    };
}

/// The transition function of `Handshake`, exhaustive in the same way.
pub inline fn switchHandshake(s: Handshake.State, e: Handshake.Event) ?Handshake.State {
    return switch (s) {
        .start => switch (e) {
            .send_hello => .hello_sent,
            .recv_hello, .recv_cert, .recv_key, .recv_finished, .close, .alert => null,
        },
        .hello_sent => switch (e) {
            .recv_hello => .hello_received,
            .alert => .closed,
            .send_hello, .recv_cert, .recv_key, .recv_finished, .close => null,
        },
        .hello_received => switch (e) {
            .recv_cert => .certificate,
            .recv_key => .key_exchange,
            .alert => .closed,
            .send_hello, .recv_hello, .recv_finished, .close => null,
        },
        .certificate => switch (e) {
            .recv_key => .key_exchange,
            .alert => .closed,
            .send_hello, .recv_hello, .recv_cert, .recv_finished, .close => null,
        },
        .key_exchange => switch (e) {
            .recv_finished => .finished_sent,
            .alert => .closed,
            .send_hello, .recv_hello, .recv_cert, .recv_key, .close => null,
        },
        .finished_sent => switch (e) {
            .recv_finished => .established,
            .alert => .closed,
            .send_hello, .recv_hello, .recv_cert, .recv_key, .close => null,
        },
        .established => switch (e) {
            .close => .closed,
            .send_hello, .recv_hello, .recv_cert, .recv_key, .recv_finished, .alert => null,
        },
        .closed => null,
    };
}

pub fn next(comptime wrapped: bool, s: State, e: Event) i16 {
    const to = (if (wrapped) Link.next(s, e) else directLink(s, e)) orelse return -1;
    return @backingInt(to);
}

pub fn nextWide(comptime wrapped: bool, s: Handshake.State, e: Handshake.Event) i16 {
    const to = (if (wrapped) Handshake.next(s, e) else directHandshake(s, e)) orelse return -1;
    return @backingInt(to);
}

/// Against the idiomatic nested switch, which the table must not exceed.
pub fn nextSwitch(comptime wrapped: bool, s: State, e: Event) i16 {
    const to = (if (wrapped) Link.next(s, e) else switchLink(s, e)) orelse return -1;
    return @backingInt(to);
}

pub fn nextWideSwitch(comptime wrapped: bool, s: Handshake.State, e: Handshake.Event) i16 {
    const to = (if (wrapped) Handshake.next(s, e) else switchHandshake(s, e)) orelse return -1;
    return @backingInt(to);
}

pub fn terminal(comptime wrapped: bool, s: State) bool {
    return if (wrapped) Link.isTerminal(s) else s == .closed;
}

pub const DirectRuntime = struct { payload: u32, state: State = .idle };
pub const Runtime = Link.Runtime(u32);
pub fn Machine(comptime wrapped: bool) type {
    return if (wrapped) Runtime else DirectRuntime;
}

pub const DirectEdge = struct { from: State, on: Event, to: State };
fn directStep(machine: *DirectRuntime, event: Event) error{IllegalEvent}!DirectEdge {
    const from = machine.state;
    const to = directLink(from, event) orelse return error.IllegalEvent;
    machine.state = to;
    return .{ .from = from, .on = event, .to = to };
}

pub fn step(comptime wrapped: bool, machine: *Machine(wrapped), event: Event) i16 {
    const edge = (if (wrapped) machine.step(event) else directStep(machine, event)) catch return -1;
    return @backingInt(edge.to);
}

/// Plan, do work the machine cannot see, then commit: the commit must re-read the state.
pub fn planCommit(comptime wrapped: bool, machine: *Machine(wrapped), event: Event) i16 {
    if (wrapped) {
        const edge = machine.plan(event) catch return -1;
        asm volatile ("" ::: .{ .memory = true });
        machine.commit(edge) catch return -2;
        return @backingInt(edge.to);
    }
    const from = machine.state;
    const to = directLink(from, event) orelse return -1;
    asm volatile ("" ::: .{ .memory = true });
    if (machine.state != from) return -2;
    machine.state = to;
    return @backingInt(to);
}

pub const Key = a.Secret([32]u8);
pub const Session = struct { key: Key, epoch: u32 };
pub const Idle = Link.At(.idle, Key);
pub const Dialing = Link.At(.dialing, Key);
pub const Open = Link.At(.open, Session);
pub const Closed = Link.At(.closed, Key);

pub fn transition(comptime wrapped: bool, source: if (wrapped) *Idle else *Key, destination: if (wrapped) *Dialing else *Key) void {
    if (wrapped) source.transition(.dial, destination) else source.moveInto(destination);
}

fn derive(epoch: u32, source: *Key, target: *Session) error{Refused}!void {
    if (epoch == 0) return error.Refused;
    source.moveInto(&target.key);
    target.epoch = epoch;
}

pub fn transitionWith(comptime wrapped: bool, source: if (wrapped) *Dialing else *Key, destination: if (wrapped) *Open else *Session, epoch: u32) bool {
    if (wrapped) {
        source.transitionWith(.up, destination, epoch, derive) catch return false;
    } else derive(epoch, source, destination) catch return false;
    return true;
}

pub fn take(comptime wrapped: bool, source: if (wrapped) *Closed else *Key, destination: *Key) void {
    if (wrapped) source.take(destination) else source.moveInto(destination);
}
