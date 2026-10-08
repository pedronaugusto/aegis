const aegis = @import("aegis");
comptime {
    _ = aegis.Secret(struct { bytes: [32]u8, pointer: *const u8 });
}
