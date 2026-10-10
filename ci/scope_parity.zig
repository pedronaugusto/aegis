//! A12 paired exports: the hand-written operation and the same operation through the scope API.
const std = @import("std");
const c = @import("scope.zig");

export fn baselineScopeGet(reference: *const c.DirectRef) *u64 {
    return c.get(false, reference);
}
export fn wrapperScopeGet(reference: *const c.Ref) *u64 {
    return c.get(true, reference);
}
export fn baselineScopeGetSlice(reference: *const c.DirectSliceRef, len: *usize) [*]u8 {
    const view = c.getSlice(false, reference);
    len.* = view.len;
    return view.ptr;
}
export fn wrapperScopeGetSlice(reference: *const c.SliceRef, len: *usize) [*]u8 {
    const view = c.getSlice(true, reference);
    len.* = view.len;
    return view.ptr;
}
export fn baselineScopeMake(scope: *const c.DirectScope, pointer: *u64, out: *c.DirectRef) void {
    c.make(false, scope, pointer, out);
}
export fn wrapperScopeMake(scope: *const c.Scope, pointer: *u64, out: *c.Ref) void {
    c.make(true, scope, pointer, out);
}
export fn baselineScopeReborrow(scope: *const c.DirectScope, source: *const c.DirectRef, out: *c.DirectRef) void {
    c.reborrow(false, scope, source, out);
}
export fn wrapperScopeReborrow(scope: *const c.Scope, source: *const c.Ref, out: *c.Ref) void {
    c.reborrow(true, scope, source, out);
}
export fn baselineScopeOpen(table: *c.DirectTable, out: *c.DirectScope) bool {
    return c.open(false, table, out);
}
export fn wrapperScopeOpen(table: *c.Table, out: *c.Scope) bool {
    return c.open(true, table, out);
}
export fn baselineScopeEnd(scope: *const c.DirectScope) void {
    c.end(false, scope);
}
export fn wrapperScopeEnd(scope: *const c.Scope) void {
    c.end(true, scope);
}
export fn baselineScopeCycle(table: *c.DirectTable, pointer: *u64) u64 {
    return c.cycle(false, table, pointer);
}
export fn wrapperScopeCycle(table: *c.Table, pointer: *u64) u64 {
    return c.cycle(true, table, pointer);
}
comptime {
    std.debug.assert(@sizeOf(c.Table) == @sizeOf(c.DirectTable));
    std.debug.assert(@sizeOf(c.Scope) == @sizeOf(c.DirectScope));
    std.debug.assert(@sizeOf(c.Table.Slot) == @sizeOf(c.DirectSlot));
    std.debug.assert(@sizeOf(c.Ref) == @sizeOf(c.DirectRef));
    std.debug.assert(@alignOf(c.Ref) == @alignOf(c.DirectRef));
    std.debug.assert(@sizeOf(c.SliceRef) == @sizeOf(c.DirectSliceRef));
    std.debug.assert(@alignOf(c.Table) == @alignOf(c.DirectTable));
}
