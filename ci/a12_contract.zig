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
    var other_slots: [1]a.scope.Table(Connection).Slot = undefined;
    var other = a.scope.Table(Connection).init(&other_slots);
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
        const copy = request;
        request.end();
        copy.end();
    } else if (std.mem.eql(u8, name, "ref-after-end")) {
        const request = try table.open();
        request.end();
        std.mem.doNotOptimizeAway(request.ref(&storage));
    } else if (std.mem.eql(u8, name, "reborrow-expired")) {
        const request = try table.open();
        const connection = try other.open();
        const view = request.ref(&storage);
        request.end();
        std.mem.doNotOptimizeAway(connection.reborrow(view));
    } else if (std.mem.eql(u8, name, "table-open")) {
        const request = try table.open();
        std.mem.doNotOptimizeAway(request);
        table.deinit();
    } else return error.UnknownCase;
}
