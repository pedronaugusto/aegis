//! Explicit inline ownership and short spin-guarded data. Runtime closure: std only.
/// Inline secret storage with explicit exposure, transfer and unconditional erasure.
pub const Secret = @import("secret/inline.zig").Secret;
/// Owned secret bytes with explicit full capacity and unconditional pre-free erasure.
pub const SecretBytes = @import("secret/SecretBytes.zig");
/// Data beside its acquire/release spin lock; guards borrow until release.
pub const Guarded = sync.Guarded;
/// All-build checked, saturating and ranged scalar arithmetic and failing casts.
pub const int = @import("int.zig");
/// Distinct scalar identity domains and nonwrapping externally serialized issuers.
pub const id = @import("id.zig");
/// Explicit scalar units, duration scales and clock domains.
pub const units = @import("units.zig");
/// Always-on programmer contracts and explicitly optional diagnostics.
pub const assert = @import("assert.zig");

/// Bounded single-owner storage and explicit finite admission.
pub const bounded = @import("bounded.zig");
/// Static nonblocking cleanup owners and explicit result obligations.
pub const own = @import("own.zig");
/// Comptime typestate machines, staged payloads and a checked runtime transition table.
pub const state = @import("state.zig");
/// Scope lifetimes: a brand and a generation that catch a reference used after its scope ended.
pub const scope = @import("scope.zig");
/// Exclusive std.Io.Mutex guards, with explicit Io release.
pub const BlockingGuarded = sync.BlockingGuarded;
/// Bounded std.Io.RwLock guards with immutable/mutable borrows.
pub const RwGuarded = sync.RwGuarded;
/// The reader-writer form of `Guarded`: a spin lock for many readers or one writer, with no Io.
pub const SpinRwGuarded = sync.SpinRwGuarded;
/// Bounded condition waiters with guard reacquisition on every return.
pub const Condition = sync.Condition;
/// Stable initialization, retry and acquire/release publication.
pub const Once = sync.Once;
/// Leaf initialization under the election mutex: no task context, the initializer's own errors.
pub const Lazy = sync.Lazy;
/// A lock-free cell for one id, count, unit or plain enum, read and written whole.
pub const Atomic = sync.Atomic;
/// Counted shared ownership of one allocated value, cleaned by the last release.
pub const Shared = sync.Shared;
/// Explicit logical-task initializer stack; zero-sized in release.
pub const InitContext = sync.InitContext;
/// Comptime partial rank relation with Debug logical-task diagnostics.
pub const Order = sync.Order;
/// Checked single-task state in Debug/ReleaseSafe, plain payload in fast/small.
pub const Confined = sync.Confined;
/// Stable caller-issued logical-task identity for Confined.
pub const TaskIdentity = sync.TaskIdentity;

/// Copyable choices and audited byte comparison/select kernels.
pub const secret = @import("secret.zig");

/// Memory whose live part never moves: a reservation or a buffer, a bump top, marks released at
/// once, and one growing tail.
pub const Region = @import("Region.zig");
/// One flat layout for a value: a block with no pointers, read in place, written at its exact
/// size, and checked before untrusted bytes become one.
pub const flat = @import("flat.zig");
/// One block for parts whose counts are known first: a plan measures them and a block of its size
/// places them, one walk of one declaration, so placing never fails.
pub const parts = @import("parts.zig");
/// Checked generational keys and typed positions; owners require external synchronization.
pub const handle = @import("handle.zig");
/// Boundary markers preserving each parser's exact error and refined result contract.
pub const input = @import("input.zig");
/// Allocation-free closed public diagnostic frames.
pub const err = @import("err.zig");

/// The synchronization and logical-task contracts the root exports, one name each.
const sync = @import("sync.zig");

/// What each of aegis's types and assertions means, for a linter that reads it (glint, design §12): its role, the
/// fields only aegis touches, and the obligations no body shows (a reservation's count, a guard's lock,
/// a scope's record, a result that must be used). Every entry names its declaration, so a rename here
/// breaks the build instead of leaving a linter reading a name that is gone.
pub const lint_rules = .{
    .version = 1,
    .include = .{@import("Order.zig").lint_rules},
    .roles = .{
        .{ .type = Secret, .role = .secret, .internal = .{.material} },
        .{ .type = SecretBytes, .role = .bytes, .internal = .{ .allocation, .used_len } },
        .{ .type = SecretBytes.Writer, .role = .bytes_writer },
        .{ .type = secret.Choice, .role = .choice, .internal = .{.bit} },
        .{ .type = Guarded, .role = .guarded, .internal = .{ .lock, .data } },
        .{ .type = .{ .generic = Guarded, .member = .Guard }, .role = .guard, .internal = .{.owner} },
        .{ .type = .{ .generic = Guarded, .member = .Handoff }, .role = .handoff },
        .{ .type = BlockingGuarded, .role = .guarded, .internal = .{ .mutex, .data } },
        .{ .type = .{ .generic = BlockingGuarded, .member = .Guard }, .role = .guard, .internal = .{.owner} },
        .{ .type = RwGuarded, .role = .guarded, .internal = .{ .lock, .admitted, .limit, .data } },
        .{ .type = .{ .generic = RwGuarded, .member = .ReadGuard }, .role = .guard, .internal = .{.owner} },
        .{ .type = .{ .generic = RwGuarded, .member = .WriteGuard }, .role = .guard, .internal = .{.owner} },
        .{ .type = SpinRwGuarded, .role = .guarded, .internal = .{ .state, .data } },
        .{ .type = .{ .generic = SpinRwGuarded, .member = .ReadGuard }, .role = .guard, .internal = .{.owner} },
        .{ .type = .{ .generic = SpinRwGuarded, .member = .WriteGuard }, .role = .guard, .internal = .{.owner} },
        .{ .type = Condition, .role = .condition },
        .{ .type = Once, .role = .once, .internal = .{ .state, .mutex, .changed, .data } },
        .{ .type = Lazy, .role = .once, .internal = .{ .state, .mutex, .data } },
        .{ .type = Confined, .role = .confined, .internal = .{ .data, .owner } },
        .{ .type = Shared, .role = .shared, .internal = .{ .block, .live } },
        .{ .type = Atomic, .role = .atomic, .internal = .{.cell} },
        .{ .type = InitContext, .role = .context, .internal = .{ .owners, .used } },
        .{ .type = .{ .generic = Order, .member = .Context }, .role = .context, .internal = .{ .stack, .used, .suspended } },
        .{ .type = .{ .generic = Order, .member = .Ordered }, .role = .guarded, .internal = .{.base} },
        .{ .type = int.Checked, .role = .scalar },
        .{ .type = int.Saturating, .role = .scalar },
        .{ .type = int.Ranged, .role = .scalar },
        .{ .type = id.Id, .role = .scalar },
        .{ .type = id.NonZero, .role = .scalar },
        .{ .type = id.Counter, .role = .issuer },
        .{ .type = units.Count, .role = .scalar },
        .{ .type = units.Bytes, .role = .scalar },
        .{ .type = units.Bits, .role = .scalar },
        .{ .type = units.Duration, .role = .scalar },
        .{ .type = units.Instant, .role = .scalar },
        .{ .type = bounded.Array, .role = .inline_store, .internal = .{ .storage, .used } },
        .{ .type = bounded.Ring, .role = .inline_store, .internal = .{ .storage, .head, .used } },
        .{ .type = bounded.Buffer, .role = .buffer, .internal = .{ .storage, .gpa, .maximum, .used } },
        .{ .type = bounded.RingBuffer, .role = .buffer, .internal = .{ .storage, .gpa, .maximum, .head, .used } },
        .{ .type = bounded.Limit, .role = .limit, .internal = .{.maximum} },
        .{ .type = bounded.Budget, .role = .budget, .internal = .{ .ceiling, .taken, .unsettled } },
        .{ .type = .{ .generic = bounded.Budget, .member = .Reservation }, .role = .reservation, .internal = .{ .budget, .amount, .live } },
        .{ .type = own.Owned, .role = .owned, .internal = .{ .data, .state } },
        .{ .type = own.OwnedIo, .role = .owned, .internal = .{ .data, .state } },
        .{ .type = own.MustUse, .role = .must_use, .internal = .{ .data, .pending, .live } },
        .{ .type = handle.SlotPool, .role = .slots, .internal = .{ .region, .slots, .count, .free_head, .used } },
        .{ .type = handle.RunPool, .role = .slots, .internal = .{ .region, .items, .end, .free_spans, .runs } },
        .{ .type = handle.DenseSlotMap, .role = .slots, .internal = .{ .primary, .value_region, .key_region, .values, .keys, .value_room, .key_room, .used } },
        .{ .type = handle.SecondaryMap, .role = .slots, .internal = .{ .index, .region, .first, .room, .free_head } },
        .{ .type = handle.Domain, .role = .issuer },
        .{ .type = handle.Index, .role = .scalar },
        .{ .type = .{ .generic = state.Machine, .member = .At }, .role = .stage, .internal = .{ .live, .payload } },
        .{ .type = .{ .generic = state.Machine, .member = .Runtime }, .role = .machine, .internal = .{.state} },
        .{ .type = scope.Table, .role = .table, .internal = .{ .slots, .free_head, .used_up, .open_count } },
        .{ .type = .{ .generic = scope.Table, .member = .Scope }, .role = .scope, .internal = .{ .table, .generation, .index } },
        .{ .type = scope.Ref, .role = .ref, .internal = .{ .slot, .generation, .pointer } },
        .{ .type = input.Untrusted, .role = .untrusted, .internal = .{.value} },
        .{ .type = err.PublicSource, .role = .public_source },
        // The always-on contracts and the optional diagnostics, which a linter counts as assertions.
        .{ .type = assert.invariant, .role = .invariant },
        .{ .type = assert.never, .role = .never },
        .{ .type = assert.debug, .role = .debug },
        .{ .type = assert.debugCheck, .role = .debug_check },
    },
    .pairs = .{
        .{ .type = .{ .generic = bounded.Budget, .member = .Reservation }, .release = .{ .release, .consume }, .transfer = .{.moveInto} },
        .{ .type = .{ .generic = Guarded, .member = .Guard }, .release = .{.deinit}, .transfer = .{.handOff} },
        .{ .type = .{ .generic = Guarded, .member = .Handoff }, .release = .{.release} },
        .{ .type = .{ .generic = BlockingGuarded, .member = .Guard }, .release = .{.deinit} },
        .{ .type = .{ .generic = RwGuarded, .member = .ReadGuard }, .release = .{.deinit} },
        .{ .type = .{ .generic = RwGuarded, .member = .WriteGuard }, .release = .{.deinit} },
        .{ .type = .{ .generic = SpinRwGuarded, .member = .ReadGuard }, .release = .{.deinit} },
        .{ .type = .{ .generic = SpinRwGuarded, .member = .WriteGuard }, .release = .{.deinit} },
        .{ .type = .{ .generic = scope.Table, .member = .Scope }, .release = .{.end} },
        .{ .type = own.MustUse, .release = .{ .take, .acknowledge }, .teardown = .{.deinit} },
    },
};

// The tests run in this module, so test support that links aegis (shakedown)
// takes this copy and the test binary holds one aegis.
test {
    _ = @import("tests.zig");
}

test "lint_rules names declarations that are there" {
    _ = lint_rules;
}
