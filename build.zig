const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tsan = b.option(bool, "thread-sanitizer", "Instrument native thread contention on Linux") orelse false;
    const filters = b.option([]const []const u8, "test-filter", "Run tests containing this name") orelse &.{};
    _ = b.addModule("aegis", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    if (b.dep_prefix.len != 0) return;
    const preflight = b.lazyImport(@This(), "preflight") orelse return;
    const test_step = b.step("test", "Run focused ownership and synchronization tests");
    const check = b.step("check", "Compile all tests without execution");
    const shake = b.dependencyLazy("shakedown", .{ .target = target, .optimize = optimize }) catch return;
    const m = b.createModule(.{ .root_source_file = b.path("src/tests.zig"), .target = target, .optimize = optimize, .imports = &.{ .{ .name = "shakedown", .module = shake.module("shakedown") }, .{ .name = "material", .module = b.createModule(.{ .root_source_file = b.path("src/testing/Material.zig"), .target = target, .optimize = optimize }) } } });
    m.sanitize_thread = tsan;
    if (tsan) m.link_libc = true;
    const tests = b.addTest(.{ .root_module = m, .filters = filters });
    test_step.dependOn(&b.addRunArtifact(tests).step);
    check.dependOn(&tests.step);
    const example = b.addExecutable(.{ .name = "aegis-example", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/usage.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "aegis", .module = b.modules.get("aegis").? }},
    }) });
    test_step.dependOn(&b.addRunArtifact(example).step);
    preflight.addCi(b, .{ .tests = test_step, .portable_tests = true, .bench = .{
        .programs = &.{ .{ .name = "owners", .source = "bench/owners.zig" }, .{ .name = "numeric", .source = "bench/numeric.zig" } },
        .imports = benchImports,
        .target = target,
        .optimize = optimize,
    } });
    preflight.addConsumerCheck(b, .{ .package = "aegis", .program = b.path("ci/consumer.zig") });
    const negative = b.addExecutable(.{ .name = "aegis-negative", .root_module = b.createModule(.{
        .root_source_file = b.path("ci/negative.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_negative = b.addRunArtifact(negative);
    run_negative.addArg(b.graph.zig_exe);
    run_negative.setCwd(b.path("."));
    b.step("check-negative", "Reject pointer-bearing secret shapes at compile time").dependOn(&run_negative.step);
    const codegen = b.addExecutable(.{ .name = "aegis-codegen", .root_module = b.createModule(.{
        .root_source_file = b.path("ci/codegen.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_codegen = b.addRunArtifact(codegen);
    run_codegen.addArg(b.graph.zig_exe);
    run_codegen.setCwd(b.path("."));
    run_codegen.addPassthruArgs();
    b.step("check-parity", "Require paired layout/IR/erasure parity for both release modes and CPUs").dependOn(&run_codegen.step);
    const contracts = b.addExecutable(.{ .name = "aegis-contracts", .root_module = b.createModule(.{
        .root_source_file = b.path("ci/contracts.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_contracts = b.addRunArtifact(contracts);
    run_contracts.addArg(b.graph.zig_exe);
    run_contracts.setCwd(b.path("."));
    b.step("check-contracts", "Require release fail-stop and portable scalar profiles").dependOn(&run_contracts.step);
    const scalar_tests = b.step("test-scalars", "Run A3 contracts in both release modes");
    for ([_]std.lang.Optimize{ .safe, .fast }) |mode| {
        const scalar_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = b.graph.host,
            .optimize = mode,
            .imports = &.{ .{ .name = "shakedown", .module = shake.module("shakedown") }, .{ .name = "material", .module = b.createModule(.{ .root_source_file = b.path("src/testing/Material.zig"), .target = b.graph.host, .optimize = mode }) } },
        });
        const release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{"A3"} });
        scalar_tests.dependOn(&b.addRunArtifact(release_tests).step);
    }
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

fn benchImports(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) []const std.Build.Module.Import {
    const material = b.createModule(.{ .root_source_file = b.path("src/testing/Material.zig"), .target = target, .optimize = optimize });
    const aegis = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const cases = b.createModule(.{ .root_source_file = b.path("ci/cases.zig"), .target = target, .optimize = optimize, .imports = &.{ .{ .name = "aegis", .module = aegis }, .{ .name = "material", .module = material } } });
    const numeric = b.createModule(.{ .root_source_file = b.path("ci/numeric.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    return b.allocator.dupe(std.Build.Module.Import, &.{ .{ .name = "cases", .module = cases }, .{ .name = "numeric", .module = numeric } }) catch @panic("out of memory configuring benchmarks");
}
