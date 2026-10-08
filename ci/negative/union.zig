const aegis = @import("aegis");
comptime {
    _ = aegis.Secret(union(enum) { bytes: [32]u8, pointer: *u8 });
}
