const aegis = @import("aegis");
comptime {
    _ = aegis.Secret(struct {
        const Self = @This();
        value: u64,
        pub fn deinit(_: *Self) void {}
    });
}
