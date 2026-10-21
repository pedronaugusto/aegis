const std = @import("std");
/// What a project that depends on aegis builds: the `aegis` module, std only.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("aegis", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
}

/// aegis's development: its tests, examples, contract programs and benchmarks,
/// under preflight's gate. Run through bay.
pub fn dev(b: *std.Build, tools: type) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});
    const tsan = b.option(bool, "thread-sanitizer", "Instrument native thread contention on Linux") orelse false;
    const filters = b.option([]const []const u8, "test-filter", "Run tests containing this name") orelse &.{};
    const package = b.dependency("aegis", .{ .target = target, .optimize = optimize });
    const p = package.builder;
    const aegis = package.module("aegis");
    const preflight = tools.preflight;
    const test_step = b.step("test", "Run focused ownership and synchronization tests");
    const check = b.step("check", "Compile all tests without execution");
    const m = testModule(b, target, optimize);
    m.sanitize_thread = tsan;
    if (tsan) m.link_libc = true;
    const tests = b.addTest(.{ .root_module = m, .filters = filters, .use_llvm = true });
    test_step.dependOn(&b.addRunArtifact(tests).step);
    check.dependOn(&tests.step);
    // The tests whose threads contend natively, which CI runs under `-Dthread-sanitizer=true` on Linux.
    const races = b.addTest(.{ .name = "aegis-native-races", .root_module = m, .filters = &.{ "Guarded native", "Consumer Job", "A6 native", "A12 native" }, .use_llvm = true });
    b.step("test-native-races", "Run the native mutual exclusion and Job race tests").dependOn(&b.addRunArtifact(races).step);
    const example = b.addExecutable(.{ .name = "aegis-example", .root_module = b.createModule(.{
        .root_source_file = p.path("examples/usage.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "aegis", .module = aegis }},
    }) });
    test_step.dependOn(&b.addRunArtifact(example).step);
    for ([_][]const u8{ "state", "scope" }) |name| {
        const worked = b.addExecutable(.{ .name = b.fmt("aegis-example-{s}", .{name}), .root_module = b.createModule(.{
            .root_source_file = p.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "aegis", .module = aegis }},
        }) });
        test_step.dependOn(&b.addRunArtifact(worked).step);
    }
    preflight.addCi(b, p, .{ .tests = test_step, .portable_tests = true, .bench = .{
        .programs = &.{ .{ .name = "owners", .source = "bench/owners.zig" }, .{ .name = "numeric", .source = "bench/numeric.zig" }, .{ .name = "choices", .source = "bench/choices.zig" }, .{ .name = "bytes", .source = "bench/bytes.zig" }, .{ .name = "guarded-bounded", .source = "bench/a67.zig" }, .{ .name = "handles-input", .source = "bench/handles_input.zig" }, .{ .name = "gaps", .source = "bench/gaps.zig" }, .{ .name = "state", .source = "bench/state.zig" }, .{ .name = "scope", .source = "bench/scope.zig" } },
        .imports = benchImports,
        .target = target,
        .optimize = optimize,
    } });
    // preflight's benchmark API does not expose backend selection. Pin both
    // benchmark executables and their CI object projections to audited LLVM.
    var llvm_steps: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    for (b.top_level_steps.values()) |step| choiceBenchmarkLlvm(b, &step.step, &llvm_steps);
    preflight.addConsumerCheck(b, p, .{ .package = "aegis", .program = p.path("ci/consumer.zig"), .modules = &.{"aegis"} });

    const negative = b.addExecutable(.{ .name = "aegis-negative", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/negative.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_negative = b.addRunArtifact(negative);
    run_negative.addArg(b.graph.zig_exe);
    run_negative.setCwd(p.path("."));
    b.step("check-negative", "Reject pointer-bearing secret shapes at compile time").dependOn(&run_negative.step);
    const codegen = b.addExecutable(.{ .name = "aegis-codegen", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/codegen.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_codegen = b.addRunArtifact(codegen);
    run_codegen.addArg(b.graph.zig_exe);
    run_codegen.setCwd(p.path("."));
    run_codegen.addPassthruArgs();
    b.step("check-parity", "Require paired layout/IR/erasure parity for both release modes and CPUs").dependOn(&run_codegen.step);
    const contracts = b.addExecutable(.{ .name = "aegis-contracts", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/contracts.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_contracts = b.addRunArtifact(contracts);
    run_contracts.addArg(b.graph.zig_exe);
    contractBinaries(b, p, run_contracts, "ci/contract.zig", &.{ .safe, .fast });
    run_contracts.setCwd(p.path("."));
    const contracts_step = b.step("check-contracts", "Require release fail-stop and portable scalar profiles");
    contracts_step.dependOn(&run_contracts.step);
    portableProfiles(b, p, contracts_step, "ci/scalars.zig", &.{.fast});
    const choices_codegen = b.addExecutable(.{ .name = "aegis-choices-codegen", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/choice_codegen.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "aegis", .module = aegis }},
    }) });
    const run_choices_codegen = b.addRunArtifact(choices_codegen);
    run_choices_codegen.addArg(b.graph.zig_exe);
    run_choices_codegen.setCwd(p.path("."));
    run_choices_codegen.addPassthruArgs();
    b.step("check-choices", "Audit A5 enclosing caller instructions and secret control/address regressions").dependOn(&run_choices_codegen.step);
    const choices_negative = b.addExecutable(.{ .name = "aegis-choices-negative", .root_module = b.createModule(.{ .root_source_file = p.path("ci/choice_negative.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "aegis", .module = aegis }} }) });
    const run_choices_negative = b.addRunArtifact(choices_negative);
    run_choices_negative.addArg(b.graph.zig_exe);
    run_choices_negative.setCwd(p.path("."));
    b.step("check-choices-negative", "Reject unsupported A5 types, profiles and disclosure/format uses").dependOn(&run_choices_negative.step);
    const bytes_contracts = b.addExecutable(.{ .name = "aegis-bytes-contracts", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/bytes_check.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_bytes_contracts = b.addRunArtifact(bytes_contracts);
    contractBinaries(b, p, run_bytes_contracts, "ci/bytes_contract.zig", &.{ .debug, .safe, .fast });
    const bytes_step = b.step("check-secret-bytes", "Require all-mode move rejection and portable byte owner compilation");
    bytes_step.dependOn(&run_bytes_contracts.step);
    portableProfiles(b, p, bytes_step, "ci/a4_contract.zig", &.{.fast});
    // Timing's AArch64 instructions are compiled only where they can run: an object of its span
    // for each architecture, unoptimized too, where nothing else removes the dead branch.
    const timing_step = b.step("check-timing", "Compile secret.Timing's span for every architecture, a no-op where there is no mode");
    for ([_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
    }) |query| {
        const timing_target = b.resolveTargetQuery(query);
        for ([_]std.lang.Optimize{ .debug, .fast }) |mode| {
            const timing_module = b.createModule(.{ .root_source_file = p.path("ci/timing.zig"), .target = timing_target, .optimize = mode, .imports = &.{.{ .name = "aegis", .module = b.dependency("aegis", .{ .target = timing_target, .optimize = mode }).module("aegis") }} });
            const timing_object = b.addObject(.{ .name = "aegis-timing", .root_module = timing_module });
            // The object itself, not only its analysis: the assembler is what refuses.
            _ = timing_object.getEmittedBin();
            timing_step.dependOn(&timing_object.step);
        }
    }
    const focus = b.step("test-handles-input", "Run selected A8/A9 cases without unrelated tooling");
    const focused = b.addTest(.{ .root_module = m, .filters = filters, .use_llvm = true });
    focus.dependOn(&b.addRunArtifact(focused).step);
    const safety_check = b.step("check-handles-input", "Require A8/A9 portable layout/instruction and negative contracts");
    for ([_][]const u8{ "safety_codegen", "safety_negative" }) |source| {
        const program = b.addExecutable(.{ .name = source, .root_module = b.createModule(.{ .root_source_file = p.path(b.fmt("ci/{s}.zig", .{source})), .target = b.graph.host, .optimize = .safe }) });
        const run = b.addRunArtifact(program);
        run.addArg(b.graph.zig_exe);
        run.setCwd(p.path("."));
        safety_check.dependOn(&run.step);
    }
    const modes = b.step("test-handles-input-modes", "Run A8/A9 semantic contracts in all release modes");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const mode_module = testModule(b, b.graph.host, mode);
        const mode_tests = b.addTest(.{ .root_module = mode_module, .filters = &.{ "A8", "A9" }, .use_llvm = true });
        modes.dependOn(&b.addRunArtifact(mode_tests).step);
    }
    const a67 = b.addExecutable(.{ .name = "aegis-a67-contracts", .root_module = b.createModule(.{ .root_source_file = p.path("ci/a67_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a67 = b.addRunArtifact(a67);
    contractBinaries(b, p, run_a67, "ci/a67_contract.zig", &.{ .debug, .safe, .fast, .small });
    const a67_step = b.step("check-a67", "Require mode-matrix safety/diagnostics and portable value layouts");
    a67_step.dependOn(&run_a67.step);
    portableProfiles(b, p, a67_step, "ci/a67_values.zig", &.{ .safe, .fast });
    const a67_tests = b.step("test-a67", "Run A6/A7 synchronization, ownership and bounds in both release modes");
    const bytes_tests = b.step("test-secret-bytes", "Run A4 ownership contracts in both release modes");
    const scalar_tests = b.step("test-scalars", "Run A3 contracts in both release modes");
    for ([_]std.lang.Optimize{ .safe, .fast }) |mode| {
        const scalar_module = testModule(b, b.graph.host, mode);
        const release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{"A3"} });
        scalar_tests.dependOn(&b.addRunArtifact(release_tests).step);
        const a67_release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{ "A6", "A7" } });
        a67_tests.dependOn(&b.addRunArtifact(a67_release_tests).step);
        const bytes_release_tests = b.addTest(.{ .root_module = scalar_module, .filters = &.{"A4"} });
        bytes_tests.dependOn(&b.addRunArtifact(bytes_release_tests).step);
    }
    const a10 = b.addExecutable(.{ .name = "aegis-a10-contracts", .root_module = b.createModule(.{ .root_source_file = p.path("ci/a10_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a10 = b.addRunArtifact(a10);
    run_a10.addArg(b.graph.zig_exe);
    contractBinaries(b, p, run_a10, "ci/a10_contract.zig", &.{ .debug, .safe, .fast, .small });
    run_a10.setCwd(p.path("."));
    const a10_step = b.step("check-a10", "Require typestate mode-matrix contracts, intended-reason rejections and portable profiles");
    a10_step.dependOn(&run_a10.step);
    portableProfiles(b, p, a10_step, "ci/a10_values.zig", &.{ .safe, .fast });
    const a10_tests = b.step("test-a10", "Run A10 typestate semantics in the three release modes");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const release_module = testModule(b, b.graph.host, mode);
        const release_tests = b.addTest(.{ .root_module = release_module, .filters = &.{"A10"}, .use_llvm = true });
        a10_tests.dependOn(&b.addRunArtifact(release_tests).step);
    }
    const a12 = b.addExecutable(.{ .name = "aegis-a12-contracts", .root_module = b.createModule(.{ .root_source_file = p.path("ci/a12_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a12 = b.addRunArtifact(a12);
    run_a12.addArg(b.graph.zig_exe);
    contractBinaries(b, p, run_a12, "ci/a12_contract.zig", &.{ .debug, .safe, .fast, .small });
    run_a12.setCwd(p.path("."));
    const a12_step = b.step("check-a12", "Require scope mode-matrix contracts, intended-reason rejections and portable profiles");
    a12_step.dependOn(&run_a12.step);
    portableProfiles(b, p, a12_step, "ci/a12_values.zig", &.{ .safe, .fast });
    const a12_tests = b.step("test-a12", "Run A12 scope semantics in the three release modes");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const release_module = testModule(b, b.graph.host, mode);
        const release_tests = b.addTest(.{ .root_module = release_module, .filters = &.{"A12"}, .use_llvm = true });
        a12_tests.dependOn(&b.addRunArtifact(release_tests).step);
    }
    contractGroups(b);
}

/// A contract program in each mode its check runs it in, the binaries passed to the
/// check in that order. The build compiles them, so it states what they import.
fn contractBinaries(b: *std.Build, p: *std.Build, run: *std.Build.Step.Run, source: []const u8, modes: []const std.lang.Optimize) void {
    for (modes) |mode| {
        const program = b.addExecutable(.{ .name = b.fmt("{s}-{t}", .{ std.Io.Dir.path.stem(source), mode }), .root_module = contractModule(b, p, source, b.graph.host, mode) });
        run.addFileArg(program.getEmittedBin());
    }
}

/// A program that must compile for each portable profile: analysed as an object
/// for every target and mode.
fn portableProfiles(b: *std.Build, p: *std.Build, step: *std.Build.Step, source: []const u8, modes: []const std.lang.Optimize) void {
    for ([_]std.Target.Query{
        .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .{ .cpu_arch = .aarch64, .os_tag = .freestanding },
    }) |query| {
        const target = b.resolveTargetQuery(query);
        for (modes) |mode| step.dependOn(&b.addObject(.{ .name = std.Io.Dir.path.stem(source), .root_module = contractModule(b, p, source, target, mode) }).step);
    }
}

fn contractModule(b: *std.Build, p: *std.Build, source: []const u8, target: std.Build.ResolvedTarget, mode: std.lang.Optimize) *std.Build.Module {
    return b.createModule(.{ .root_source_file = p.path(source), .target = target, .optimize = mode, .imports = &.{.{ .name = "aegis", .module = b.dependency("aegis", .{ .target = target, .optimize = mode }).module("aegis") }} });
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

/// One set of modules per target and mode, as the tests' module is one per target and mode.
fn benchImports(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) []const std.Build.Module.Import {
    const key = b.fmt("{s}-{t}", .{ target.query.zigTriple(b.allocator) catch @panic("OOM"), optimize });
    if (bench_imports.get(key)) |imports| return imports;
    const imports = makeBenchImports(b, target, optimize);
    bench_imports.put(b.allocator, key, imports) catch @panic("OOM");
    return imports;
}

var bench_imports: std.StringHashMapUnmanaged([]const std.Build.Module.Import) = .empty;

fn makeBenchImports(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) []const std.Build.Module.Import {
    const p = b.dependency("aegis", .{}).builder;
    // The tests' module, which shakedown imports as its aegis.
    const aegis = testModule(b, target, optimize);
    const material = aegis.import_table.get("material").?;
    const cases = b.createModule(.{ .root_source_file = p.path("ci/cases.zig"), .target = target, .optimize = optimize, .imports = &.{ .{ .name = "aegis", .module = aegis }, .{ .name = "material", .module = material } } });
    const numeric = b.createModule(.{ .root_source_file = p.path("ci/numeric.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const choices = b.createModule(.{ .root_source_file = p.path("ci/choice_callers.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const safety = b.createModule(.{ .root_source_file = p.path("ci/safety_parity.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const bytes = b.createModule(.{ .root_source_file = p.path("ci/bytes.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const a67 = b.createModule(.{ .root_source_file = p.path("ci/a67.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const gaps = b.createModule(.{ .root_source_file = p.path("ci/gaps.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const ab = b.createModule(.{ .root_source_file = p.path("ci/ab.zig"), .target = target, .optimize = optimize });
    const state = b.createModule(.{ .root_source_file = p.path("ci/state.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    const scope = b.createModule(.{ .root_source_file = p.path("ci/scope.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    return b.allocator.dupe(std.Build.Module.Import, &.{ .{ .name = "ab", .module = ab }, .{ .name = "state", .module = state }, .{ .name = "scope", .module = scope }, .{ .name = "aegis", .module = aegis }, .{ .name = "cases", .module = cases }, .{ .name = "numeric", .module = numeric }, .{ .name = "choices", .module = choices }, .{ .name = "bytes", .module = bytes }, .{ .name = "a67", .module = a67 }, .{ .name = "gaps", .module = gaps }, .{ .name = "material", .module = material }, .{ .name = "safety", .module = safety } }) catch @panic("out of memory configuring benchmarks");
}

fn choiceBenchmarkLlvm(b: *std.Build, step: *std.Build.Step, seen: *std.AutoHashMapUnmanaged(*std.Build.Step, void)) void {
    const entry = seen.getOrPut(b.allocator, step) catch @panic("OOM");
    if (entry.found_existing) return;
    if (step.cast(std.Build.Step.Compile)) |compile| {
        if (std.mem.eql(u8, compile.name, "choices") or std.mem.eql(u8, compile.name, "handles-input")) compile.use_llvm = true;
    }
    for (step.dependencies.items) |dependency| choiceBenchmarkLlvm(b, dependency, seen);
}

/// The module the tests run in and the benchmarks import: aegis's own, with
/// shakedown and the tests' material imported. bay gives shakedown the aegis
/// under development, so shakedown's `aegis` is this module and a binary
/// links one aegis. One per target and mode, as the package is. It is one
/// module only while shakedown asks for aegis with the target and mode it is
/// asked with, as its build does: Zig keys a package instance by its options too.
fn testModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    const package = b.dependency("aegis", .{ .target = target, .optimize = optimize });
    const module = package.module("aegis");
    if (module.import_table.get("shakedown") != null) return module;
    const material = b.createModule(.{ .root_source_file = package.builder.path("src/testing/Material.zig"), .target = target, .optimize = optimize });
    module.addImport("shakedown", b.dependency("shakedown", .{ .target = target, .optimize = optimize }).module("shakedown"));
    module.addImport("material", material);
    return module;
}
