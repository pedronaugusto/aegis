//! A routing table many readers consult and one writer replaces: the reader-writer spin lock,
//! with a waiting writer holding off new readers so it is never starved.
const std = @import("std");
const aegis = @import("aegis");

const Routes = struct { version: u32 = 0, targets: [4]u16 = @splat(0) };

fn publish(routes: *aegis.SpinRwGuarded(Routes), versions: u32) void {
    for (1..versions + 1) |version| {
        var held = routes.write();
        defer held.deinit();
        held.value().version = @intCast(version);
        held.value().targets = @splat(@intCast(version));
    }
}

fn consult(routes: *aegis.SpinRwGuarded(Routes), rounds: usize, torn: *std.atomic.Value(usize)) void {
    for (0..rounds) |_| {
        var held = routes.read();
        defer held.deinit();
        const table = held.value(); // shared and read-only
        for (table.targets) |target| {
            if (target != table.version) _ = torn.fetchAdd(1, .monotonic);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var routes = aegis.SpinRwGuarded(Routes).init(.{});
    var torn: std.atomic.Value(usize) = .init(0);
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    try group.concurrent(init.io, publish, .{ &routes, 500 });
    for (0..3) |_| try group.concurrent(init.io, consult, .{ &routes, 2000, &torn });
    try group.await(init.io);
    aegis.assert.invariant(torn.load(.monotonic) == 0, "no reader saw a half-written table");

    // Readers share; a writer waits for them.
    var first = routes.read();
    var second = routes.tryRead() orelse unreachable; // unreachable: readers share the lock
    aegis.assert.invariant(routes.tryWrite() == null, "a writer is refused while readers hold it");
    first.deinit();
    second.deinit();
    aegis.assert.invariant(routes.teardown().version == 500, "the last version stands");
}
