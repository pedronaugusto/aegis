//! The catalogue: every aegis module with its release contract, and what holds each part of
//! it. A module answers for its public names, states what it is in ReleaseFast and
//! ReleaseSmall and what is checked in which builds, and names its layout rows
//! (ci/layouts.zig), its paired kernels (the three codegen checks), its mode-matrix cases
//! (ci/modes.zig) and its example. This program fails when a public name, a fixture, a case,
//! a row or an example belongs to no module, or a stated check has no case to hold it, or a
//! module is neither required by a danger rule of glint's aegis pack nor built on by a module
//! that is (aegis's design §7, criterion 4); then it prints the contract table README.md shows
//! (`zig build catalogue`).
const std = @import("std");
const aegis = @import("aegis");
const modes = @import("modes.zig");
const layouts = @import("layouts.zig");
const codegen = @import("codegen.zig");
const safety = @import("safety_codegen.zig");
const choices = @import("choice_callers.zig");

pub const Module = struct {
    name: []const u8,
    /// The public declarations it answers for, as `aegis.<name>` spells them.
    names: []const []const u8,
    /// What it is in ReleaseFast and ReleaseSmall.
    release: []const u8,
    /// What stays checked or done in every build.
    always: []const u8,
    /// Checked in Debug and ReleaseSafe only, as Zig's runtime safety is.
    checked: []const u8 = "",
    /// Diagnosed in Debug only.
    debug: []const u8 = "",
    /// The paired fixtures that hold its release cost against hand-written code.
    kernels: []const []const u8,
    example: []const u8,
    /// False for a module of functions only, which has no layout to hold.
    types: bool = true,
    /// Why it is in aegis: the danger rule of glint's aegis pack that requires it at its danger
    /// sites, or the required module built on it. A module with neither goes.
    required: Required,
};

pub const Required = union(enum) {
    /// The rule's ID, A007 to A021.
    rule: []const u8,
    /// The module built on it, itself required by a rule.
    block: []const u8,
};

pub const modules = [_]Module{
    .{
        .name = "Secret",
        .required = .{ .rule = "A008" },
        .names = &.{ "Secret", "secret.Secret" },
        .release = "exactly `T`",
        .always = "the whole representation, padding included, wiped by volatile stores at `deinit` and after `moveInto`; a move into overlapping storage stops; formatting refused at compile time",
        .kernels = &.{ "secret_s32", "transfer_s32", "secret_s48", "transfer_s48", "secret_material", "transfer_material", "cleanup", "cleanup_material" },
        .example = "examples/secret.zig",
    },
    .{
        .name = "SecretBytes",
        .required = .{ .rule = "A008" },
        .names = &.{ "SecretBytes", "secret.SecretBytes" },
        .release = "allocator, allocation and live length, as a hand-written owner",
        .always = "full capacity wiped before free and on `reserve`; capacity and overlap errors before any change; a move into overlapping storage stops",
        .kernels = &.{ "bytes_dead", "bytes_cleanup", "bytes_resize", "bytes_reserve", "bytes_move", "bytes_adopt_dead", "bytes_replace" },
        .example = "examples/secret_bytes.zig",
    },
    .{
        .name = "secret",
        .required = .{ .rule = "A008" },
        .names = &.{ "secret.Choice", "secret.OrderChoices", "secret.CompareError", "secret.SelectError", "secret.equal", "secret.equalBytes", "secret.compareUnsigned", "secret.audited_profiles" },
        .release = "a `Choice` is one byte holding one bit",
        .always = "the instructions of hand-written mask arithmetic, with no branch or load on a secret in the audited profiles; unequal lengths and partial overlap are errors",
        .kernels = &choice_kernels,
        .example = "examples/choice.zig",
    },
    .{
        .name = "secret.Timing",
        .required = .{ .block = "secret" },
        .names = &.{ "secret.Timing", "secret.scrubStack", "secret.stackReach", "secret.scrubbed" },
        .release = "`Timing` is the mode it found, one `u64`",
        .always = "data-independent timing set for the span where the processor has it, nothing where it has none; `scrubStack` zeroes its frame with volatile stores",
        .kernels = &.{ "a11_timing_span", "a11_scrub_stack" },
        .example = "examples/timing.zig",
    },
    .{
        .name = "Guarded",
        .required = .{ .rule = "A007" },
        .names = &.{ "Guarded", "sync.Guarded" },
        .release = "a lock word beside `T`; a guard is one pointer",
        .always = "acquire is one swap and release one store",
        .checked = "`teardown` while the lock is held stops",
        .kernels = &.{ "increment", "job", "budget", "gaps_try_acquire", "gaps_teardown", "gaps_is_held" },
        .example = "examples/guarded.zig",
    },
    .{
        .name = "SpinRwGuarded",
        .required = .{ .rule = "A007" },
        .names = &.{ "SpinRwGuarded", "sync.SpinRwGuarded" },
        .release = "one state word beside `T`; a guard is one pointer",
        .always = "readers share and a writer excludes them, a waiting writer holding off new readers",
        .checked = "`teardown` while the lock is held stops",
        .kernels = &.{ "a11_spin_rw_read", "a11_spin_rw_write" },
        .example = "examples/spin_rw_guarded.zig",
    },
    .{
        .name = "BlockingGuarded",
        .required = .{ .rule = "A007" },
        .names = &.{ "BlockingGuarded", "sync.BlockingGuarded" },
        .release = "a `std.Io.Mutex` beside `T`; a guard is one pointer",
        .always = "the mutex's own operations; a canceled acquire grants nothing",
        .checked = "`teardown` while the lock is held stops",
        .kernels = &.{"a67_mutex"},
        .example = "examples/blocking_guarded.zig",
    },
    .{
        .name = "RwGuarded",
        .required = .{ .rule = "A007" },
        .names = &.{ "RwGuarded", "sync.RwGuarded" },
        .release = "a `std.Io.RwLock`, an admission count and its limit beside `T`",
        .always = "admission past the limit is `AdmissionLimit`, before std's packed counters can overflow",
        .checked = "`teardown` while the lock is held stops",
        .kernels = &.{ "a67_rw_read", "a67_rw_write" },
        .example = "examples/rw_guarded.zig",
    },
    .{
        .name = "Condition",
        .required = .{ .rule = "A007" },
        .names = &.{ "Condition", "sync.Condition" },
        .release = "the hand-written waiter registry",
        .always = "the waiter limit; the guard held again on every return; a wait with another owner's guard stops",
        .kernels = &.{ "a67_condition", "gaps_wait_uncancelable" },
        .example = "examples/condition.zig",
    },
    .{
        .name = "Once",
        .required = .{ .rule = "A007" },
        .names = &.{ "Once", "InitContext", "sync.Once", "sync.InitContext" },
        .release = "state, mutex, a condition and `T`; `InitContext` is empty",
        .always = "initialized once and published by a release store; the waiter limit",
        .debug = "a recursive initializer stops",
        .kernels = &.{ "a67_once_ready", "a67_once_cold" },
        .example = "examples/once.zig",
    },
    .{
        .name = "Lazy",
        .required = .{ .rule = "A007" },
        .names = &.{ "Lazy", "sync.Lazy" },
        .release = "state, mutex and `T`",
        .always = "initialized once and published by a release store; only the initializer's errors",
        .kernels = &.{ "gaps_lazy_ready", "gaps_lazy_cold", "gaps_lazy_infallible" },
        .example = "examples/lazy.zig",
    },
    .{
        .name = "Atomic",
        .required = .{ .rule = "A007" },
        .names = &.{ "Atomic", "sync.Atomic" },
        .release = "the backing integer's atomic cell",
        .always = "checked `fetchAdd` and `fetchSub` report overflow with the cell unchanged",
        .kernels = &.{ "gaps_atomic_load", "gaps_atomic_store", "gaps_atomic_swap", "gaps_atomic_compare_exchange", "gaps_atomic_max", "gaps_atomic_add_wrapping", "gaps_atomic_add" },
        .example = "examples/atomic.zig",
    },
    .{
        .name = "Shared",
        .required = .{ .rule = "A007" },
        .names = &.{ "Shared", "sync.Shared" },
        .release = "one pointer",
        .always = "the static cleanup runs once, at the last release; a count past its limit stops",
        .debug = "a handle released twice stops",
        .kernels = &.{ "gaps_shared_retain", "gaps_shared_get", "gaps_shared_release" },
        .example = "examples/shared.zig",
    },
    .{
        .name = "Order",
        .required = .{ .rule = "A021" },
        .names = &.{ "Order", "sync.Order" },
        .release = "`Context` is empty; an ordered lock is its lock",
        .always = "the lock's own operations",
        .debug = "an acquire out of rank or of an owner already held stops",
        .kernels = &.{ "a67_ordered", "gaps_ordered_uncancelable" },
        .example = "examples/order.zig",
    },
    .{
        .name = "Confined",
        .required = .{ .rule = "A007" },
        .names = &.{ "Confined", "TaskIdentity", "sync.Confined", "sync.TaskIdentity" },
        .release = "exactly `T`",
        .always = "nothing: the payload is plain data",
        .checked = "access or hand-off by a task that does not own it stops",
        .kernels = &.{"a67_confined"},
        .example = "examples/confined.zig",
    },
    .{
        .name = "int",
        .required = .{ .rule = "A010" },
        .names = &.{"int"},
        .release = "the integer",
        .always = "overflow, division by zero, invalid shifts, range and narrowing are errors; a conversion that cannot fail carries none",
        .kernels = &.{ "numeric_add", "numeric_sub", "numeric_mul", "numeric_div", "numeric_rem", "numeric_shift", "numeric_saturating", "numeric_ranged", "numeric_cast", "gaps_cast_widen", "gaps_cast_usize" },
        .example = "examples/int.zig",
    },
    .{
        .name = "id",
        .required = .{ .rule = "A016" },
        .names = &.{"id"},
        .release = "the integer",
        .always = "ids never wrap: exhaustion, underflow and a backwards distance are errors; `NonZero` refuses zero",
        .kernels = &.{ "numeric_identity", "numeric_counter", "gaps_last", "gaps_id_successor", "gaps_id_advance", "gaps_id_retreat", "gaps_id_distance" },
        .example = "examples/id.zig",
    },
    .{
        .name = "units",
        .required = .{ .rule = "A011" },
        .names = &.{"units"},
        .release = "the integer",
        .always = "arithmetic and conversions checked, a conversion that cannot fail carrying no check; text read and written exactly",
        .kernels = &.{ "numeric_count", "numeric_bits", "numeric_duration", "numeric_rounding", "numeric_instant", "numeric_encoding", "gaps_compare", "gaps_equal", "gaps_io_widen", "gaps_io_timestamp", "gaps_io_narrow", "gaps_wide_round_trip", "gaps_saturating_add", "gaps_saturating_sub", "gaps_saturating_span", "gaps_count_convert", "gaps_duration_widen", "gaps_duration_coarse" },
        .example = "examples/units.zig",
    },
    .{
        .name = "assert",
        .required = .{ .rule = "A013" },
        .names = &.{"assert"},
        .types = false,
        .release = "no storage; a check is a compare and a cold stop",
        .always = "`invariant`, `pre`, `post` and `never` stop",
        .debug = "`debug` and `debugCheck` stop",
        .kernels = &.{ "numeric_invariant", "numeric_diagnostics", "gaps_never" },
        .example = "examples/assert.zig",
    },
    .{
        .name = "bounded",
        .required = .{ .rule = "A012" },
        .names = &.{"bounded"},
        .release = "storage and counters, as hand-written",
        .always = "`Full`, `Empty`, `OutOfBounds` and `LimitExceeded` returned; a budget never holds more than its maximum; a reservation underflow stops",
        .kernels = &.{ "a67_array", "a67_queue", "a67_buffer", "a67_budget", "a67_ring_buffer", "a67_limit", "gaps_exceeds", "gaps_buffer_capacity", "gaps_buffer_full", "gaps_budget_keeping", "gaps_budget_charged" },
        .example = "examples/bounded.zig",
    },
    .{
        .name = "own",
        .required = .{ .rule = "A015" },
        .names = &.{"own"},
        .release = "exactly `T`",
        .always = "the static cleanup once, at `deinit`",
        .debug = "a second cleanup and an undischarged `MustUse` stop",
        .kernels = &.{ "a67_owned", "a67_must_use", "gaps_owned_from", "gaps_owned_io" },
        .example = "examples/own.zig",
    },
    .{
        .name = "state",
        .required = .{ .rule = "A017" },
        .names = &.{"state"},
        .release = "a stage is its payload; a runtime machine is its payload and state",
        .always = "an undeclared event is `IllegalEvent` and changes nothing; a commit of an edge the machine does not declare stops",
        .checked = "a transition into its own source stops",
        .debug = "a stage used after its payload moved on stops",
        .kernels = &.{ "state_next", "state_next_wide", "state_next_switch", "state_next_wide_switch", "state_terminal", "state_step", "state_plan_commit", "state_transition", "state_transition_with", "state_take" },
        .example = "examples/state.zig",
    },
    .{
        .name = "scope",
        .required = .{ .rule = "A014" },
        .names = &.{"scope"},
        .release = "a reference is its pointer; a table keeps nothing",
        .always = "nothing: these checks follow Zig's runtime safety",
        .checked = "a reference used after its scope ended, a scope ended twice or used after its end, and a table torn down with a scope open stop",
        .kernels = &.{ "scope_get", "scope_get_slice", "scope_make", "scope_reborrow", "scope_open", "scope_end", "scope_cycle" },
        .example = "examples/scope.zig",
    },
    .{
        .name = "handle",
        .required = .{ .rule = "A014" },
        .names = &.{"handle"},
        .release = "keys and slots as hand-written; an index is its integer",
        .always = "stale, foreign and out-of-range keys are errors; generations never wrap, a worn-out slot retires",
        .kernels = &.{ "handle_get", "handle_insert", "handle_remove", "handle_index", "dense_sum", "gaps_index_compare" },
        .example = "examples/handle.zig",
    },
    .{
        .name = "input",
        .required = .{ .rule = "A009" },
        .names = &.{"input"},
        .release = "the value or view it wraps",
        .always = "the parser's own checks and errors, unchanged",
        .kernels = &.{ "input_parse", "input_diagnostics" },
        .example = "examples/input.zig",
    },
    .{
        .name = "err",
        .required = .{ .rule = "A018" },
        .names = &.{"err"},
        .release = "inline frames, a length and a truncation mark",
        .always = "frames kept up to the capacity and truncation marked; nothing allocated",
        .kernels = &.{"context_push"},
        .example = "examples/err.zig",
    },
};

/// The namespaces whose members are claimed one by one; every other public name is a module.
const namespaces = [_][]const u8{ "secret", "sync" };

/// The Choice harness's callers, as the catalogue names them.
const choice_kernels = blk: {
    var names: [choices.names.len][]const u8 = undefined;
    for (&names, 0..) |*name, i| name.* = "choice_" ++ choices.names[i];
    break :blk names;
};

const Failure = error{CatalogueIncomplete};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var err = std.Io.File.stderr().writerStreaming(init.io, &.{});
    var failed = false;
    // Every public name of aegis, its namespaces' members one by one.
    inline for (@typeInfo(aegis).@"struct".decl_names) |decl| {
        if (comptime isNamespace(decl)) {
            inline for (@typeInfo(@field(aegis, decl)).@"struct".decl_names) |member| failed = !try claimed(&err.interface, decl ++ "." ++ member) or failed;
        } else failed = !try claimed(&err.interface, decl) or failed;
    }
    for (modules) |module| {
        for (module.names) |name| if (!public(name)) {
            try err.interface.print("catalogue: {s} names {s}, which aegis does not declare\n", .{ module.name, name });
            failed = true;
        };
        var layout_rows: usize = 0;
        for (layouts.names) |row| layout_rows += @intFromBool(std.mem.eql(u8, row.module, module.name));
        if (module.types != (layout_rows != 0)) {
            try err.interface.print("catalogue: {s}: {s}\n", .{ module.name, if (module.types) "no layout row" else "layout rows for a module of functions" });
            failed = true;
        }
        if (module.kernels.len == 0) {
            try err.interface.print("catalogue: {s} has no paired kernel\n", .{module.name});
            failed = true;
        }
        for (module.kernels) |kernel| if (!fixture(kernel)) {
            try err.interface.print("catalogue: {s} names kernel {s}, which no codegen check compares\n", .{ module.name, kernel });
            failed = true;
        };
        inline for (.{ .{ "checked", modes.When.checked }, .{ "debug", modes.When.debug } }) |column| {
            const stated = @field(module, column[0]).len != 0;
            var held = false;
            for (modes.cases) |case| held = held or (case.when == column[1] and std.mem.eql(u8, case.module, module.name));
            if (stated != held) {
                try err.interface.print("catalogue: {s} {s}: {s}\n", .{ module.name, column[0], if (stated) "stated with no mode-matrix case to hold it" else "a mode-matrix case the contract does not state" });
                failed = true;
            }
        }
        if (!listed(args[1..], module.example)) {
            try err.interface.print("catalogue: {s}'s example {s} is not one the build runs\n", .{ module.name, module.example });
            failed = true;
        }
    }
    for (layouts.names) |row| if (!known(row.module)) {
        try err.interface.print("catalogue: layout row {s} names no module ({s})\n", .{ row.label, row.module });
        failed = true;
    };
    for (modes.cases) |case| if (!known(case.module)) {
        try err.interface.print("catalogue: mode case {s} names no module ({s})\n", .{ case.name, case.module });
        failed = true;
    };
    for (codegen.names ++ safety.names ++ choice_kernels) |kernel| {
        var owners: usize = 0;
        for (modules) |module| {
            for (module.kernels) |name| owners += @intFromBool(std.mem.eql(u8, name, kernel));
        }
        if (owners != 1) {
            try err.interface.print("catalogue: kernel {s} belongs to {d} modules, not one\n", .{ kernel, owners });
            failed = true;
        }
    }
    for (args[1..]) |example| {
        var owners: usize = 0;
        for (modules) |module| owners += @intFromBool(std.mem.eql(u8, module.example, example));
        if (owners != 1 and !std.mem.eql(u8, example, "examples/usage.zig")) {
            try err.interface.print("catalogue: example {s} belongs to {d} modules, not one\n", .{ example, owners });
            failed = true;
        }
    }
    for (modules) |module| if (!try earned(&err.interface, module)) {
        failed = true;
    };
    if (failed) return Failure.CatalogueIncomplete;
    var out = std.Io.File.stdout().writerStreaming(init.io, &.{});
    try table(&out.interface);
}

/// Whether a module earns its place: a danger rule (A007 to A021) requires it, or a module a
/// rule requires is built on it.
fn earned(err: *std.Io.Writer, module: Module) !bool {
    switch (module.required) {
        .rule => |id| {
            const number = if (id.len == 4 and id[0] == 'A') std.fmt.parseInt(u8, id[1..], 10) catch 0 else 0;
            if (number >= 7 and number <= 21) return true;
            try err.print("catalogue: {s} names {s}, which is no danger rule (A007 to A021)\n", .{ module.name, id });
        },
        .block => |name| {
            for (modules) |other| if (std.mem.eql(u8, other.name, name)) {
                if (other.required == .rule) return true;
                try err.print("catalogue: {s} is built on by {s}, which no rule requires\n", .{ module.name, name });
                return false;
            };
            try err.print("catalogue: {s} is built on by {s}, which is no module\n", .{ module.name, name });
        },
    }
    return false;
}

/// The README's contract table, one row per module.
fn table(out: *std.Io.Writer) !void {
    try out.writeAll("| Module | Required by | In ReleaseFast and ReleaseSmall | In every build | Debug and ReleaseSafe | Debug | Example |\n|---|---|---|---|---|---|---|\n");
    for (modules) |module| {
        var buffer: [64]u8 = undefined;
        const why = switch (module.required) {
            .rule => |id| id,
            .block => |name| try std.mem.print(&buffer, "`{s}` builds on it", .{name}),
        };
        try out.print("| `{s}` | {s} | {s} | {s} | {s} | {s} | [{s}]({s}) |\n", .{ module.name, why, module.release, module.always, orDash(module.checked), orDash(module.debug), std.Io.Dir.path.basename(module.example), module.example });
    }
}

fn orDash(text: []const u8) []const u8 {
    return if (text.len == 0) "—" else text;
}

fn isNamespace(comptime name: []const u8) bool {
    for (namespaces) |namespace| if (std.mem.eql(u8, name, namespace)) return true;
    return false;
}

fn claimed(err: *std.Io.Writer, name: []const u8) !bool {
    var owners: usize = 0;
    for (modules) |module| {
        for (module.names) |owned| owners += @intFromBool(std.mem.eql(u8, owned, name));
    }
    if (owners == 1) return true;
    try err.print("catalogue: aegis.{s} belongs to {d} modules, not one\n", .{ name, owners });
    return false;
}

fn public(name: []const u8) bool {
    inline for (@typeInfo(aegis).@"struct".decl_names) |decl| {
        if (comptime isNamespace(decl)) {
            inline for (@typeInfo(@field(aegis, decl)).@"struct".decl_names) |member| if (std.mem.eql(u8, name, decl ++ "." ++ member)) return true;
        } else if (std.mem.eql(u8, name, decl)) return true;
    }
    return false;
}

fn fixture(name: []const u8) bool {
    for (codegen.names ++ safety.names ++ choice_kernels) |kernel| if (std.mem.eql(u8, kernel, name)) return true;
    return false;
}

fn known(name: []const u8) bool {
    for (modules) |module| if (std.mem.eql(u8, module.name, name)) return true;
    return false;
}

fn listed(examples: []const []const u8, path: []const u8) bool {
    for (examples) |example| if (std.mem.eql(u8, example, path)) return true;
    return false;
}
