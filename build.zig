const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});
    const tsan = b.option(bool, "thread-sanitizer", "Instrument native thread contention on Linux") orelse false;
    const filters = b.option([]const []const u8, "test-filter", "Run tests containing this name") orelse &.{};
    const aegis = b.addModule("aegis", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    if (b.dep_prefix.len != 0) return;
    const preflight = b.lazyImport(@This(), "preflight") orelse return;
    const test_step = b.step("test", "Run focused ownership and synchronization tests");
    const check = b.step("check", "Compile all tests without execution");
    const shake = b.dependencyLazy("shakedown", .{ .target = target, .optimize = optimize }) catch return;
    const material = b.createModule(.{ .root_source_file = b.path("src/testing/Material.zig"), .target = target, .optimize = optimize });
    const m = testModule(b, shake.module("shakedown"), material, target, optimize);
    if (tsan) aegis.sanitize_thread = true;
    m.sanitize_thread = tsan;
    if (tsan) m.link_libc = true;
    const tests = b.addTest(.{ .root_module = m, .filters = filters, .use_llvm = true });
    test_step.dependOn(&b.addRunArtifact(tests).step);
    check.dependOn(&tests.step);
    const example = b.addExecutable(.{ .name = "aegis-example", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/usage.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "aegis", .module = aegis }},
    }) });
    test_step.dependOn(&b.addRunArtifact(example).step);
    for ([_][]const u8{ "state", "scope" }) |name| {
        const worked = b.addExecutable(.{ .name = b.fmt("aegis-example-{s}", .{name}), .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "aegis", .module = aegis }},
        }) });
        test_step.dependOn(&b.addRunArtifact(worked).step);
    }
    preflight.addCi(b, .{ .tests = test_step, .portable_tests = true, .bench = .{
        .programs = &.{ .{ .name = "owners", .source = "bench/owners.zig" }, .{ .name = "numeric", .source = "bench/numeric.zig" }, .{ .name = "choices", .source = "bench/choices.zig" }, .{ .name = "bytes", .source = "bench/bytes.zig" }, .{ .name = "guarded-bounded", .source = "bench/a67.zig" }, .{ .name = "handles-input", .source = "bench/handles_input.zig" }, .{ .name = "gaps", .source = "bench/gaps.zig" }, .{ .name = "state", .source = "bench/state.zig" }, .{ .name = "scope", .source = "bench/scope.zig" } },
        .imports = benchImports,
        .target = target,
        .optimize = optimize,
    } });
    // preflight's benchmark API does not expose backend selection. Pin both
    // benchmark executables and their CI object projections to audited LLVM.
    var llvm_steps: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    for (b.top_level_steps.values()) |step| choiceBenchmarkLlvm(b, &step.step, &llvm_steps);
    preflight.addConsumerCheck(b, .{ .package = "aegis", .program = b.path("ci/consumer.zig"), .modules = &.{"aegis"} });

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
        .imports = &.{.{ .name = "aegis", .module = aegis }},
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
    const safety_check = b.step("check-handles-input", "Require A8/A9 portable layout/instruction and negative contracts");
    for ([_][]const u8{ "safety_codegen", "safety_negative" }) |source| {
        const program = b.addExecutable(.{ .name = source, .root_module = b.createModule(.{ .root_source_file = b.path(b.fmt("ci/{s}.zig", .{source})), .target = b.graph.host, .optimize = .safe }) });
        const run = b.addRunArtifact(program);
        run.addArg(b.graph.zig_exe);
        run.setCwd(b.path("."));
        safety_check.dependOn(&run.step);
    }
    const modes = b.step("test-handles-input-modes", "Run A8/A9 semantic contracts in all release modes");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const mode_module = testModule(b, shake.module("shakedown"), material, b.graph.host, mode);
        const mode_tests = b.addTest(.{ .root_module = mode_module, .filters = &.{ "A8", "A9" }, .use_llvm = true });
        modes.dependOn(&b.addRunArtifact(mode_tests).step);
    }
    const a67 = b.addExecutable(.{ .name = "aegis-a67-contracts", .root_module = b.createModule(.{ .root_source_file = b.path("ci/a67_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a67 = b.addRunArtifact(a67);
    run_a67.addArg(b.graph.zig_exe);
    run_a67.setCwd(b.path("."));
    b.step("check-a67", "Require mode-matrix safety/diagnostics and portable value layouts").dependOn(&run_a67.step);
    const a67_tests = b.step("test-a67", "Run A6/A7 synchronization, ownership and bounds in both release modes");
    const bytes_tests = b.step("test-secret-bytes", "Run A4 ownership contracts in both release modes");
    const scalar_tests = b.step("test-scalars", "Run A3 contracts in both release modes");
    for ([_]std.lang.Optimize{ .safe, .fast }) |mode| {
        const scalar_module = testModule(b, shake.module("shakedown"), material, b.graph.host, mode);
        const release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{"A3"} });
        scalar_tests.dependOn(&b.addRunArtifact(release_tests).step);
        const a67_release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{ "A6", "A7" } });
        a67_tests.dependOn(&b.addRunArtifact(a67_release_tests).step);
        const bytes_release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{"A4"} });
        bytes_tests.dependOn(&b.addRunArtifact(bytes_release_tests).step);
    }
    const a10 = b.addExecutable(.{ .name = "aegis-a10-contracts", .root_module = b.createModule(.{ .root_source_file = b.path("ci/a10_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a10 = b.addRunArtifact(a10);
    run_a10.addArg(b.graph.zig_exe);
    run_a10.setCwd(b.path("."));
    b.step("check-a10", "Require typestate mode-matrix contracts, intended-reason rejections and portable profiles").dependOn(&run_a10.step);
    const a10_tests = b.step("test-a10", "Run A10 typestate semantics in the three release modes");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const release_module = testModule(b, shake.module("shakedown"), material, b.graph.host, mode);
        const release_tests = b.addTest(.{ .root_module = release_module, .filters = &.{"A10"}, .use_llvm = true });
        a10_tests.dependOn(&b.addRunArtifact(release_tests).step);
    }
    const a12 = b.addExecutable(.{ .name = "aegis-a12-contracts", .root_module = b.createModule(.{ .root_source_file = b.path("ci/a12_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a12 = b.addRunArtifact(a12);
    run_a12.addArg(b.graph.zig_exe);
    run_a12.setCwd(b.path("."));
    b.step("check-a12", "Require scope mode-matrix contracts, intended-reason rejections and portable profiles").dependOn(&run_a12.step);
    const a12_tests = b.step("test-a12", "Run A12 scope semantics in the three release modes");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const release_module = testModule(b, shake.module("shakedown"), material, b.graph.host, mode);
        const release_tests = b.addTest(.{ .root_module = release_module, .filters = &.{"A12"}, .use_llvm = true });
        a12_tests.dependOn(&b.addRunArtifact(release_tests).step);
    }
    contractGroups(b);
}

// The contract gates split into groups of near-equal hosted cost. Each group is
// one hosted job, and `contracts` runs them all.
fn contractGroups(b: *std.Build) void {
    const groups = [_]struct { name: []const u8, description: []const u8, steps: []const []const u8 }{
        .{ .name = "contracts-values", .description = "Run the A3 to A5 value and owner contracts", .steps = &.{ "check-negative", "check-parity", "check-contracts", "test-scalars", "check-secret-bytes", "test-secret-bytes" } },
        .{ .name = "contracts-choices", .description = "Run the A5 choice contracts", .steps = &.{ "check-choices", "check-choices-negative" } },
        .{ .name = "contracts-published", .description = "Run the A6 to A12 contracts and the published-module gates", .steps = &.{ "check-a67", "test-a67", "check-handles-input", "test-handles-input-modes", "check-a10", "test-a10", "check-a12", "test-a12", "check-consumer" } },
    };
    const all = b.step("contracts", "Run every contract group");
    for (groups) |group| {
        const step = b.step(group.name, group.description);
        for (group.steps) |name| step.dependOn(&b.top_level_steps.get(name).?.step);
        all.dependOn(step);
    }
}

fn benchImports(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) []const std.Build.Module.Import {
    const material = b.createModule(.{ .root_source_file = b.path("src/testing/Material.zig"), .target = target, .optimize = optimize });
    const aegis = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const cases = b.createModule(.{ .root_source_file = b.path("ci/cases.zig"), .target = target, .optimize = optimize, .imports = &.{ .{ .name = "aegis", .module = aegis }, .{ .name = "material", .module = material } } });
    const numeric = b.createModule(.{ .root_source_file = b.path("ci/numeric.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const choices = b.createModule(.{ .root_source_file = b.path("ci/choice_callers.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const shake = b.dependencyLazy("shakedown", .{ .target = target, .optimize = optimize }) catch @panic("shakedown unavailable for A5 benchmark");
    const safety = b.createModule(.{ .root_source_file = b.path("ci/safety_parity.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const bytes = b.createModule(.{ .root_source_file = b.path("ci/bytes.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const a67 = b.createModule(.{ .root_source_file = b.path("ci/a67.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const gaps = b.createModule(.{ .root_source_file = b.path("ci/gaps.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const ab = b.createModule(.{ .root_source_file = b.path("ci/ab.zig"), .target = target, .optimize = optimize });
    const state = b.createModule(.{ .root_source_file = b.path("ci/state.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const scope = b.createModule(.{ .root_source_file = b.path("ci/scope.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    return b.allocator.dupe(std.Build.Module.Import, &.{ .{ .name = "ab", .module = ab }, .{ .name = "state", .module = state }, .{ .name = "scope", .module = scope }, .{ .name = "aegis", .module = aegis }, .{ .name = "cases", .module = cases }, .{ .name = "numeric", .module = numeric }, .{ .name = "choices", .module = choices }, .{ .name = "shakedown", .module = shake.module("shakedown") }, .{ .name = "bytes", .module = bytes }, .{ .name = "a67", .module = a67 }, .{ .name = "gaps", .module = gaps }, .{ .name = "material", .module = material }, .{ .name = "safety", .module = safety } }) catch @panic("out of memory configuring benchmarks");
}

fn choiceBenchmarkLlvm(b: *std.Build, step: *std.Build.Step, seen: *std.AutoHashMapUnmanaged(*std.Build.Step, void)) void {
    const entry = seen.getOrPut(b.allocator, step) catch @panic("OOM");
    if (entry.found_existing) return;
    if (step.cast(std.Build.Step.Compile)) |compile| {
        if (std.mem.eql(u8, compile.name, "choices") or std.mem.eql(u8, compile.name, "handles-input")) compile.use_llvm = true;
    }
    for (step.dependencies.items) |dependency| choiceBenchmarkLlvm(b, dependency, seen);
}

fn testModule(b: *std.Build, shake: *std.Build.Module, material: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    const module = b.createModule(.{ .root_source_file = b.path("src/tests.zig"), .target = target, .optimize = optimize });
    module.addImport("shakedown", shake);
    module.addImport("material", material);
    return module;
}
