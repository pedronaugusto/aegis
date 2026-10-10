//! Portable scope profile for 32-bit, wasm and freestanding targets.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");
const Request = struct {};
const Slots = a.scope.Table(Request);
comptime {
    if (builtin.optimize == .fast or builtin.optimize == .small) {
        std.debug.assert(@sizeOf(a.scope.Ref(Request, *u32)) == @sizeOf(*u32));
        std.debug.assert(@sizeOf(a.scope.Ref(Request, []u8)) == @sizeOf([]u8));
        std.debug.assert(@sizeOf(Slots) == 0 and @sizeOf(Slots.Slot) == 0 and @sizeOf(Slots.Scope) == 0);
    }
}
export fn pure(seed: u32) u32 {
    var slots: [2]Slots.Slot = undefined;
    var table = Slots.init(&slots);
    var value = seed;
    const request = table.open() catch return 0;
    const view = request.ref(&value);
    view.get().* +%= 1;
    const result = view.get().*;
    request.end();
    table.deinit();
    return result;
}
