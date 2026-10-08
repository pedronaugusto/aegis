const aegis = @import("aegis");
comptime {
    _ = aegis.Secret([]u8);
}
