const aegis = @import("aegis");

pub fn main() void {
    // --- README:usage ---
    var key = aegis.Secret([32]u8).init(@splat(7));
    defer key.deinit();
    const bytes = key.expose(); // borrow ends at cleanup/transfer
    var counts = aegis.Guarded(usize).init(0);
    var held = counts.acquire();
    defer held.deinit();
    held.value().* += bytes[0];
    // --- README:usage ---
}
