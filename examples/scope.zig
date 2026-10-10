const aegis = @import("aegis");

// --- README:scope ---
const std = @import("std");

/// The brand: a reference made in a request scope is a different type from one made in any other kind.
const Request = struct {};
const Requests = aegis.scope.Table(Request);

pub fn main() !void {
    // The connection keeps the table. One slot per request that can be open and checked at once.
    var slots: [4]Requests.Slot = undefined;
    var requests = Requests.init(&slots);
    defer requests.deinit();

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const request = try requests.open();
    const body = try arena.allocator().dupe(u8, "GET /index");
    const view = request.ref(body); // good while `request` is open
    aegis.assert.post(view.get().len == 10, "the body is readable while its request is open");

    request.end();
    _ = arena.reset(.free_all);
    // `view.get()` from here on stops the program in Debug and ReleaseSafe: its scope ended.
    // In ReleaseFast and ReleaseSmall nothing is checked and `view` is just the slice.
}
// --- README:scope ---
