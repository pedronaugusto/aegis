const a = @import("aegis");
const O = a.Order(&.{ .{ .name = "one", .after = &.{1} }, .{ .name = "two", .after = &.{0} } });
export fn bad() usize {
    return @sizeOf(O.Context);
}
