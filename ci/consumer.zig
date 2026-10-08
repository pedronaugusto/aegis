const aegis = @import("aegis");
pub fn main() void {
    var secret = aegis.Secret([32]u8).init(@splat(0));
    defer secret.deinit();
    var shared = aegis.Guarded(u64).init(0);
    var held = shared.acquire();
    defer held.deinit();
    held.value().* += secret.expose()[0];
}
