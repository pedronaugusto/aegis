//! A count of open connections shared without a lock: one cell holding a typed count, its
//! arithmetic checked, so it reports overflow instead of wrapping.
const std = @import("std");
const aegis = @import("aegis");

const Connection = struct {};
const Open = aegis.units.Count(Connection, u16);

fn churn(open: *aegis.Atomic(Open), rounds: usize) void {
    for (0..rounds) |_| {
        _ = open.fetchAdd(.fromRaw(1), .monotonic) catch return;
        _ = open.fetchSub(.fromRaw(1), .monotonic) catch return;
    }
}

pub fn main(init: std.process.Init) !void {
    var open = aegis.Atomic(Open).init(.fromRaw(0));
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    for (0..4) |_| try group.concurrent(init.io, churn, .{ &open, 1000 });
    try group.await(init.io);
    aegis.assert.invariant(open.load(.acquire).eql(.fromRaw(0)), "every open was closed");

    // At the top of the range the add is refused and the cell keeps its value.
    open.store(.fromRaw(std.math.maxInt(u16)), .monotonic);
    if (open.fetchAdd(.fromRaw(1), .monotonic)) |_| unreachable else |err| aegis.assert.invariant(err == error.Overflow, "a count never wraps");
    aegis.assert.invariant(open.load(.monotonic).eql(.fromRaw(std.math.maxInt(u16))), "the refused add changed nothing");

    // A counter whose width cannot be reached takes the hardware add by name.
    const events = aegis.Atomic(aegis.units.Count(Connection, u64));
    var seen = events.init(.fromRaw(0));
    _ = seen.fetchAddWrapping(.fromRaw(1), .monotonic);
    aegis.assert.invariant(seen.load(.monotonic).eql(.fromRaw(1)), "the wrapping form is the plain add");
}
