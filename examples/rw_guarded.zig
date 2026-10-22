//! A configuration many tasks read and one reloads, behind `std.Io.RwLock`, with a finite
//! admission so the lock's packed counters can never overflow.
const std = @import("std");
const aegis = @import("aegis");

const Config = struct { timeout_ms: u32, retries: u8 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // At most two holders at once; the third is refused, not queued past the counters.
    var config = try aegis.RwGuarded(Config).initLimit(.{ .timeout_ms = 250, .retries = 3 }, 2);

    {
        var reader = try config.read(io);
        defer reader.deinit(io);
        var other = try config.read(io);
        defer other.deinit(io);
        aegis.assert.post(reader.value().timeout_ms == other.value().timeout_ms, "readers share one view");
        if (config.tryRead(io)) |_| unreachable else |err| aegis.assert.invariant(err == error.AdmissionLimit, "a third holder is past the limit");
    }

    {
        var writer = try config.write(io);
        defer writer.deinit(io);
        writer.value().* = .{ .timeout_ms = 500, .retries = 5 };
    }

    var reader = try config.readUncancelable(io);
    defer reader.deinit(io);
    aegis.assert.post(reader.value().retries == 5, "readers see the reload");
}
