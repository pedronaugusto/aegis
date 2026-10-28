//! A request timeout and an upload limit read from configuration text: durations, sizes and
//! clock readings as types, converted only where it is exact or by a stated rounding.
const std = @import("std");
const aegis = @import("aegis");

const units = aegis.units;
const Timeout = units.Duration(.millisecond, u32);
const Size = units.Bytes(u64);
const Upload = struct {};

pub fn main(init: std.process.Init) !void {
    // One text form, exact both ways.
    const timeout = try Timeout.parse("1m30s");
    const limit = try Size.parse("64MiB");
    aegis.assert.invariant(timeout.eql(.fromRaw(90_000)) and limit.eql(.fromRaw(64 << 20)), "parsed exactly");
    if (Timeout.parse("1.5ms")) |_| unreachable else |err| aegis.assert.invariant(err == error.Inexact, "finer than a millisecond is refused, not rounded");
    if (Size.parse("64mb")) |_| unreachable else |err| aegis.assert.invariant(err == error.Malformed, "a unit is spelled exactly: MiB or MB, never mb");
    var line: [32]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&line);
    try writer.print("{f} {f}", .{ timeout, limit });
    aegis.assert.invariant(std.mem.eql(u8, writer.buffered(), "1m30s 64MiB"), "written as it is read");

    // A conversion that cannot fail carries no error; one that can, keeps its check.
    const wide = timeout.convert(.millisecond, u64, .exact); // no `try`
    const seconds = try timeout.convert(.second, u32, .exact);
    aegis.assert.invariant(wide.eql(.fromRaw(90_000)) and seconds.eql(.fromRaw(90)), "90 s either way");

    // Arithmetic stays in its domain and is checked.
    const uploaded = try units.Count(Upload, u32).fromRaw(3).add(.fromRaw(4));
    aegis.assert.invariant(uploaded.eql(.fromRaw(7)), "counts add to counts");

    // A deadline on the awake clock, from std's own reading, with the span between two readings.
    const Awake = units.Instant(.awake, .nanosecond, i96);
    const start = try Awake.fromIoTimestamp(.now(init.io, .awake), .exact);
    const deadline = try start.add(timeout.convert(.nanosecond, i96, .exact));
    aegis.assert.invariant((try start.durationTo(deadline)).eql(.fromRaw(90 * std.time.ns_per_s)), "the deadline is the timeout away");
}
