const std = @import("std");
const preflight = @import("preflight");
pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Floor: no implementation yet");
    _ = b.step("check", "Floor: no implementation yet");
    preflight.addCi(b, .{ .tests = test_step });
    const tools = b.dependencyLazy("preflight", .{}) catch return;
    const host = b.graph.host;
    const gantry = tools.builder.dependencyLazy("gantry", .{ .target = host, .optimize = .safe }) catch return;
    const tool = b.addExecutable(.{ .name = "aegis-plan", .root_module = b.createModule(.{
        .root_source_file = tools.path("src/main.zig"),
        .target = host,
        .optimize = .safe,
        .imports = &.{.{ .name = "gantry", .module = gantry.module("gantry") }},
    }) });
    const run = b.addRunArtifact(tool);
    run.addArg("plan");
    run.setCwd(b.path("."));
    run.addPassthruArgs();
    b.step("plan", "Generate hosted matrices from repository facts").dependOn(&run.step);
}
