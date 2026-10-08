const a = @import("aegis");
export fn bad() void {
    _ = a.int.Checked(u7).init(1).toBytes(.big);
}
