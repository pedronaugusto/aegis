//! Two locks always taken in one order, accounts before the ledger: ranks declared once and
//! checked at every acquire in Debug, so an inversion is caught before it can deadlock.
const std = @import("std");
const aegis = @import("aegis");

const accounts = 0;
const ledger = 1;
const Ranks = aegis.Order(&.{
    .{ .name = "accounts" },
    .{ .name = "ledger", .after = &.{accounts} },
});

const Accounts = Ranks.Ordered(aegis.BlockingGuarded([2]i64), accounts);
const Ledger = Ranks.Ordered(aegis.BlockingGuarded(u32), ledger);

fn transfer(io: std.Io, context: *Ranks.Context, books: *Accounts, log: *Ledger, amount: i64) !void {
    var balances = try books.acquireOrdered(io, context);
    defer balances.deinit(io);
    var entries = try log.acquireOrdered(io, context); // ledger after accounts: in order
    defer entries.deinit(io);
    balances.value()[0] -= amount;
    balances.value()[1] += amount;
    entries.value().* += 1;
}

pub fn main(init: std.process.Init) !void {
    var books = Accounts.init(.init(.{ 100, 0 }));
    var log = Ledger.init(.init(0));
    // One context per logical task; it holds the ranks held, in Debug only.
    var context: Ranks.Context = .{};
    try transfer(init.io, &context, &books, &log, 30);
    try transfer(init.io, &context, &books, &log, 20);
    // Taking the ledger and then the accounts would stop a Debug build at the second acquire.
    aegis.assert.invariant(books.teardown()[1] == 50 and log.teardown().* == 2, "both transfers landed");
}
