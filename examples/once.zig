//! A resolver table loaded on first use by whichever task gets there first, the others waiting
//! for it: an initializer that may wait or fail, published once.
const std = @import("std");
const aegis = @import("aegis");

const Table = struct { entries: [4]u32 };

const Loader = struct {
    attempts: u32 = 0,

    /// Fails the first time, as a read that was interrupted would; the next caller retries.
    fn load(_: std.Io, loader: *Loader, table: *Table) error{Interrupted}!void {
        loader.attempts += 1;
        if (loader.attempts == 1) return error.Interrupted;
        table.* = .{ .entries = .{ 1, 2, 3, 4 } };
    }
};

fn drop(_: *Table) void {}

pub fn main(init: std.process.Init) !void {
    var table = aegis.Once(Table).init();
    defer table.deinit(drop);
    // Each logical task carries its own context: in Debug it catches an initializer that
    // reaches its own Once again; in release builds it is empty.
    var task: aegis.InitContext = .{};
    var loader: Loader = .{};

    if (table.getOrInit(init.io, &task, &loader, Loader.load)) |_| unreachable else |err| aegis.assert.invariant(err == error.Interrupted, "a failed load leaves it empty");
    aegis.assert.invariant(table.get() == null, "nothing was published");

    const loaded = try table.getOrInit(init.io, &task, &loader, Loader.load);
    aegis.assert.invariant(loaded.entries[3] == 4 and loader.attempts == 2, "the retry loaded it");
    aegis.assert.invariant(try table.getOrInit(init.io, &task, &loader, Loader.load) == loaded and loader.attempts == 2, "later callers get the same table, never a second load");
}
