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
/// A one-shot signal across tasks: set once by any side, waited on by any task, with the value it was set with.
pub const Signal = sync.Signal;
pub const Pulse = sync.Pulse;
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
/// Stream ends that state why they failed: a reader or writer with the way to its cause.
pub const io = @import("io.zig");
/// Boundary markers preserving each parser's exact error and refined result contract.
pub const input = @import("input.zig");
/// Allocation-free closed public diagnostic frames.
pub const err = @import("err.zig");
/// Fault points a package marks in its own code for a test's driver to decide; compiled out of
/// every build but a test build.
pub const points = @import("points.zig");

const std = @import("std");
/// The synchronization and logical-task contracts the root exports, one name each.
const sync = @import("sync.zig");

/// The rules aegis declares for a linter that reads them (glint), in the vocabulary any package may use (version
/// 2): `governed`, a type whose fields are aegis's alone and no cast or reflection outside aegis may reach, with the
/// exits that give its bare value out; `replaces`, a declaration, a builtin or a symbol aegis's answer stands for,
/// reported under the rule the entry names wherever it is used outside a seam the project declares. A rule the
/// project does not select is not checked (lock order is off until a project selects it). Every entry names its
/// declaration, so a rename here breaks the build instead of leaving a linter reading a name that is gone.
pub const lint_rules = .{
    .version = 2,
    .include = .{@import("Order.zig").lint_rules},
    .rules = .{
        .{ .id = .A001, .name = "governed state", .kind = .ban, .reads = .governed, .default = true, .purpose = "a governed type's internal fields, and any cast or reflection over the type, are aegis's alone: outside aegis each is a finding" },
        .{ .id = .A004, .name = "bare value", .kind = .hygiene, .reads = .exits, .default = true, .purpose = "a governed type's bare value given straight to arithmetic, a comparison or a narrowing cast loses the type's checks: use the type's own operation" },
        .{ .id = .A007, .name = "shared state", .kind = .ban, .reads = .replaces, .default = true, .purpose = "std's locks, atomics and futexes outside a seam: aegis's guarded types are the answer" },
        .{ .id = .A008, .name = "secrets", .kind = .ban, .reads = .replaces, .default = true, .purpose = "std's secret keys, zeroing and constant-time comparisons outside a seam: Secret, SecretBytes and secret's comparisons are the answer" },
        .{ .id = .A009, .name = "input seam", .kind = .ban, .reads = .replaces, .default = true, .purpose = "where bytes from outside enter (a reader made over a file, a pipe or a socket; a direct file, link, process or descriptor read) only in a declared input seam, so a program's input entry points are few, named and counted; whether what enters leaves as input.Untrusted is design review's, not this rule's" },
        .{ .id = .A012, .name = "bounded containers", .kind = .ban, .reads = .replaces, .default = false, .purpose = "where a project selects it, a std container that grows without a stated limit: bounded's Array, Buffer, Ring and RingBuffer hold a capacity the program states" },
        .{ .id = .A011, .name = "units", .kind = .ban, .reads = .replaces, .default = true, .purpose = "std's raw time conversions and per-unit constants outside a seam: units.Duration and units.Instant are the answer" },
        .{ .id = .A013, .name = "contracts", .kind = .ban, .reads = .replaces, .default = true, .purpose = "std.debug.assert is gone in ReleaseFast: aegis's assert keeps the contract in every build" },
        .{ .id = .A015, .name = "owned handles", .kind = .ban, .reads = .replaces, .default = true, .purpose = "a std handle held by value in a field is an owner nothing checks: own.OwnedIo releases it" },
        .{ .id = .A021, .name = "lock order", .kind = .ban, .reads = .replaces, .default = false, .purpose = "where a project selects it, every acquisition is ranked: Order checks the ranks at run time" },
    },
    .governed = .{
        .{ .type = Secret, .internal = .{.aegis_material} },
        .{ .type = SecretBytes, .internal = .{ .aegis_allocation, .aegis_used_len } },
        .{ .type = SecretBytes.Writer },
        .{ .type = secret.Choice, .internal = .{.aegis_bit} },
        .{ .type = Guarded, .internal = .{ .aegis_lock, .aegis_data } },
        .{ .type = .{ .generic = Guarded, .member = .Guard }, .internal = .{.aegis_owner} },
        .{ .type = .{ .generic = Guarded, .member = .Handoff } },
        .{ .type = BlockingGuarded, .internal = .{ .aegis_mutex, .aegis_data } },
        .{ .type = .{ .generic = BlockingGuarded, .member = .Guard }, .internal = .{.aegis_owner} },
        .{ .type = RwGuarded, .internal = .{ .aegis_lock, .aegis_admitted, .aegis_limit, .aegis_data } },
        .{ .type = .{ .generic = RwGuarded, .member = .ReadGuard }, .internal = .{.aegis_owner} },
        .{ .type = .{ .generic = RwGuarded, .member = .WriteGuard }, .internal = .{.aegis_owner} },
        .{ .type = SpinRwGuarded, .internal = .{ .aegis_state, .aegis_data } },
        .{ .type = .{ .generic = SpinRwGuarded, .member = .ReadGuard }, .internal = .{.aegis_owner} },
        .{ .type = .{ .generic = SpinRwGuarded, .member = .WriteGuard }, .internal = .{.aegis_owner} },
        .{ .type = Condition, .internal = .{ .aegis_mutex, .aegis_associated, .aegis_first, .aegis_count, .aegis_limit } },
        .{ .type = Once, .internal = .{ .aegis_state, .aegis_mutex, .aegis_changed, .aegis_data } },
        .{ .type = Lazy, .internal = .{ .aegis_state, .aegis_mutex, .aegis_data } },
        .{ .type = Signal, .internal = .{ .aegis_state, .aegis_value } },
        .{ .type = Pulse, .internal = .{.aegis_generation} },
        .{ .type = Confined, .internal = .{ .aegis_data, .aegis_owner } },
        .{ .type = Shared, .internal = .{ .aegis_block, .aegis_live } },
        .{ .type = Atomic, .internal = .{.aegis_cell} },
        .{ .type = InitContext, .internal = .{ .aegis_owners, .aegis_used } },
        .{ .type = .{ .generic = Order, .member = .Context }, .internal = .{ .aegis_stack, .aegis_used, .aegis_suspended } },
        .{ .type = .{ .generic = Order, .member = .Ordered }, .internal = .{.aegis_base} },
        .{ .type = int.Checked, .exits = .{.raw} },
        .{ .type = int.Saturating, .exits = .{.raw} },
        .{ .type = int.Ranged, .exits = .{.raw} },
        .{ .type = id.Id, .exits = .{.raw} },
        .{ .type = id.NonZero },
        .{ .type = id.Counter },
        .{ .type = units.Count, .exits = .{.raw} },
        .{ .type = units.Bytes, .exits = .{.raw} },
        .{ .type = units.Bits, .exits = .{.raw} },
        .{ .type = units.Duration, .exits = .{.raw} },
        .{ .type = units.Instant, .exits = .{.raw} },
        .{ .type = bounded.Array, .internal = .{ .aegis_storage, .aegis_used } },
        .{ .type = bounded.Ring, .internal = .{ .aegis_storage, .aegis_head, .aegis_used } },
        .{ .type = bounded.Buffer, .internal = .{ .aegis_storage, .aegis_gpa, .aegis_maximum, .aegis_used } },
        .{ .type = bounded.RingBuffer, .internal = .{ .aegis_storage, .aegis_gpa, .aegis_maximum, .aegis_head, .aegis_used } },
        .{ .type = bounded.Limit, .internal = .{.aegis_maximum} },
        .{ .type = bounded.Budget, .internal = .{ .aegis_ceiling, .aegis_taken, .aegis_unsettled } },
        .{ .type = .{ .generic = bounded.Budget, .member = .Reservation }, .internal = .{ .aegis_budget, .aegis_amount, .aegis_live } },
        .{ .type = own.Owned, .internal = .{ .aegis_data, .aegis_state } },
        .{ .type = own.OwnedIo, .internal = .{ .aegis_data, .aegis_state } },
        .{ .type = own.Unowned, .internal = .{.aegis_handle} },
        .{ .type = own.MustUse, .internal = .{ .aegis_data, .aegis_pending, .aegis_live } },
        .{ .type = handle.SlotPool, .internal = .{ .aegis_region, .aegis_slots, .aegis_count, .aegis_free_head, .aegis_used } },
        .{ .type = handle.RunPool, .internal = .{ .aegis_region, .aegis_items, .aegis_end, .aegis_free_spans, .aegis_runs } },
        .{ .type = handle.DenseSlotMap, .internal = .{ .aegis_primary, .aegis_value_region, .aegis_key_region, .aegis_values, .aegis_keys, .aegis_value_room, .aegis_key_room, .aegis_used } },
        .{ .type = handle.SecondaryMap, .internal = .{ .aegis_index, .aegis_region, .aegis_first, .aegis_room, .aegis_free_head } },
        .{ .type = handle.Domain },
        .{ .type = handle.Index },
        .{ .type = .{ .generic = state.Machine, .member = .At }, .internal = .{ .aegis_live, .aegis_payload } },
        .{ .type = .{ .generic = state.Machine, .member = .Runtime }, .internal = .{.aegis_state} },
        .{ .type = scope.Table, .internal = .{ .aegis_slots, .aegis_free_head, .aegis_used_up, .aegis_open_count } },
        .{ .type = .{ .generic = scope.Table, .member = .Scope }, .internal = .{ .aegis_table, .aegis_generation, .aegis_index } },
        .{ .type = scope.Ref, .internal = .{ .aegis_slot, .aegis_generation, .aegis_pointer } },
        .{ .type = input.Untrusted, .internal = .{.aegis_value} },
        .{ .type = err.PublicSource },
    },
    .replaces = .{
        // A007: locks, atomics and words signalled by hand.
        .{ .rule = .A007, .decl = std.Io.Mutex, .with = .{ Guarded, BlockingGuarded }, .why = "a lock apart from the data it guards: Guarded holds the data and hands it out only under the lock" },
        .{ .rule = .A007, .decl = std.Io.RwLock, .with = RwGuarded, .why = "a reader-writer lock apart from its data: RwGuarded holds the data and hands it out under a read or write guard" },
        .{ .rule = .A007, .decl = std.Io.Condition, .with = Condition, .why = "a condition apart from the lock its predicate needs: aegis's Condition waits on a guard" },
        .{ .rule = .A007, .decl = std.Io.Event, .with = .{ Signal, Pulse, Once, Lazy }, .why = "a flag set and waited on by hand, re-armed by a reset that races its waiters: a wake given once is a Signal, set by the side that has the value and handed to every waiter; a wake given again and again is a Pulse, waited past by the generation a waiter last saw, with no reset to race; Once and Lazy initialize on demand in whoever comes first" },
        .{ .rule = .A007, .decl = std.atomic.Value, .with = .{ Atomic, Shared }, .why = "a raw atomic: Atomic is one cell of a named domain shared by pointer, with the orderings named. A bool flag is Atomic of a two-state enum, a counter Atomic(units.Count), an id Atomic(id.Id), a published address Atomic(*T); a reference count is Shared" },
        .{ .rule = .A007, .decl = std.atomic.Mutex, .with = SpinRwGuarded, .why = "a spin lock apart from its data: SpinRwGuarded holds the data" },
        .{ .rule = .A007, .decl = std.Io.futexWait, .with = Condition, .why = "a wait on a word signalled by hand: Condition waits on a guard" },
        .{ .rule = .A007, .decl = std.Io.futexWaitTimeout, .with = Condition, .why = "a wait on a word signalled by hand: Condition waits on a guard" },
        .{ .rule = .A007, .decl = std.Io.futexWaitUncancelable, .with = Condition, .why = "a wait on a word signalled by hand: Condition waits on a guard" },
        .{ .rule = .A007, .decl = std.Io.futexWake, .with = Condition, .why = "a word signalled by hand: Condition signals a guard's waiters" },
        .{ .rule = .A007, .builtin = .@"@atomicLoad", .with = Atomic, .why = "a raw atomic access: Atomic names the cell and its ordering" },
        .{ .rule = .A007, .builtin = .@"@atomicStore", .with = Atomic, .why = "a raw atomic access: Atomic names the cell and its ordering" },
        .{ .rule = .A007, .builtin = .@"@atomicRmw", .with = Atomic, .why = "a raw atomic access: Atomic names the cell and its ordering" },
        .{ .rule = .A007, .builtin = .@"@cmpxchgWeak", .with = Atomic, .why = "a raw atomic access: Atomic names the cell and its ordering" },
        .{ .rule = .A007, .builtin = .@"@cmpxchgStrong", .with = Atomic, .why = "a raw atomic access: Atomic names the cell and its ordering" },
        // A008: keys, zeroing, comparisons.
        .{ .rule = .A008, .decl = std.crypto.secureZero, .with = SecretBytes, .why = "zeroing by hand misses a copy: SecretBytes scrubs its allocation when it ends" },
        .{ .rule = .A008, .decl = std.crypto.timing_safe.eql, .with = secret.equal, .why = "secret.equal compares in constant time and answers a Choice, never a branchable bool" },
        .{ .rule = .A008, .decl = std.crypto.timing_safe.compare, .with = secret.compareUnsigned, .why = "secret.compareUnsigned orders in constant time and answers Choices" },
        .{ .rule = .A008, .decl = std.crypto.sign.Ed25519.SecretKey, .with = Secret, .why = "a secret key held as plain bytes is copied and left in memory: Secret holds it and scrubs it" },
        .{ .rule = .A008, .decl = std.crypto.sign.Ed25519.KeyPair, .with = Secret, .why = "a key pair holds its secret key as plain bytes: Secret holds it and scrubs it" },
        .{ .rule = .A008, .decl = std.crypto.dh.X25519.KeyPair, .with = Secret, .why = "a key pair holds its secret key as plain bytes: Secret holds it and scrubs it" },
        .{ .rule = .A008, .decl = std.crypto.sign.ecdsa.EcdsaP256Sha256.SecretKey, .with = Secret, .why = "a secret key held as plain bytes (every Ecdsa instance's, by its declaration): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.sign.ecdsa.EcdsaP256Sha256.KeyPair, .with = Secret, .why = "a key pair holds its secret key as plain bytes (every Ecdsa instance's): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.kem.hybrid.MlKem768X25519.SecretKey, .with = Secret, .why = "a secret key held as plain bytes (every hybrid KEM instance's): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.kem.hybrid.MlKem768X25519.KeyPair, .with = Secret, .why = "a key pair holds its secret key as plain bytes (every hybrid KEM instance's): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.kem.ml_kem.MLKem768.SecretKey, .with = Secret, .why = "a secret key held as plain bytes (every ML-KEM and Kyber instance's): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.kem.ml_kem.MLKem768.KeyPair, .with = Secret, .why = "a key pair holds its secret key as plain bytes (every ML-KEM and Kyber instance's): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.sign.mldsa.MLDSA65.SecretKey, .with = Secret, .why = "a secret key held as plain bytes (every ML-DSA instance's): Secret holds it" },
        .{ .rule = .A008, .decl = std.crypto.sign.mldsa.MLDSA65.KeyPair, .with = Secret, .why = "a key pair holds its secret key as plain bytes (every ML-DSA instance's): Secret holds it" },
        // A009: the input sources. Every function of std's reader gives bytes from outside but those that make, wrap
        // or skip; a new one a Zig adds is a source until it is named here.
        .{ .rule = .A009, .decl = std.Io.File.reader, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.File.readerStreaming, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.File.Reader.init, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.File.Reader.initStreaming, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.net.Stream.reader, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.net.Stream.readerWithControl, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.net.Stream.Reader.init, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.net.Stream.Reader.initWithControl, .with = input.Untrusted, .why = "where bytes from outside enter the program: a reader over a file, a pipe or a socket is made in the input seam, so the program's entry points are few, named and counted" },
        .{ .rule = .A009, .decl = std.Io.File.readStreaming, .with = input.Untrusted, .why = "a file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.File.readPositional, .with = input.Untrusted, .why = "a file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.File.readPositionalAll, .with = input.Untrusted, .why = "a file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.Dir.readFile, .with = input.Untrusted, .why = "a file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.Dir.readLink, .with = input.Untrusted, .why = "a link's target is input: read it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.Dir.readFileAlloc, .with = own.readFile, .why = "a file's contents are input, read in the input seam; std's takes a failed length as a guess and reads on, so a cancel that lands there is lost: own.readFile returns it, under a limit the caller gives" },
        .{ .rule = .A009, .decl = std.Io.Dir.readFileAllocOptions, .with = own.readFile, .why = "a file's contents are input, read in the input seam; std's loses a cancel that lands on the length: own.readFile (own.readFileSentinel for a sentinel) returns it" },
        .{ .rule = .A009, .decl = own.readFile, .with = input.Untrusted, .why = "a file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = own.readFileSentinel, .with = input.Untrusted, .why = "a file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = own.readOpened, .with = input.Untrusted, .why = "an opened file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = own.readOpenedSentinel, .with = input.Untrusted, .why = "an opened file's contents are input: read them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.net.Stream.read, .with = input.Untrusted, .why = "what a socket gives is input: read it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.net.Stream.readWithControl, .with = input.Untrusted, .why = "what a socket gives is input: read it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.net.Socket.receive, .with = input.Untrusted, .why = "a datagram is input: receive it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.net.Socket.receiveTimeout, .with = input.Untrusted, .why = "a datagram is input: receive it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.net.Socket.receiveManyTimeout, .with = input.Untrusted, .why = "datagrams are input: receive them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.Dir.readLinkAbsolute, .with = input.Untrusted, .why = "a link's target is input: read it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.File.MemoryMap.create, .with = input.Untrusted, .why = "a file mapped into memory is its contents, input: map it in the input seam" },
        .{ .rule = .A009, .decl = std.Io.File.MemoryMap.read, .with = input.Untrusted, .why = "a file's contents read into its map are input: read them in the input seam" },
        .{ .rule = .A009, .decl = std.Io.File.MultiReader.init, .with = input.Untrusted, .why = "readers over several files, pipes or sockets take in input: make them in the input seam" },
        .{ .rule = .A009, .field = .{ .type = std.Io.Operation, .name = .file_read_streaming }, .with = input.Untrusted, .why = "the read a file reader runs, asked of the Io directly, takes in input: ask it in the input seam" },
        .{ .rule = .A009, .field = .{ .type = std.Io.Operation, .name = .net_receive }, .with = input.Untrusted, .why = "the receive a socket runs, asked of the Io directly, takes in input: ask it in the input seam" },
        .{ .rule = .A009, .field = .{ .type = std.Io.Operation, .name = .net_read }, .with = input.Untrusted, .why = "the read a stream runs, asked of the Io directly, takes in input: ask it in the input seam" },
        .{ .rule = .A009, .field = .{ .type = std.Io.VTable, .name = .fileReadPositional }, .with = input.Untrusted, .why = "the Io implementation's file read, called through its table, takes in input: read in the input seam" },
        .{ .rule = .A009, .field = .{ .type = std.Io.VTable, .name = .fileMemoryMapRead }, .with = input.Untrusted, .why = "the Io implementation's map read, called through its table, takes in input: read in the input seam" },
        .{ .rule = .A009, .field = .{ .type = std.Io.VTable, .name = .dirReadLink }, .with = input.Untrusted, .why = "the Io implementation's link read, called through its table, takes in input: read in the input seam" },
        .{ .rule = .A009, .decl = std.process.run, .with = input.Untrusted, .why = "a child's output is input: run it in the input seam" },
        .{ .rule = .A009, .decl = std.posix.read, .with = input.Untrusted, .why = "what a descriptor gives is input: read it in the input seam" },
        // A011: time by hand.
        .{ .rule = .A011, .members = std.Io.Duration, .except = .{std.Io.Duration.format}, .with = units.Duration, .why = "a duration converted by hand drops its unit: units.Duration carries it" },
        .{ .rule = .A011, .field = .{ .type = std.Io.Duration, .name = .nanoseconds }, .with = units.Duration, .why = "a raw nanosecond count drops its unit: units.Duration carries it" },
        .{ .rule = .A011, .decl = std.Io.Timestamp.fromNanoseconds, .with = units.Instant, .why = "an instant made by hand drops its clock: units.Instant carries it" },
        .{ .rule = .A011, .decl = std.Io.Timestamp.toNanoseconds, .with = units.Instant, .why = "an instant read out by hand drops its clock: units.Instant carries it" },
        .{ .rule = .A011, .decl = std.Io.Timestamp.toMicroseconds, .with = units.Instant, .why = "an instant read out by hand drops its clock: units.Instant carries it" },
        .{ .rule = .A011, .decl = std.Io.Timestamp.toMilliseconds, .with = units.Instant, .why = "an instant read out by hand drops its clock: units.Instant carries it" },
        .{ .rule = .A011, .decl = std.Io.Timestamp.toSeconds, .with = units.Instant, .why = "an instant read out by hand drops its clock: units.Instant carries it" },
        .{ .rule = .A011, .field = .{ .type = std.Io.Timestamp, .name = .nanoseconds }, .with = units.Instant, .why = "a raw nanosecond count drops its clock: units.Instant carries it" },
        .{ .rule = .A011, .decl = std.time.ns_per_us, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ns_per_ms, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ns_per_s, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ns_per_min, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ns_per_hour, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ns_per_day, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ns_per_week, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.us_per_ms, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.us_per_s, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.us_per_min, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.us_per_hour, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.us_per_day, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.us_per_week, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ms_per_s, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ms_per_min, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ms_per_hour, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ms_per_day, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.ms_per_week, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.s_per_min, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.s_per_hour, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.s_per_day, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        .{ .rule = .A011, .decl = std.time.s_per_week, .with = units.Duration, .why = "a per-unit constant in arithmetic converts by hand: units.Duration converts" },
        // A013: the contract kept in every build. The answers are the assertions a linter counts.
        .{ .rule = .A013, .decl = std.debug.assert, .with = .{ assert.invariant, assert.debug, assert.debugCheck }, .drop_in = assert.invariant, .why = "std's assert is unreachable in ReleaseFast, so a broken contract is undefined behaviour there: assert.invariant keeps it in every build, assert.debug says it is a diagnostic" },
        // A015: std handles held by value in a field.
        .{ .rule = .A015, .decl = std.Io.File, .held = .field, .with = .{ own.OwnedIo, own.Unowned }, .why = "a file held by value in a field is an owner nothing checks: own.OwnedIo releases it once; own.Unowned names one its owner keeps and closes" },
        .{ .rule = .A015, .decl = std.Io.Dir, .held = .field, .with = .{ own.OwnedIo, own.Unowned }, .why = "a directory held by value in a field is an owner nothing checks: own.OwnedIo releases it once; own.Unowned names one its owner keeps and closes" },
        .{ .rule = .A015, .decl = std.Io.net.Stream, .held = .field, .with = .{ own.OwnedIo, own.Unowned }, .why = "a stream held by value in a field is an owner nothing checks: own.OwnedIo releases it once; own.Unowned names one its owner keeps and closes" },
        .{ .rule = .A015, .decl = std.Io.net.Server, .held = .field, .with = .{ own.OwnedIo, own.Unowned }, .why = "a server held by value in a field is an owner nothing checks: own.OwnedIo releases it once; own.Unowned names one its owner keeps and closes" },
        .{ .rule = .A015, .decl = std.process.Child, .held = .field, .with = .{ own.OwnedIo, own.Unowned }, .why = "a child held by value in a field is an owner nothing checks: own.OwnedIo waits for it once; own.Unowned names one its owner waits for" },
        // A012: growth with a stated limit, where a project selects it. std's maps, MultiArrayList and
        // priority queues have no bounded answer in aegis, so they are not named.
        .{ .rule = .A012, .decl = std.ArrayList, .with = .{ bounded.Array, bounded.Buffer }, .why = "a list that grows without a limit: bounded.Array holds its capacity inline, bounded.Buffer over memory the caller states" },
        .{ .rule = .A012, .decl = std.array_list.Aligned, .with = .{ bounded.Array, bounded.Buffer }, .why = "a list that grows without a limit: bounded.Array holds its capacity inline, bounded.Buffer over memory the caller states" },
        .{ .rule = .A012, .decl = std.array_list.Managed, .with = .{ bounded.Array, bounded.Buffer }, .why = "a list that grows without a limit: bounded.Array holds its capacity inline, bounded.Buffer over memory the caller states" },
        .{ .rule = .A012, .decl = std.array_list.AlignedManaged, .with = .{ bounded.Array, bounded.Buffer }, .why = "a list that grows without a limit: bounded.Array holds its capacity inline, bounded.Buffer over memory the caller states" },
        .{ .rule = .A012, .decl = std.Deque, .with = .{ bounded.Ring, bounded.RingBuffer }, .why = "a queue that grows without a limit: bounded.Ring holds its capacity inline, bounded.RingBuffer over memory the caller states" },
        // A021: every acquisition ranked, where a project selects it.
        .{ .rule = .A021, .decl = .{ .generic = Guarded, .member = .acquire }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = Guarded, .member = .acquireScheduling }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = Guarded, .member = .tryAcquire }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = Guarded, .member = .acquireYielding }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = Guarded, .member = .acquireYieldingUncancelable }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = BlockingGuarded, .member = .acquire }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = BlockingGuarded, .member = .acquireUncancelable }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = BlockingGuarded, .member = .tryAcquire }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = RwGuarded, .member = .read }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = RwGuarded, .member = .write }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = RwGuarded, .member = .readUncancelable }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = RwGuarded, .member = .writeUncancelable }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = RwGuarded, .member = .tryRead }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = RwGuarded, .member = .tryWrite }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = SpinRwGuarded, .member = .read }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = SpinRwGuarded, .member = .tryRead }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = SpinRwGuarded, .member = .write }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
        .{ .rule = .A021, .decl = .{ .generic = SpinRwGuarded, .member = .tryWrite }, .with = .{ .generic = Order, .member = .Ordered }, .why = "an unranked acquisition: Order's ordered lock checks the rank" },
    },
};

// The tests run in this module, so test support that links aegis (shakedown)
// takes this copy and the test binary holds one aegis.
test {
    _ = @import("tests.zig");
}

test "lint_rules names declarations that are there" {
    _ = lint_rules;
    // A field entry names its field by name: each is one its type has.
    inline for (lint_rules.replaces) |entry| {
        if (@hasField(@TypeOf(entry), "field")) try std.testing.expect(@hasField(entry.field.type, @tagName(entry.field.name)));
    }
}

test "lint_rules names every read std.posix declares as an input source" {
    // std.posix is no banned namespace: its functions are mostly a descriptor's control. Each of its reads is an
    // A009 entry; one a new Zig adds fails here until it is named.
    @setEvalBranchQuota(100_000);
    inline for (@typeInfo(std.posix).@"struct".decl_names) |name| {
        const read = comptime std.ascii.isLower(name[0]) and (std.mem.startsWith(u8, name, "read") or std.mem.startsWith(u8, name, "pread") or std.mem.startsWith(u8, name, "recv"));
        if (read) {
            const function = @field(std.posix, name);
            const named = comptime for (lint_rules.replaces) |entry| {
                if (@hasField(@TypeOf(entry), "decl") and @TypeOf(entry.decl) == @TypeOf(function) and entry.decl == function) break true;
            } else false;
            try std.testing.expect(named);
        }
    }
}
