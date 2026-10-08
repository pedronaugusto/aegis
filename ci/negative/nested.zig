const aegis = @import("aegis");
comptime {
    _ = aegis.Secret([2]struct { value: ?[]const u8 });
}
