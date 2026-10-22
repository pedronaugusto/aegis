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
    // The checking programs run on the host, so they import aegis built for it.
    const host_aegis = b.dependency("aegis", .{ .target = b.graph.host, .optimize = .safe }).module("aegis");
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
    // The whole suite in each release mode: what a module keeps checking there, and that its
    // semantics hold where Debug's own checks are gone.
    const release_tests = b.step("test-release", "Run every test in ReleaseSafe, ReleaseFast and ReleaseSmall");
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        const release = b.addTest(.{ .name = b.fmt("aegis-tests-{t}", .{mode}), .root_module = testModule(b, b.graph.host, mode), .filters = filters, .use_llvm = true });
        release_tests.dependOn(&b.addRunArtifact(release).step);
    }

    // An example for every module, built against the module a consumer gets and run: running
    // it is what proves the code does what the text around it says. examples/usage.zig is the
    // README's Usage block (`zig build docs -- usage`).
    const examples_step = b.step("examples", "Build and run the example of every module");
    for (examples) |source| {
        const example = b.addExecutable(.{ .name = b.fmt("aegis-example-{s}", .{std.Io.Dir.path.stem(source)}), .root_module = b.createModule(.{
            .root_source_file = p.path(source),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "aegis", .module = aegis }},
        }) });
        examples_step.dependOn(&b.addRunArtifact(example).step);
        check.dependOn(&example.step);
    }
    test_step.dependOn(examples_step);

    // The catalogue: every module's release contract and what holds it. It prints the
    // README's contract table, which the docs check keeps in step.
    const catalogue = b.addExecutable(.{ .name = "aegis-catalogue", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/catalogue.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "aegis", .module = host_aegis }},
    }) });
    const run_catalogue = b.addRunArtifact(catalogue);
    run_catalogue.addArgs(&examples);
    b.step("catalogue", "Require every module's contract, layout, kernels, mode cases and example; print the contract table").dependOn(&run_catalogue.step);

    preflight.addCi(b, p, .{ .tests = test_step, .portable_tests = true, .bench = .{
        .programs = &.{ .{ .name = "owners", .source = "bench/owners.zig" }, .{ .name = "numeric", .source = "bench/numeric.zig" }, .{ .name = "choices", .source = "bench/choices.zig" }, .{ .name = "bytes", .source = "bench/bytes.zig" }, .{ .name = "guarded-bounded", .source = "bench/a67.zig" }, .{ .name = "handles-input", .source = "bench/handles_input.zig" }, .{ .name = "gaps", .source = "bench/gaps.zig" }, .{ .name = "state", .source = "bench/state.zig" }, .{ .name = "scope", .source = "bench/scope.zig" }, .{ .name = "a11", .source = "bench/a11.zig" } },
        .imports = benchImports,
        .target = target,
        .optimize = optimize,
    } });
    // preflight's benchmark API does not expose backend selection. Pin both
    // benchmark executables and their CI object projections to audited LLVM.
    var llvm_steps: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    for (b.top_level_steps.values()) |step| choiceBenchmarkLlvm(b, &step.step, &llvm_steps);
    preflight.addConsumerCheck(b, p, .{ .package = "aegis", .program = p.path("ci/consumer.zig"), .modules = &.{"aegis"} });

    // The mode matrix: each module's stops, in exactly the builds its contract names.
    const mode_matrix = b.addExecutable(.{ .name = "aegis-modes", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/modes_check.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "aegis", .module = host_aegis }},
    }) });
    const run_modes = b.addRunArtifact(mode_matrix);
    contractBinaries(b, p, run_modes, "ci/modes.zig", &.{ .debug, .safe, .fast, .small });
    b.step("check-modes", "Require every module's stops in exactly the builds its contract names").dependOn(&run_modes.step);

    // Every module's layout against hand-written storage, held for each portable profile and
    // mode by compiling; the table each object carries is read back as the layout evidence.
    const layout_report = b.addExecutable(.{ .name = "aegis-layouts", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/layout_report.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "aegis", .module = host_aegis }},
    }) });
    const run_layouts = b.addRunArtifact(layout_report);
    const layout_evidence = run_layouts.addOutputDirectoryArg2("layouts", .{});
    for (layout_profiles) |query| {
        const layout_target = b.resolveTargetQuery(query);
        for ([_]std.lang.Optimize{ .debug, .safe, .fast, .small }) |mode| {
            const object = b.addObject(.{ .name = "aegis-layouts", .root_module = contractModule(b, p, "ci/layouts.zig", layout_target, mode) });
            run_layouts.addArg(b.fmt("{s}-{t}", .{ query.zigTriple(b.allocator) catch @panic("OOM"), mode }));
            run_layouts.addFileArg(object.getEmittedBin());
        }
    }
    b.step("check-layouts", "Hold every module's layout against hand-written storage on every portable profile and mode").dependOn(&run_layouts.step);

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
    const kernel_evidence = run_codegen.addOutputDirectoryArg2("kernels", .{});
    run_codegen.setCwd(p.path("."));
    b.step("check-parity", "Require paired layout/IR/erasure parity for both release modes and CPUs").dependOn(&run_codegen.step);
    const contracts = b.addExecutable(.{ .name = "aegis-contracts", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/contracts.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    }) });
    const run_contracts = b.addRunArtifact(contracts);
    run_contracts.addArg(b.graph.zig_exe);
    run_contracts.setCwd(p.path("."));
    const contracts_step = b.step("check-contracts", "Require the raw integer ABI and portable scalar profiles");
    contracts_step.dependOn(&run_contracts.step);
    portableProfiles(b, p, contracts_step, "ci/scalars.zig", &.{.fast});
    const choices_codegen = b.addExecutable(.{ .name = "aegis-choices-codegen", .root_module = b.createModule(.{
        .root_source_file = p.path("ci/choice_codegen.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "aegis", .module = host_aegis }},
    }) });
    const run_choices_codegen = b.addRunArtifact(choices_codegen);
    run_choices_codegen.addArg(b.graph.zig_exe);
    const choice_evidence = run_choices_codegen.addOutputDirectoryArg2("choices", .{});
    run_choices_codegen.setCwd(p.path("."));
    b.step("check-choices", "Audit A5 enclosing caller instructions and secret control/address regressions").dependOn(&run_choices_codegen.step);
    const choices_negative = b.addExecutable(.{ .name = "aegis-choices-negative", .root_module = b.createModule(.{ .root_source_file = p.path("ci/choice_negative.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "aegis", .module = host_aegis }} }) });
    const run_choices_negative = b.addRunArtifact(choices_negative);
    run_choices_negative.addArg(b.graph.zig_exe);
    run_choices_negative.setCwd(p.path("."));
    b.step("check-choices-negative", "Reject unsupported A5 types, profiles and disclosure/format uses").dependOn(&run_choices_negative.step);
    portableProfiles(b, p, b.step("check-secret-bytes", "Compile the byte owner for the portable profiles"), "ci/a4_contract.zig", &.{.fast});
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
    const safety_codegen = b.addExecutable(.{ .name = "safety_codegen", .root_module = b.createModule(.{ .root_source_file = p.path("ci/safety_codegen.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_safety_codegen = b.addRunArtifact(safety_codegen);
    run_safety_codegen.addArg(b.graph.zig_exe);
    const safety_evidence = run_safety_codegen.addOutputDirectoryArg2("handles-input", .{});
    run_safety_codegen.setCwd(p.path("."));
    safety_check.dependOn(&run_safety_codegen.step);
    const safety_negative = b.addExecutable(.{ .name = "safety_negative", .root_module = b.createModule(.{ .root_source_file = p.path("ci/safety_negative.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_safety_negative = b.addRunArtifact(safety_negative);
    run_safety_negative.addArg(b.graph.zig_exe);
    run_safety_negative.setCwd(p.path("."));
    safety_check.dependOn(&run_safety_negative.step);
    portableProfiles(b, p, b.step("check-a67", "Compile the A6/A7 values for the portable profiles"), "ci/a67_values.zig", &.{ .safe, .fast });
    const a10 = b.addExecutable(.{ .name = "aegis-a10-contracts", .root_module = b.createModule(.{ .root_source_file = p.path("ci/a10_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a10 = b.addRunArtifact(a10);
    run_a10.addArg(b.graph.zig_exe);
    run_a10.setCwd(p.path("."));
    const a10_step = b.step("check-a10", "Require typestate intended-reason rejections and portable profiles");
    a10_step.dependOn(&run_a10.step);
    portableProfiles(b, p, a10_step, "ci/a10_values.zig", &.{ .safe, .fast });
    const a12 = b.addExecutable(.{ .name = "aegis-a12-contracts", .root_module = b.createModule(.{ .root_source_file = p.path("ci/a12_check.zig"), .target = b.graph.host, .optimize = .safe }) });
    const run_a12 = b.addRunArtifact(a12);
    run_a12.addArg(b.graph.zig_exe);
    run_a12.setCwd(p.path("."));
    const a12_step = b.step("check-a12", "Require scope intended-reason rejections and portable profiles");
    a12_step.dependOn(&run_a12.step);
    portableProfiles(b, p, a12_step, "ci/a12_values.zig", &.{ .safe, .fast });

    // The evidence the checks above write, under zig-out/artifacts: the layout of every module
    // on every portable profile and mode, and the instructions of every paired kernel.
    const artifacts = b.step("artifacts", "Install every module's layout and kernel evidence under zig-out/artifacts");
    for ([_]struct { std.Build.LazyPath, []const u8 }{
        .{ layout_evidence, "artifacts/layouts" },
        .{ kernel_evidence, "artifacts/kernels" },
        .{ safety_evidence, "artifacts/kernels/handles-input" },
        .{ choice_evidence, "artifacts/kernels/choices" },
    }) |evidence| artifacts.dependOn(&b.addInstallDirectory(.{ .source_dir = evidence[0], .install_dir = .prefix, .install_subdir = evidence[1] }).step);
    contractGroups(b);
}

/// Every example, listed rather than globbed: a build graph that scans a directory is not
/// reproducible from the manifest alone. ci/catalogue.zig requires one per module.
const examples = [_][]const u8{
    "examples/usage.zig",
    "examples/secret.zig",
    "examples/secret_bytes.zig",
    "examples/choice.zig",
    "examples/timing.zig",
    "examples/guarded.zig",
    "examples/spin_rw_guarded.zig",
    "examples/blocking_guarded.zig",
    "examples/rw_guarded.zig",
    "examples/condition.zig",
    "examples/once.zig",
    "examples/lazy.zig",
    "examples/atomic.zig",
    "examples/shared.zig",
    "examples/confined.zig",
    "examples/int.zig",
    "examples/id.zig",
    "examples/units.zig",
    "examples/assert.zig",
    "examples/bounded.zig",
    "examples/own.zig",
    "examples/state.zig",
    "examples/scope.zig",
    "examples/handle.zig",
    "examples/input.zig",
    "examples/err.zig",
};

/// The profiles every module's layout is held on: the hosted targets' two architectures and
/// the portable 32-bit, wasm and freestanding ones, with Windows and macOS for their ABIs.
const layout_profiles = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
    .{ .cpu_arch = .aarch64, .os_tag = .freestanding },
};

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
        .{ .name = "contracts-values", .description = "Run the value and owner contracts: paired kernels, layouts, the ABI and the portable profiles", .steps = &.{ "check-negative", "check-parity", "check-contracts", "check-secret-bytes", "check-layouts" } },
        .{ .name = "contracts-choices", .description = "Run the A5 choice contracts", .steps = &.{ "check-choices", "check-choices-negative" } },
        .{ .name = "contracts-published", .description = "Run the mode matrix, the release-mode suite and the published-module gates", .steps = &.{ "check-modes", "test-release", "check-a67", "check-handles-input", "check-a10", "check-a12", "check-consumer" } },
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
    const a11 = b.createModule(.{ .root_source_file = p.path("ci/a11.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "aegis", .module = aegis }} });
    return b.allocator.dupe(std.Build.Module.Import, &.{ .{ .name = "ab", .module = ab }, .{ .name = "state", .module = state }, .{ .name = "scope", .module = scope }, .{ .name = "a11", .module = a11 }, .{ .name = "aegis", .module = aegis }, .{ .name = "cases", .module = cases }, .{ .name = "numeric", .module = numeric }, .{ .name = "choices", .module = choices }, .{ .name = "bytes", .module = bytes }, .{ .name = "a67", .module = a67 }, .{ .name = "gaps", .module = gaps }, .{ .name = "material", .module = material }, .{ .name = "safety", .module = safety } }) catch @panic("out of memory configuring benchmarks");
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
