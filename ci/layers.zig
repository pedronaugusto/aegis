const gantry = @import("gantry");
const family = @import("preflight_rules");
pub const layers: []const gantry.rules.Layer = &.{
    .{ .name = "base", .patterns = &.{ "src/scalar.zig", "src/int.zig", "src/id.zig", "src/units.zig", "src/assert.zig" } },
    .{ .name = "secret", .patterns = &.{ "src/secret.zig", "src/secret/**" } },
    .{ .name = "sync", .patterns = &.{ "src/Guarded.zig", "src/sync.zig" } },
    .{ .name = "handles", .patterns = &.{ "src/handle.zig", "src/handle/**" } },
    .{ .name = "boundary", .patterns = &.{ "src/input.zig", "src/err.zig" } },
    .{ .name = "public", .patterns = &.{"src/root.zig"} },
};
pub const required = [_][]const u8{ "src/root.zig", "src/secret.zig", "src/secret/inline.zig", "src/secret/bytes.zig", "src/Guarded.zig", "src/secret/value.zig", "src/scalar.zig", "src/int.zig", "src/id.zig", "src/assert.zig", "src/tests.zig" };
pub const entries: []const []const u8 = &.{"src/root.zig"};
pub const modules: []const gantry.NamedModule = &.{ .{ .name = "scalar", .path = "src/scalar.zig" }, .{ .name = "int", .path = "src/int.zig" }, .{ .name = "id", .path = "src/id.zig" }, .{ .name = "units", .path = "src/units.zig" }, .{ .name = "assert", .path = "src/assert.zig" }, .{ .name = "secret", .path = "src/secret.zig" }, .{ .name = "sync", .path = "src/sync.zig" }, .{ .name = "handle", .path = "src/handle.zig" }, .{ .name = "input", .path = "src/input.zig" }, .{ .name = "err", .path = "src/err.zig" }, .{ .name = "shakedown", .path = "" }, .{ .name = "material", .path = "" } };
const leaf = [_]gantry.rules.ReferenceRule{.{ .name = "std-only leaf", .unresolved_only = true, .except_targets = &.{ "std", "builtin", "shakedown", "material" } }};
pub const references: []const gantry.rules.ReferenceRule = &(leaf ++ family.shakedown);
pub const owned: []const gantry.rules.TokenRule = &(family.durability ++ family.no_async);
