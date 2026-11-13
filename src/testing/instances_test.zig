//! Every generic type aegis declares, made at a representative parameter, with each of its
//! declarations referenced: a method nothing inside aegis calls compiles here, so one left
//! broken (a field renamed and a read of it missed, 688eb2b's aegis_ rename) fails aegis's own
//! tests, not a caller's build. `refAllDecls` reaches neither an inline method nor one a lock
//! type answers by its shape (Order's acquisitions over each lock): those are named.
const std = @import("std");
const r = std.testing.refAllDecls;
const Tag = struct {};
fn noop(_: *u32) void {}
fn noopIo(_: *u32, _: std.Io) void {}
test "every public type function, made at a representative parameter, compiles every method it declares" {
    const b = @import("../bounded.zig");
    r(b.Array(u8, 4));
    r(b.Ring(u8, 4));
    r(b.Buffer(u8));
    r(b.RingBuffer(u8));
    r(b.Limit(u32));
    r(b.Budget(u32));
    const Dense = @import("../handle/dense.zig").DenseSlotMap(u32, Tag);
    r(Dense);
    const Pool = @import("../handle/slot_pool.zig").SlotPool(u32, Tag, .{});
    r(Pool);
    r(@import("../handle/slot_pool.zig").SlotPool(u32, Tag, .{ .generation = u32 }));
    r(@import("../handle/run_pool.zig").RunPool(u32, Tag));
    r(@import("../handle/secondary.zig").SecondaryMap(Dense, u32));
    const own = @import("../own.zig");
    r(own.Owned(u32, noop));
    r(own.OwnedIo(u32, noopIo));
    r(own.MustUse(u32, "x"));
    r(@import("../scope/table.zig").Table(Tag));
    const O = @import("../Order.zig").Order(&.{ .{ .name = "a" }, .{ .name = "b", .after = &.{0} } });
    r(O);
    const Rw = O.Ordered(@import("../RwGuarded.zig").RwGuarded(u32), 0);
    const Bl = O.Ordered(@import("../BlockingGuarded.zig").BlockingGuarded(u32), 1);
    inline for (.{ "init", "readOrdered", "writeOrdered", "readOrderedUncancelable", "writeOrderedUncancelable" }) |m| _ = &@field(Rw, m);
    inline for (.{ "init", "acquireOrdered", "acquireOrderedUncancelable" }) |m| _ = &@field(Bl, m);
    const Cap = @typeInfo(@typeInfo(@TypeOf(Bl.acquireOrdered)).@"fn".return_type.?).error_union.payload;
    r(Cap);
    const RCap = @typeInfo(@typeInfo(@TypeOf(Rw.readOrdered)).@"fn".return_type.?).error_union.payload;
    inline for (.{ "value", "deinit" }) |m| _ = &@field(RCap, m);
    r(@import("../Guarded.zig").Guarded(u32).Handoff);
    r(@import("../BlockingGuarded.zig").BlockingGuarded(u32));
    r(@import("../Confined.zig").Confined(u32));
    r(@import("../Guarded.zig").Guarded(u32));
    r(@import("../Lazy.zig").Lazy(u32));
    r(@import("../Once.zig").Once(u32));
    r(@import("../RwGuarded.zig").RwGuarded(u32));
    r(@import("../Signal.zig").Signal(u32));
    r(@import("../SpinRwGuarded.zig").SpinRwGuarded(u32));
    r(@import("../Region.zig").Tail(u32));
    r(@import("../Shared.zig").Shared(u32, noop));
    r(@import("../input.zig").Untrusted(u32));
    r(@import("../secret/inline.zig").Secret(u32));
    r(own.Unowned(std.Io.File));
    r(@import("../Pulse.zig").Pulse);
}
