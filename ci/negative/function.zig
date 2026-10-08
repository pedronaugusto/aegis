const aegis = @import("aegis");
comptime {
    _ = aegis.Secret(*const fn () void);
}
