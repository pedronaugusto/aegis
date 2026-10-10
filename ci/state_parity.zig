//! A10 paired exports: the hand-written operation and the same operation through the typestate API.
const std = @import("std");
const c = @import("state.zig");

export fn baselineStateNext(s: c.State, e: c.Event) i16 {
    return c.next(false, s, e);
}
export fn wrapperStateNext(s: c.State, e: c.Event) i16 {
    return c.next(true, s, e);
}
export fn baselineStateNextWide(s: c.Handshake.State, e: c.Handshake.Event) i16 {
    return c.nextWide(false, s, e);
}
export fn wrapperStateNextWide(s: c.Handshake.State, e: c.Handshake.Event) i16 {
    return c.nextWide(true, s, e);
}
export fn baselineStateNextSwitch(s: c.State, e: c.Event) i16 {
    return c.nextSwitch(false, s, e);
}
export fn wrapperStateNextSwitch(s: c.State, e: c.Event) i16 {
    return c.nextSwitch(true, s, e);
}
export fn baselineStateNextWideSwitch(s: c.Handshake.State, e: c.Handshake.Event) i16 {
    return c.nextWideSwitch(false, s, e);
}
export fn wrapperStateNextWideSwitch(s: c.Handshake.State, e: c.Handshake.Event) i16 {
    return c.nextWideSwitch(true, s, e);
}
export fn baselineStateTerminal(s: c.State) bool {
    return c.terminal(false, s);
}
export fn wrapperStateTerminal(s: c.State) bool {
    return c.terminal(true, s);
}
export fn baselineStateStep(machine: *c.DirectRuntime, e: c.Event) i16 {
    return c.step(false, machine, e);
}
export fn wrapperStateStep(machine: *c.Runtime, e: c.Event) i16 {
    return c.step(true, machine, e);
}
export fn baselineStatePlanCommit(machine: *c.DirectRuntime, e: c.Event) i16 {
    return c.planCommit(false, machine, e);
}
export fn wrapperStatePlanCommit(machine: *c.Runtime, e: c.Event) i16 {
    return c.planCommit(true, machine, e);
}
export fn baselineStateTransition(source: *c.Key, destination: *c.Key) void {
    c.transition(false, source, destination);
}
export fn wrapperStateTransition(source: *c.Idle, destination: *c.Dialing) void {
    c.transition(true, source, destination);
}
export fn baselineStateTransitionWith(source: *c.Key, destination: *c.Session, epoch: u32) bool {
    return c.transitionWith(false, source, destination, epoch);
}
export fn wrapperStateTransitionWith(source: *c.Dialing, destination: *c.Open, epoch: u32) bool {
    return c.transitionWith(true, source, destination, epoch);
}
export fn baselineStateTake(source: *c.Key, destination: *c.Key) void {
    c.take(false, source, destination);
}
export fn wrapperStateTake(source: *c.Closed, destination: *c.Key) void {
    c.take(true, source, destination);
}
comptime {
    std.debug.assert(@sizeOf(c.Runtime) == @sizeOf(c.DirectRuntime));
    std.debug.assert(@alignOf(c.Runtime) == @alignOf(c.DirectRuntime));
    std.debug.assert(@sizeOf(c.Idle) == @sizeOf(c.Key));
    std.debug.assert(@alignOf(c.Idle) == @alignOf(c.Key));
    std.debug.assert(@sizeOf(c.Open) == @sizeOf(c.Session));
    std.debug.assert(@alignOf(c.Open) == @alignOf(c.Session));
    std.debug.assert(@sizeOf(c.Closed) == @sizeOf(c.Key));
}
