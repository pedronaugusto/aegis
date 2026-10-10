# Design

Aegis supplies explicit safety types for any Zig project. Runtime code depends only on std. Shakedown is test-only; preflight owns the build and CI gate. Modules import representation kernels downward, never consumers or tooling. Numeric values are copyable; secrets and guards have one semantic owner. Zig copying, reflection and escaped pointers remain caller bypasses, so these types do not claim compiler-enforced linearity or a borrow checker.

## Secrets and ownership

`Secret(T)` holds a fixed pointer-free representation inline, including padding. Shape validation rejects pointers and aggregates declaring cleanup. Explicit exposure borrows storage; cleanup and transfer use unconditional volatile std erasure over the entire representation in all modes. Transfer requires uninitialized, disjoint destination storage. Never read consumed storage as T. Caller temporaries, displaced values and escaped copies require their own authorized wipes.

`SecretBytes` stores exactly allocator, full allocation slice and live length. Its layout matches the handwritten full-wipe owner. Initialization zeros full capacity. Adoption validates length before transfer and accepts undefined slack without reading it; the caller supplies a genuine exclusive allocation with allocator-compatible byte alignment. Exposure borrows only the live prefix.

Shrinking securely erases the removed tail; growth zeros newly live bytes. Replacement rejects over-capacity input and any backing-storage overlap before mutation, wipes displaced live data and copies disjoint input. Reserve explicitly allocates, zeros new capacity, copies live bytes, securely erases the entire old capacity, frees and then publishes the replacement. It never resizes/remaps implicitly. OOM preserves ownership, content and existing borrows; successful reserve ends old borrows. Move transfers the descriptor without allocation or backing-byte copies and consumes its source. Both descriptors remain outside backing storage.

Cleanup wipes full capacity before rawFree with the exact extent and alignment, so a lawful pre-free observing allocator sees erased bytes before Debug allocator poison. Consumed descriptors are invalidated without reading them again. Formatting fails before writing. Errors use explicit defer/errdefer cleanup; panic, abort and process death provide no automatic cleanup. Wiping does not promise to erase older compiler copies, registers, paging or core dumps.

Costs are O(capacity) initialization/cleanup, O(removed tail) shrink, O(new live bytes) growth, O(old live + new live) replacement, O(new capacity + live + old capacity) reserve and constant-size descriptor transfer. There are no hidden backing copies, reference counts or extra release fields.

## Guarded data

`Guarded(T)` keeps data beside an acquire/release spin lock. Published owners have stable addresses. Acquire produces an explicit borrowed guard; defer its cleanup immediately. Critical sections are bounded and contain no blocking, yielding, recursive acquisition or arbitrary callbacks. Acquisition is noncancelable and has no fairness guarantee. The consumer owns data cleanup, reclamation and escaped-pointer lifetime. Locks remain in release builds.

The acquire is one swap with acquire ordering when the lock is free, which is the cost of a hand-written lock; a weak compare-and-swap loop measured about 10% dearer uncontended. A waiter that loses spins on a plain load until the lock reads free and swaps again, since a bare swap loop rewrites the held lock's cache line and measured two to five times slower with four to eight contenders. `tryAcquire` is one swap and never waits. `acquireYielding(io)` is for an owner whose holder may not be running, as on a cooperative Io: after a bounded spin each failed attempt sleeps through Io, so the holder runs. It returns Canceled before granting anything and leaves the lock to its holder, or, as `acquireYieldingUncancelable` for a cleanup path, blocks cancellation for the wait; the lock word carries no waiter state, so release stays a plain store and pays nothing for waiters. `teardown` on `Guarded`, `BlockingGuarded` and `RwGuarded` returns the data of a sole owner without taking the lock, so a deinit needs no Io; Debug and ReleaseSafe assert the lock is free, and the owner is not used again. A type declares `pub const interior_lock = true` when all of its mutation is behind its own lock; the guards do, and shared owners hand such a type out mutable.

## Io guards, publication and logical tasks

BlockingGuarded keeps exactly std.Io.Mutex plus T. Guard stores only an owner pointer; Io is passed per call. Cancellation grants no guard. RwGuarded preserves std.Io.RwLock's semantics and adds an atomic admission counter plus a finite limit, checked before either packed std reader/writer count can overflow. All read/write/try/uncancelable paths include admission; failed acquisition deregisters. Total admission never exceeds the smaller packed counter ceiling. Guards are one pointer. No fairness, recursion, upgrade/downgrade, transfer between logical tasks or recursive constness of pointees is promised.

Condition uses an intrusive stack waiter list, count, limit, permanent owner association and registry Io mutex. Register while the associated owner mutex is held, then release the owner. Each stack waiter has a monotonic notification word and stays in the registry until its return path deregisters under the registry lock. Signal/broadcast cannot retain a departed stack pointer. Wait loops use one absolute deadline; a spurious wake cannot extend it. Cancellation wins a raced signal, removing the waiter and forwarding its unused notification. Every return reacquires the owner uncancelably. Caps and association checks remain in all modes. Registry operations allocate nothing. List admission is LIFO without fairness/starvation bounds. Direct kernel fixtures use the same necessary registry policy, separately comparing guard access against direct associated-mutex operations.

Once holds empty/running/ready atomic publication state, an election mutex, bounded Condition registry and stable T storage. Election releases the internal lock before the callback. Callback receives the destination address and owns cleanup of every partial acquisition on failure; no by-value owner copy follows success. Error/cancellation resets empty and broadcasts; a canceled waiter cannot cancel the initializer. Completed initialization commits ready uncancelably with release ordering; get acquires before borrowing. Teardown requires join/drain and no readers. Static cleanup runs once only for ready storage, without a publication lock, and is infallible/nonblocking. There is no reset, reload or abort recovery.

Lazy is Once for a leaf. Its initializer is `fn (context, *T)` returning void or an error union of void and receives no Io, so it can neither wait nor reach another Lazy, and `getOrInit` needs no InitContext. The initializer runs under the election mutex with the empty/ready state published by release store afterwards, so there is no running state, no Condition and no waiter cap; a concurrent caller blocks uncancelably for the initializer's bounded time. The error set returned is the initializer's alone. Failure leaves the value empty for the next caller. A `T` declaring `interior_lock` is handed out as `*T`, any other as `*const T`. Mixing Lazy and Once on one storage is not possible: they are separate types.

Shared is counted ownership of one allocated `T`: a block of atomic count, allocator and value, and a one-pointer handle. `retain` adds with monotonic ordering and fails stop before the count can wrap; `release` subtracts with release ordering, and the last one acquires, runs the static cleanup and frees the block. Cleanup runs on whichever task releases last and is infallible and nonblocking. `createFrom` moves the payload by `moveInto` after the allocation succeeds, so an allocation error leaves the source with the caller. Debug adds a live flag to each handle to diagnose a handle released twice or used after release; copying a handle with `=` instead of `retain` is a caller bug no mode detects. The handout follows `interior_lock` as in Lazy.

An explicit InitContext accompanies getOrInit in addition to the initializer's arbitrary context. This extra task capability is necessary to diagnose recursion on a migrating runtime without storing Io or using threadlocal state. Its bounded 32-entry initializer stack exists only in Debug. Caller carries one context per logical task and never shares it with simultaneous execution.

Order compiles a strict partial rank relation, rejects cycles and checks all actual held owner identities before base acquisition in Debug. Its 32-entry context belongs to a logical task, and overflow diagnoses rather than dropping checks. Rank remains reserved during Condition suspension, which rejects further acquisitions in that context. Release contexts are zero-sized; ordered owners/guards match the base representation. Confined is a separate single-owner policy: caller-issued unique logical-task identities are checked on access and handoff in Debug and ReleaseSafe. Fast/small payload layout and operations equal bare T. Caller ends borrows and supplies external synchronization for quiescent handoff. No kernel can prevent caller reflection, raw alias races or forged/reused task identities.

## Bounded storage and static owners

Array and Buffer keep an initialized prefix; Queue/Ring and QueueBuffer/RingBuffer keep only live FIFO cursor entries. Arbitrary nonzero ring capacity uses subtraction before adding a cursor, so cursor arithmetic cannot overflow. Full never overwrites except the explicit overwrite operation, which returns displaced ownership. Dynamic forms accept caller-backed storage or explicit allocated capacity and finite maximum. Reserve allocates before moving; OOM leaves all owners/cursors/borrows valid. Successful reserve moves only initialized entries and invalidates container borrows. Entries declaring moveInto transfer through that explicit capability, preserving bound Owned identities and secret transfer contracts; other entries use caller-disciplined assignment. Cleanup is static, infallible and nonblocking; no hidden destructor, allocator growth or concurrency promise exists.

Finite Limit and externally synchronized Budget never interpret zero as unlimited. `Limit.exceeds` is the boolean form of `check`: true only above the maximum. Checked admission uses remaining capacity before addition, preventing overflow in all modes. Reservations store a borrowed budget pointer plus amount, release once or explicitly move, and must not outlive the budget. Underflow is fail-stop in every mode. Debug tracks live tokens; ordinary copies can evade checks and caller misuse is not linearity proof. The admitting operation performs transactional rollback across multiple budgets and retains the reservation until admitted work is finally reaped.

Owned stores T plus Debug-only live/address witnesses. Binding on first use diagnoses supported movement/copies after binding; moveInto resets the destination's witness and consumes the source. take transfers into explicit uninitialized storage. Payloads declaring moveInto use that capability recursively, retaining inline-secret source erasure and SecretBytes descriptor/full-capacity ownership; ordinary payloads use disciplined assignment. `initFrom` takes the payload from a source by `moveInto` where the payload declares one and consumes the source; `init` copies, which for a Budget reservation would leave the source able to release the same charge again. Static cleanup has no deleter vtable, stored Io, fallible/blocking finish or automatic unwind. Release stores only T and one required cleanup call. MustUse tracks discharge only in Debug; take or a static documented acknowledgment discharges a non-resource result, and explicit deinit diagnoses otherwise. Omitted deinit, pre-binding copies and reflection remain unsupported gaps. Resource-bearing outcomes require Owned or an explicit combined consumer owner.

## Scalars and foreign boundaries

IDs, NonZero, Counter, Count, Bytes, Bits, Duration, Instant and Ranged use non-exhaustive enum(Repr) storage. Tags, scales and bounds occupy no bytes; scalar size/alignment matches Repr. A one-field extern struct was rejected because equal layout does not imply the integer calling convention: 32-bit x86 can return structs through memory. The C ABI guarantee covers signed/unsigned 8–64-bit and usize/isize representations on every configured target. 128-bit reprs remain usable Zig types with the same factory, arithmetic and encoding APIs, but are NOT promised C ABI types. MSVC has no 128-bit integer and Zig 0.17 lowers enum(u128)/enum(i128) returns differently from raw integers on x86-64 Windows. Only those widths are excluded from the ABI fixture; no target is excluded.

Identity import is explicit and does not establish authenticity or uniqueness. NonZero rejects zero. Counter exhausts without wrapping or mutating on failure and requires external serialization. Counts and durations use checked arithmetic. Every unit scalar has `eql` and `compare` like IDs, and Counter reads its last issued ID, null before the first. The std adapters take what the representation and unit allow: the range of a std i96 nanosecond value is compared with the target at compile time, and a conversion that always fits and needs no rounding carries no error and no range check, while one that can lose data keeps its check and has only the errors it can have. A narrowing is never made free. Conversions check scaling, sign and range in every mode; down rounds toward negative infinity, up toward positive infinity, exact rejects remainders. Instants combine only with matching clock/domain durations; changing clocks requires a sampled correspondence. Wait boundaries retain std.Io.Timeout. Endian encoding reads/writes exact repr bytes, never copies ABI storage. Foreign callers honor nonzero/range contracts or validate returns through checked import.

Checked and Saturating retain arbitrary nonzero integer widths. Division by zero and invalid shifts fail even in saturating operations. Signed division truncates toward zero; min/-1 remainder is zero. Ranged checks inclusive bounds. Integer casts reject sign/narrowing loss. Arithmetic and conversion checks remain enabled in release modes; there is no allocation or indirect dispatch in scalar kernels.

## Executable contracts and evidence

Invariant, pre and post fail-stop with static public messages in every build. Peer errors return named errors. debugCheck omits its predicate in release modes; maybe is not a truth assertion and test-only counting uses caller-owned storage. Fail-stop does not unwind cleanup.

The ABI test calls separately compiled raw-integer exports through both typed and raw declarations, using two runtime arguments and consuming returns. It checks extern-record size/alignment/offsets and raw field access. All configured targets plus 32-bit x86 and wasm are required; cross codegen is distinguished from separately linked native execution. Independent C exports compile for every ABI profile and the native checks link and execute both raw-Zig and C translation units. Matching typed prototypes are never interoperability proof. Zig-only 128-bit factory/extreme/encoding tests remain active.

Required SecretBytes checks observe valid allocations before free, cover undefined/nonzero slack, all overlap directions, shrink/regrow, OOM and borrow preservation, NoResize allocation failures, generated live-set properties, explicit move rejection in every execution mode and portable profiles. Paired enclosing release consumers require equal symbol sizes/instructions and volatile full-capacity erasure, including adopted dead-use and error cleanup. Deliberately broken wipes must be rejected by the observer; production is never changed to that mutant. Secret formatting has an intended-reason compile rejection.

Own benchmarks live in bench and CI compiles them without timing gates. Correctness and deterministic checks gate landing. Timing is paired and interleaved with ratios and spread; performance misses remain open objectives. The package contains its implementation, tests, benchmarks and architecture; measurement rows and drivers live in private trials. Hosted CI outcomes certify exact source commits. A6/A7 contracts require meaningful simulated cancel/wake/race traces and native publication/contention. Pure value profiles compile on 32-bit x86, wasm and freestanding aarch64; host Io execution is required separately on Linux, macOS and Windows. No generic bare-lock benchmark substitutes for equally bounded admission/publication policy. Confined identity checks are necessary safety in ReleaseSafe, not abstraction overhead. All paired fixtures compare that same safety work.

Cloak/family adoption and the rest of the planned safety catalogue are later work.

## Choice kernels

`aegis.secret` supplies a copyable one-bit `Choice`. The representation occupies
one byte and contains one decision bit. `and`, `or`, `xor`, and `not` produce
choices. `fromBit(u8)` imports a **public** bit and rejects values above one in
every build mode. Internal kernels establish the 0/1 invariant without a
secret-dependent validity branch.

`equal(N, a, b)` compares fixed byte arrays. `equalBytes(a, b)` returns
`CompareError.LengthMismatch` for unequal **public** lengths, including empty
against nonempty. It reads every byte of the public common length. Length is
not concealed. `compareUnsigned(N, endian, a, b)` returns `OrderChoices` with
exactly one of `lt`, `eq`, `gt` set; endian is public and both endian orders are
supported. Zero-byte integers compare equal.

A zero choice selects `a`; one selects `b`. `selectInt(T, a, b)` accepts signed
and unsigned 8/16/32/64-bit integers. Other integer widths, floating point,
aggregates, and secret indexing are unsupported. `selectBytes(N, out, a, b)`
accepts disjoint output or output exactly equal to either source. Partial
output/source overlap returns `SelectError.PartialOverlap` before mutation.
Sources may overlap each other. Both source bytes load before each result
store, including exact aliases. All source bytes must be initialized and live.
Addresses, extents and lengths are public. Bounds and extent validation stay
enabled in every mode.

`declassify(comptime reason)` explicitly releases a bool. Its trimmed reason
must be nonempty. A completed verdict may then control a branch. Formatting
with `{f}` is a compile error. Explicit casts, field access and generic
representation inspection can bypass these conventions in Zig; the type is
not a compiler information-flow proof. Neither select input may perform
secret-dependent work before entering the kernel.

### Compiler boundary

This batch stages one dispatch: Zig **0.17.0 LLVM**, `-mcpu=baseline`, ordinary
unmodified baseline feature sets. No target-specific hardware dispatch is
performed. The enabled profiles are:

| Target | CPU |
|---|---|
| x86_64-linux-gnu / x86_64-linux-musl | baseline x86_64 |
| aarch64-linux-gnu | generic |
| x86_64-windows-gnu / aarch64-windows-gnu | baseline x86_64 / generic |
| x86_64-macos / aarch64-macos | baseline x86_64 / apple_m1 |

Debug, ReleaseSafe, ReleaseFast and ReleaseSmall are checked. Root
`std_options.side_channels_mitigations` may be `basic`, `medium` (default), or
`full`; `none` is rejected. Other compiler versions/backends, custom CPU models
or features, 32-bit, wasm, freestanding, and unlisted OS/ABI profiles fail when
a kernel is instantiated. Other aegis modules remain usable on their own
supported profiles. Importing this lazy module alone does not enable a kernel.
Consumers must retain their own caller audit after composition, root-option,
compiler, flag or CPU changes.

### Kernels and checks

Equality uses volatile byte loads and a full-length XOR reduction. Order
accumulates masked first-difference decisions without early exit. Select uses
opaque full-register masks and complements; both inputs participate. A tied
volatile empty inline assembly register blocks LLVM's mask reasoning. This is
a compiler barrier, not a hardware timing instruction or a universal
constant-time guarantee. The equivalent handwritten baseline retains the same
barriers, volatile loads, checks and decision representation.

`zig build check-choices` inspects enclosing optimized callers across every
listed profile and root mitigation option. The integer caller catalogue includes
every signed and unsigned supported width. Release modes require identical
normalized emitted instructions to the equivalent baseline. Debug retains
runtime safety and runs a stack-aware SSA regression detector. The detector
checks secret-derived branches, select conditions and address indices; three
deliberately unsafe compiled controls (branch, index and unresolved helper call) must be caught in each profile. It is a
regression check for these fixtures, not a sound whole-program analyzer.
`zig build check-choices-negative` verifies unsupported profiles/types and
explicit disclosure/format contracts. Native correctness tests live beside
the package's tests; `zig build bench` owns the manual paired measurements.
CI compiles benchmarks and does not gate on timing.

Fixtures preserve the c1 Montgomery limb count, fixed-window table scan and
completed offline padding-verdict shapes. They prove aegis composition at
those seams, not the entire curve, modular arithmetic or CBC cipher. The MAC/
Finished fixture describes a future caller shape. No cloak source is changed
and no consumer adoption is claimed. Choice does not own or erase its inputs;
secret owners retain their cleanup obligations. It cannot guarantee erasure
of historical copies, registers or caller-owned temporaries.

Hardware constant-time assurance remains unestablished. Native x86 timing, class-resolved cache misses, power, EM, cross-thread leakage and arbitrary whole-program behavior remain outside this checked compiler boundary. Observed secret-class timing differences remain unresolved; passing caller checks does not explain those differences or prove data-independent physical execution.

## Generational storage and checked input

The handle owner has exclusive mutation and requires external synchronization. Caller-provided namespaces must be globally unique in the intended lifetime; Domain externally serializes its monotonically increasing instance counter and fails on exhaustion. Persisted instances require caller-managed issuer continuity. Keys contain namespace, instance, usize position and u64 generation; they are liveness witnesses, never authority tokens. Every lookup/remove validates all fields, range and occupancy in all modes. This deliberately follows the handle semantic contract rather than treating generation validation as a removable diagnostic. Public field access can bypass the API.

Fixed pools own no allocation and keep live slot addresses stable until removal, reuse or cleanup. SlotMap owns its allocator and slot allocation. Reserve allocates before touching live values; failure preserves keys, values and borrows. Success explicitly moves live values, preserves generations and retires metadata, and ends every old value borrow. Insert grows geometrically within its explicit capacity ceiling. A generation at its maximum retires a removed slot permanently; clear never resets generations. The internal lowered-width kernel exhausts every slot in tests. Pool clear cleans in ascending slot order. No mutation cleanup may reenter the owner.

DenseSlotMap has a primary generational position table plus contiguous values and reverse full keys. Reserve acquires both new buffers and primary capacity before moving any value. Swap removal repairs the moved value's primary link and invalidates affected borrows. Reverse dense order determines clear cleanup. SecondaryMap hashes the complete primary key into an association position; its own values relocate through explicit moves. Resolving always checks the primary liveness witness. Stale associations still own values and support explicit removal/pruning; no primary callback implicitly owns their cleanup. Its free list gives amortized constant-time insertion; prune scans capacity.

Moves call a value's explicit moveInto when available, otherwise transfer the representation and invalidate the source. Destinations must be uninitialized and disjoint. Admission, allocation and alias rejection preserve the source. No container invokes automatic destruction or stores Io. Cleanup receives an already detached value. Borrowed items and iterators expire at the documented structural mutation; a stable key does not imply a stable pointer.

Untrusted adapts nonowning values to a parser's exact declared error union and distinct refined return type. Top-level pointers/slices become const views, including their original sentinel/alignment attributes. Structs that declare cleanup/transfer, and aggregates containing them, cannot implicitly adapt by value. Pointers can explicitly borrow owners. Const access does not freeze mutable aliases. Parsed borrowed views expire with their source; source mutation can alter them. Parsing proves only the consumer parser's checks, never authentication or authority. Canceled/error paths remain the parser's cleanup responsibility.

Error contexts have only inline frames, length and truncation. A copied context has no internal self-pointer. The consumer explicitly admits closed public frame structs; recursively accepted scalar fields cannot identify sensitive meaning. Known owner/secret formatting or transfer shapes, pointers, slices, unknown aggregates and user formatters are rejected. PublicText is the sole admitted text representation: literals or explicitly classified runtime bytes are escaped into fixed storage, stopping before a partial escape and preserving truncation. Formatting invokes only the library's closed formatter and propagates Writer errors without consuming frames or replacing the primary cause. Default crypto frames contain only public enums and numeric facts.

Required key validation, retirement, resource ceilings, parser checks and bounded escaping stay enabled in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall. The implementation adds no optional address/cleanup diagnostics to these values. This does not remove required semantic metadata. This batch is library implementation and fixture proof; no consumer adoption or new protocol parser is claimed.

The A8/A9 deterministic gate compiles ten target profiles in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall. The assembly gate compares the mode-matrix cost profiles (Fast and Small) on x86-64/aarch64 against plain handwritten storage with identical key checks, nonwrapping retirement, alias rejection, source consumption and distinct error outcomes. Consumer fixtures also compare typed positions, parser checks, enabled/optional context writes and dense iteration. Negative compilation checks cross-brand/raw-to-refined misuse, owning by-value input, non-refining or anyerror parsers, unsafe frames, Secret/Choice capture and unclassified runtime text. The native cases observe owning cleanup at every allocation failure on NoResize and preserve borrows on failed reserve. Published own.Owned fixtures bind before insertion, grow through explicit moves and detach for cleanup; no A7 implementation is duplicated. The published cloak c1 DER envelope fixture retains its canonical enclosing lengths and borrowed views; it is not certificate grammar, authentication or consumer adoption.

## Typestate machines

A machine is a topology over two exhaustive enums: one deterministic edge per state and event, an initial state and any number of terminal states. The specification is validated when the machine is analyzed, so a mistake is a compile error naming the state and event: a duplicate edge, a terminal state with an edge out, a non-terminal state with no way out, a state no edge reaches from the initial one, a terminal initial state, a terminal state listed twice. Events need not all be used: a machine legitimately rejects part of a peer's alphabet in every state. Machines that differ by role or version declare their own state enums, which also keeps their states from mixing.

The transition table is a comptime array of one cell per state and event, a state's position or one past the last state, in whole bytes. `next` is one load from it with no branch on the state or the event, and a dense enum is its own position; an enum with explicit values maps through a comptime scan. The load turns off Zig's bounds and range checks, because both operands are valid enum values and every cell comes from the validated table; Debug keeps them. The idiomatic hand-written nested switch compiles to a larger and, on a random event stream, slower function, so the paired gate compares against a hand-written table with the same cell width and sentinel, and reports the switch as a row that the table may beat but must not exceed.

A static stage, `At(state, Payload)`, holds the payload and nothing else outside Debug. Debug adds one flag, set when the payload has moved on, which makes a later use panic. Zig copies freely, so the flag detects a stale binding and nothing more. `transition` moves the payload with its `moveInto` when it has one, into storage apart from the source, and consumes the source; `transitionWith` runs a preparation that writes a payload of another type, and is the only fallible step. A failed preparation leaves the source staged and the destination unwritten, so there is no half-moved state to reason about. A payload leaves a stage only from a terminal one, which keeps an early exit an edge in the specification. The destination of an edge back to the same stage must be a second stage; Debug and ReleaseSafe stop a transition into its own source.

The runtime machine is a payload beside a state and the same table. `step` returns the edge taken, or `error.IllegalEvent` with the state unchanged, in every build mode: an undeclared event comes from the peer and is not a programmer error. `plan` and `commit` split the step for work that can fail or suspend. A commit after the machine has moved to another state is `error.Stale`, since a late completion is an ordinary race. A plan is a state and an event, so a machine that returned to the same state accepts it again; a consumer that needs a plan to be unique carries its own token. A forged edge, one the table does not declare, is a programmer error and stops the program. The table does not carry actions or callbacks: the caller reads the edge and does the work, and so nothing runs under a hidden lock. Each step is a constant number of instructions, so the work a step may do is whatever the caller's own budget allows.

No type tracks whether the peer's event is genuine, ordered or authorized, whether a transcript or nonce is right, or whether two threads drive one machine. Enum states are no thread-safety claim, and one driver owns a runtime machine.

## Scope lifetimes

A scope is a lifetime the creator ends: a request, a connection, an arena. Zig cannot prove that a reference does not outlive it, so aegis catches the use when it happens. The creator keeps a table of slots, each holding a generation, and a scope is a slot and the generation it was opened at. A reference carries a pointer to the slot and that generation, and checking is one load and one compare. The slots live in the creator's storage and not in the scope's memory because the check must read live metadata after the scope's memory is gone. Ending a scope bumps the slot's generation, so every reference made in it fails its check from then on, even once the slot hosts a new scope with its own generation. A slot whose generation reaches the largest value retires and never opens another scope, so a generation never repeats; with 64 bits that takes longer than a process lives, and a table with every slot retired reports `Exhausted`.

The brand is the type that names the kind of scope. It is part of the reference's type, so a reference from one kind of scope cannot be passed where another is expected, and moving it takes `reborrow`, which checks the source and binds it to the new scope. That is a statement in the code that the memory now lives under the new scope, which the compiler cannot check and the reader can see.

The checks follow the mode matrix: Zig's runtime safety. Debug and ReleaseSafe check; ReleaseFast and ReleaseSmall keep no table, no generation and no check, and a reference is exactly the pointer it wraps. The record is a 64-bit atomic read and write without ordering where the target has them, so using a reference from another thread is well defined and means something only when the caller's own synchronization orders the end of the scope against the use; narrower targets keep a plain integer. The table is not thread-safe: opening and ending belong to one owner.

A check that stops the program is the right answer for a bug, and the wrong one for an event: a completion that arrives after its request ended is expected, and a handle, whose check is required in every build mode, is what to hold there. Scopes catch the use that should never happen; they do not catch a raw pointer taken out of `get` and kept, a reference that is never used, or memory the creator frees without ending the scope.

## Namespace build graph

Each implemented namespace has its own build module alongside aegis, including the published sync, bounded and own APIs. Root exports are aliases of those same module declarations, so mixing root and standalone imports cannot create a second Secret, guard, ID or key type. A private scalar kernel is shared by int, id and units. Gantry checks the base (id/units/int/assert and representation kernel), secret (owners and constant-time values, depending only downward), then synchronization/handles/boundaries, bounded and ownership, typestate, lifetimes, then root. Published consumers stop build setup before lazy tooling/test dependencies are requested. The CI mixed-import fixture asserts declaration identity; CLI compiler fixtures use one explicit projection of the same graph.

Secret's existing inline/byte/value parts live under secret/ beside secret.zig. This avoids the Secret.zig/secret.zig collision on case-insensitive hosts and gives the standalone secret module one source owner. v0 root aliases, signatures and runtime kernels remain the same. Test discovery stays in src/tests.zig; the internal lowered-generation fixture is a separate CI executable, with no test-only production API.
