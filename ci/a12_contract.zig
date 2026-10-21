//! Deliberate scope violations in isolated child processes, never live station turns.
const std = @import("std");
const a = @import("aegis");
const Request = struct {};
const Connection = struct {};
var storage: u64 = 0xfeed;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const name = args[1];
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    var other_slots: [1]a.scope.Table(Connection).Slot = undefined;
    var other = a.scope.Table(Connection).init(&other_slots);
    defer other.deinit();
    if (std.mem.eql(u8, name, "ref-expired")) {
        const request = try table.open();
        const view = request.ref(&storage);
        request.end();
        std.mem.doNotOptimizeAway(view.get().*);
    } else if (std.mem.eql(u8, name, "ref-after-reuse")) {
        const first = try table.open();
        const stale = first.ref(&storage);
        first.end();
        const second = try table.open();
        defer second.end();
        std.mem.doNotOptimizeAway(stale.get().*);
    } else if (std.mem.eql(u8, name, "end-twice")) {
        const request = try table.open();
        request.end();
        // glint-ignore: A003 -- design: the deliberate second end the checked builds stop on; an isolated child process runs it
        request.end();
    } else if (std.mem.eql(u8, name, "ref-after-end")) {
        const request = try table.open();
        request.end();
        // glint-ignore: A003 -- design: the deliberate use of an ended scope the checked builds stop on; an isolated child process runs it
        std.mem.doNotOptimizeAway(request.ref(&storage));
    } else if (std.mem.eql(u8, name, "reborrow-expired")) {
        const request = try table.open();
        // glint-ignore: A003 -- design: left open, as the checked builds stop at the stale reborrow before its end; an isolated child process runs it
        const connection = other.open() catch unreachable; // unreachable: a table of one slot opens its first scope
        const view = request.ref(&storage);
        request.end();
        std.mem.doNotOptimizeAway(connection.reborrow(view));
    } else if (std.mem.eql(u8, name, "table-open")) {
        var open_slots: [1]a.scope.Table(Request).Slot = undefined;
        var open = a.scope.Table(Request).init(&open_slots);
        errdefer open.deinit();
        // The scope stays open: the teardown below is the violation.
        _ = try open.open();
        open.deinit();
    } else return error.UnknownCase;
}
