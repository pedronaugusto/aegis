const gantry = @import("gantry");
const family = @import("preflight_rules");
pub const layers: []const gantry.rules.Layer = &.{
    .{ .name = "primitives", .patterns = &.{ "src/Secret.zig", "src/Guarded.zig" } },
    .{ .name = "public", .patterns = &.{"src/root.zig"} },
};
pub const required = [_][]const u8{ "src/root.zig", "src/Secret.zig", "src/Guarded.zig", "src/tests.zig" };
pub const entries: []const []const u8 = &.{"src/root.zig"};
pub const modules: []const gantry.NamedModule = &.{ .{ .name = "shakedown", .path = "" }, .{ .name = "material", .path = "" } };
const leaf = [_]gantry.rules.ReferenceRule{.{ .name = "std-only leaf", .unresolved_only = true, .except_targets = &.{ "std", "shakedown", "material" } }};
pub const references: []const gantry.rules.ReferenceRule = &(leaf ++ family.shakedown);
pub const owned: []const gantry.rules.TokenRule = &(family.durability ++ family.no_async);
