const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
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
    const tests = b.addTest(.{ .root_module = m, .filters = filters, .use_llvm = true });
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
        .programs = &.{ .{ .name = "owners", .source = "bench/owners.zig" }, .{ .name = "numeric", .source = "bench/numeric.zig" }, .{ .name = "choices", .source = "bench/choices.zig" }, .{ .name = "bytes", .source = "bench/bytes.zig" } },
        .imports = benchImports,
        .target = target,
        .optimize = optimize,
    } });
    // preflight's benchmark API does not expose backend selection. Pin both
    // benchmark executables and their CI object projections to audited LLVM.
    var llvm_steps: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    for (b.top_level_steps.values()) |step| choiceBenchmarkLlvm(b, &step.step, &llvm_steps);
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
    const choices_codegen = b.addExecutable(.{ .name = "aegis-choices-codegen", .root_module = b.createModule(.{
        .root_source_file = b.path("ci/choice_codegen.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "aegis", .module = b.modules.get("aegis").? }},
    }) });
    const run_choices_codegen = b.addRunArtifact(choices_codegen);
    run_choices_codegen.addArg(b.graph.zig_exe);
    run_choices_codegen.setCwd(b.path("."));
    run_choices_codegen.addPassthruArgs();
    b.step("check-choices", "Audit A5 enclosing caller instructions and secret control/address regressions").dependOn(&run_choices_codegen.step);
    const choices_negative = b.addExecutable(.{ .name = "aegis-choices-negative", .root_module = b.createModule(.{ .root_source_file = b.path("ci/choice_negative.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_choices_negative = b.addRunArtifact(choices_negative);
    run_choices_negative.addArg(b.graph.zig_exe);
    run_choices_negative.setCwd(b.path("."));
    b.step("check-choices-negative", "Reject unsupported A5 types, profiles and disclosure/format uses").dependOn(&run_choices_negative.step);
    const bytes_contracts = b.addExecutable(.{ .name = "aegis-bytes-contracts", .root_module = b.createModule(.{
        .root_source_file = b.path("ci/bytes_check.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_bytes_contracts = b.addRunArtifact(bytes_contracts);
    run_bytes_contracts.addArg(b.graph.zig_exe);
    run_bytes_contracts.setCwd(b.path("."));
    b.step("check-secret-bytes", "Require all-mode move rejection and portable byte owner compilation").dependOn(&run_bytes_contracts.step);
    const focus = b.step("test-handles-input", "Run selected A8/A9 cases without unrelated tooling");
    const focused = b.addTest(.{ .root_module = m, .filters = filters, .use_llvm = true });
    focus.dependOn(&b.addRunArtifact(focused).step);
    const bytes_tests = b.step("test-secret-bytes", "Run A4 ownership contracts in both release modes");
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
        const bytes_release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{"A4"} });
        bytes_tests.dependOn(&b.addRunArtifact(bytes_release_tests).step);
    }
}

fn benchImports(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) []const std.Build.Module.Import {
    const material = b.createModule(.{ .root_source_file = b.path("src/testing/Material.zig"), .target = target, .optimize = optimize });
    const aegis = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const cases = b.createModule(.{ .root_source_file = b.path("ci/cases.zig"), .target = target, .optimize = optimize, .imports = &.{ .{ .name = "aegis", .module = aegis }, .{ .name = "material", .module = material } } });
    const numeric = b.createModule(.{ .root_source_file = b.path("ci/numeric.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const choices = b.createModule(.{ .root_source_file = b.path("ci/choice_callers.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const shake = b.dependencyLazy("shakedown", .{ .target = target, .optimize = optimize }) catch @panic("shakedown unavailable for A5 benchmark");
    const bytes = b.createModule(.{ .root_source_file = b.path("ci/bytes.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    return b.allocator.dupe(std.Build.Module.Import, &.{ .{ .name = "cases", .module = cases }, .{ .name = "numeric", .module = numeric }, .{ .name = "choices", .module = choices }, .{ .name = "shakedown", .module = shake.module("shakedown") }, .{ .name = "bytes", .module = bytes }, .{ .name = "material", .module = material } }) catch @panic("out of memory configuring benchmarks");
}

fn choiceBenchmarkLlvm(b: *std.Build, step: *std.Build.Step, seen: *std.AutoHashMapUnmanaged(*std.Build.Step, void)) void {
    const entry = seen.getOrPut(b.allocator, step) catch @panic("OOM");
    if (entry.found_existing) return;
    if (step.cast(std.Build.Step.Compile)) |compile| {
        if (std.mem.eql(u8, compile.name, "choices")) compile.use_llvm = true;
    }
    for (step.dependencies.items) |dependency| choiceBenchmarkLlvm(b, dependency, seen);
}
