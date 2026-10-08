const gantry = @import("gantry");
const family = @import("preflight_rules");
pub const layers: []const gantry.rules.Layer = &.{
    .{ .name = "primitives", .patterns = &.{ "src/Secret.zig", "src/SecretBytes.zig", "src/Guarded.zig", "src/scalar.zig", "src/int.zig", "src/id.zig", "src/assert.zig", "src/bounded.zig", "src/own.zig", "src/BlockingGuarded.zig", "src/RwGuarded.zig", "src/Condition.zig", "src/Confined.zig" } },
    .{ .name = "units and publication", .patterns = &.{ "src/units.zig", "src/Once.zig", "src/Order.zig" } },
    .{ .name = "public", .patterns = &.{"src/root.zig"} },
};
pub const required = [_][]const u8{ "src/root.zig", "src/Secret.zig", "src/SecretBytes.zig", "src/Guarded.zig", "src/scalar.zig", "src/int.zig", "src/id.zig", "src/assert.zig", "src/tests.zig" };
pub const entries: []const []const u8 = &.{"src/root.zig"};
pub const modules: []const gantry.NamedModule = &.{ .{ .name = "shakedown", .path = "" }, .{ .name = "material", .path = "" } };
const leaf = [_]gantry.rules.ReferenceRule{.{ .name = "std-only leaf", .unresolved_only = true, .except_targets = &.{ "std", "builtin", "shakedown", "material" } }};
pub const references: []const gantry.rules.ReferenceRule = &(leaf ++ family.shakedown);
pub const owned: []const gantry.rules.TokenRule = &(family.durability ++ family.no_async);
