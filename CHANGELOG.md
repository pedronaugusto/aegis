# Changelog

All notable changes are documented here, following Keep a Changelog 1.1.0.

## [Unreleased]

### Added

- `Shared.createWith(gpa, context, init_fn)`: a block whose value `init_fn(context, &value)` builds in place before any handle exists, so a value that must not be copied, such as key material, is never anywhere but in the block. On `init_fn`'s error the whole block is erased and then freed, without `cleanup`; releasing what `init_fn` acquired before it failed stays `init_fn`'s (its `errdefer`). `CreateWithError(init_fn)` is its error set; an `init_fn` that cannot fail adds none. (cloak's `PrivateKey` built its key on the stack and moved it in with `createFrom`.)

## [0.2.1] - 2026-10-27

### Added

- `units.Instant.floor(tick)`: the start of the tick an instant falls in, ticks counted from the clock's zero, rounded toward negative infinity and saturating at the representation's minimum; `tick` is positive. For bucketing time by a span that is not a unit, such as a filesystem's two-second tick.
- `units.Duration.divTrunc(count)` and `divFloor(count)`: a part of a span, such as a quarter of a wait, rounded toward zero or negative infinity. `DivError` is `DivisionByZero`, plus `Overflow` on a signed representation for its minimum by -1. (cloak's DTLS timers: RFC 9147's ACK timer is a quarter of the retransmission wait.)

### Fixed

- `own.readFile` and `readFileSentinel` read a file to its end and judge the limit by what they read. They refused a pseudo-file by the length it states: sysfs states 4096 and procfs 0 whatever they hold, so a 256-byte limit refused a 16-byte sysfs attribute as `StreamTooLong` before reading it (preflight 0.18's VM guest reading `/sys/class/virtio-ports/*/name`, which made the family's riscv64 nightly leg red; glyph's finding). The stated length is now only the first allocation's size. It is still read first, with its error returned, so a cancel there is still `Canceled`, and the reader never asks for it again. A file longer than the limit is `StreamTooLong` once the byte past the limit is read, no longer before anything is allocated, and bytes appended during the read are read.
- `own.Owned` and `own.OwnedIo` bind their address once: Debug's witness stored the owner's address on every `borrow`, a data race when several tasks borrow one owner read-only at once (review-io's finding, chronicle under ThreadSanitizer). The first use binds it with one compare-and-swap, and every use after only reads it. A native test borrows one owner from 8 tasks at once, its first bind among them, and joins `test-native-races` (`-Dthread-sanitizer=true`), which reported the race before.

## [0.2.0] - 2026-10-25

### Breaking

- `SecretBytes` holds no allocator: it is the allocation and its live length, 24 bytes where it was 40, as std's unmanaged containers are. The allocator that made it is passed where it allocates or frees: `init(gpa, capacity)` as before, `reserve(gpa, capacity)`, `appendSlice(gpa, bytes)`, `Writer.init(&owner, gpa)` and `deinit(gpa)`; `adopt(allocation, live_len)` no longer takes one. `SecretBytes.empty` is an owner of no allocation, to grow from, so a field that may hold none needs no optional. Before: `var key = try SecretBytes.init(gpa, 32); defer key.deinit(); try key.reserve(64);`. After: `var key = try SecretBytes.init(gpa, 32); defer key.deinit(gpa); try key.reserve(gpa, 64);`. (cloak's connection keeps its record and handshake-message buffers as owners: with an allocator in each, beside the one the connection holds, the idle client passed its 2 KiB budget.)

## [0.1.18] - 2026-10-25

### Added

- `own.readFile(io, dir, sub_path, gpa, limit)` and `own.readFileSentinel(..., sentinel)` (source text a parser reads to its end): a whole file's bytes, at most `limit` (`units.Bytes(u64)`, which the caller must give), the caller owning them. It reads the file's length first and returns its error, so a cancel that lands there is `Canceled`; std 0.17's `Dir.readFileAlloc` takes a failed length as a guess and reads on, so that cancel is lost. A file longer than the limit is `StreamTooLong` before anything is allocated, and the read is as long as the length said (bytes appended after it are not read). Proved under shakedown's `everyFault` with every cancel, error, short read and allocation failure. (relic-c's finding; preflight's default policy names it as std's replacement.)
- aegis's `build.zig` gives a build script `own` (`@import("aegis").own.readFile`), which takes no package module: the same spelling as in a program. Zig analyzes what a build script uses, so a build runner compiles the read and what it needs, not aegis. (preflight's build helpers read their files through it.)
- `own.Owned.move` and `own.OwnedIo.move`: a used owner handed on by value, consumed as `moveInto` consumes it, the result binding at its first use, so a function that opens and uses a resource can return its owner. `own.Lent(T)` and `lend()`: a copy of a by-value payload (a file, a directory) with no `deinit`, what an accessor hands out of a handle its owner closes. Both refuse a payload that declares `moveInto`. (relic's repository moves its directories from discovery into its state, and its accessors hand them out.)
- `SecretBytes.appendSlice` and `SecretBytes.Writer`: secret text built a piece at a time, grown only through `reserve`, which erases the storage it leaves. The writer is a `std.Io.Writer` whose buffer is the allocation itself, so what is printed is held nowhere else; `flush` publishes it as the live prefix, and `err` names the allocation failure behind `WriteFailed`. Overlapping input is refused as `replace` refuses it. (relic built such text in a `std.ArrayList` and wiped it by hand, where each growth left an unwiped copy.)
- `bounded.Budget.settled()`, a Debug witness: whether every reservation the budget gave has been released or consumed (a move hands one on, still open). A reservation dropped without either leaves it false, which a test asserts after the work it charged; a build without diagnostics keeps no count and answers true. The count is a word in Debug, so a budget is larger there than in release builds, as its reservation already was.
- Each scalar says what it is in one declaration, `aegis_scalar`: its `contract` (the declaration's version, 1), its `kind` (`.ranged`, `.duration`, …), its `representation`, and its bounds, unit, clock or domain. Generic code recognizes aegis's scalars by it and builds them only through their own checked functions, as README's contract 1 names them, refusing a contract it does not know by its number. Rebuilding a type from its published parameters and comparing, which README recommended, refuses a type made by another copy of aegis: a plain `zig build` whose dependencies pin two aegis versions builds two, so ensign refused bay's `int.Ranged` as a non-exhaustive enum, while the declaration reads the same in every copy.

## [0.1.17] - 2026-10-24

### Fixed

- The hosted gate's `contracts-published` job ran the suite in each release mode outside preflight's runner, so with no watchdog or timing record, and preflight refused it (the nightly's red since 0.1.15). `test-release` is gone: the release tier runs the whole suite in ReleaseSafe and ReleaseFast under the runner, and ReleaseSmall, which keeps no check ReleaseFast drops, is held by the mode matrix.

## [0.1.16] - 2026-10-22

### Added

- The catalogue names, for every module, the danger rule of glint's aegis pack that requires it at its danger sites, or the required module built on it, and refuses a module with neither (aegis's design §7, criterion 4); README's table shows it. `Order` is the answer to A021, a function holding two aegis guards at once without both ranked.

## [0.1.15] - 2026-10-22

### Added

- A release contract for every module in the README: what it is in ReleaseFast and ReleaseSmall, what it keeps checking in every build and what Debug and ReleaseSafe add, each row held by the gate (layouts against hand-written storage on the portable profiles, paired kernels, a mode matrix of every deliberate violation, the whole suite in each release mode). An example of every module in `examples/`, which the build runs.

### Changed

- `secret.Timing.end` restores the mode only where `begin` set it, from what `begin` recorded, instead of asking a second time whether the processor has it: on AArch64 Linux a span is now the instructions of a hand-written one (it was 60 bytes larger).

## [0.1.14] - 2026-10-17

### Changed

- `scope.Ref`'s private pointer is the field `pointer`, no longer `ptr`: a slice's own member has that name, so a read of `x.ptr` in generic code could not be told from a reference's private state. Reach the pointer through `get` as before.

## [0.1.13] - 2026-10-17

### Added

- `Budget.Reservation.consume()`: ends a reservation with its amount kept as consumed work. A charge taken before an allocation is released if the allocation fails and consumed once it succeeds; before, a successful path could only drop the live reservation (strand's `Context.alloc`). glint's A003 reads it as the reservation's discharge.

## [0.1.12] - 2026-10-17

### Added

- `Guarded(T).Guard.handOff()` and `Guarded(T).Handoff`: the release of a held lock, handed to code that runs it past the holder's frame (a scheduler releasing a lock once the holder's task is parked), released once with `release()`. glint's A003 reads it as a declared transfer, where a guard's address through an erased callback context stayed undecided.

### Changed

- The docs say that a `Choice` is constant-time on the hardware only under `secret.Timing`: on AArch64 without DIT set, a comparison's time depends on its operands (cloak road A's finding).

## [0.1.11] - 2026-10-17

### Fixed

- `secret.Timing` compiles for every architecture again: 0.1.10's AArch64 instructions reached an unoptimized build's assembler on x86_64 (and any architecture without the mode), which refused `mrs`, so a Debug build of any program using `Timing` failed outside AArch64. They are now behind a compile-time check, and `zig build check-timing` (in the gate) builds `Timing`'s span as an object for x86_64, AArch64 and wasm32, Debug and ReleaseFast.

## [0.1.10] - 2026-10-17

### Fixed

- `secret.Timing` sets data-independent timing on AArch64 Linux too: it was decided at compile time from the target's features, so a baseline AArch64 build (Linux distributions' default) never set it on a processor that has it. Where the target does not say, `Timing.supported()` asks the kernel once (HWCAP_DIT); the mode is set only where the processor has it, since setting it on one without traps. `Timing.available` now says the build can set it, `supported()` that this processor does. cloak's timing campaign found std's X25519 timed apart by its secret on an Apple M3 without the mode.

## [0.1.9] - 2026-10-15

The change first tagged v0.2.0 the same day, released on the 0.1 line: it breaks no caller (only builds that failed to compile now compile), and a family resolves aegis within one line, so a new minor would have split every package that also reaches aegis through shakedown. v0.2.0 was withdrawn and its tag removed; 0.1.9 is the same tree.

### Changed

- `secret.Choice` and its kernels compile for every target, backend and CPU instead of failing outside the checked profiles: a build that relied on the compile error to keep unaudited lowering out asserts `secret.Choice.audited` instead.

### Added

- `secret.Choice.audited`: whether this build (compiler, backend, target, CPU model and features, mitigation level) is one whose lowering `zig build check-choices` inspects; `secret.audited_profiles` lists them.
- check-choices covers x86_64-linux-gnu at x86_64_v2/v3/v4, aarch64-linux-gnu at neoverse_n1/v2, aarch64-macos at apple_m2/m3/m4, x86_64 FreeBSD, OpenBSD, NetBSD and DragonFly, and wasm32-freestanding: 20 profiles, 240 builds.

## [0.1.8] - 2026-10-14

### Changed

- Pins preflight 0.5.4, shakedown 0.4.3.

## [0.1.7] - 2026-10-14

### Fixed

- The `secret.scrubStack` and `secret.scrubbed` tests measure the dead stack with instrumentation off: under ThreadSanitizer the hook each read calls ran in the bytes being read and erased the residue the control expects.

## [0.1.6] - 2026-10-13

### Added

- `secret.scrubStack(bytes)`: zeroes the stack below the caller after a secret computation returns, where the compiler's spills, saved registers and by-value copies of its callees lie and no owner can name them; `secret.stackReach(bytes, function, args)` measures how deep a call writes, to choose the depth with; `secret.scrubbed(bytes, function, args)` runs a secret computation in a frame of its own under `secret.Timing`, then scrubs.
- `secret.Timing`: data-independent timing for the span of a secret computation (`begin`, `end` in a `defer`, `active`). On AArch64 with FEAT_DIT it sets PSTATE.DIT, under which the architecture guarantees operand-independent timing of data-processing instructions and Apple's cores turn off the data memory-dependent prefetcher; elsewhere it does nothing.

## [0.1.5] - 2026-10-13

### Added

- `units.Duration.literal` and `units.Bytes.literal`: a value written in the text form and read at compile time, `.literal("250ms")` or `.literal("64KiB")`, for defaults and constants; text `parse` refuses is a compile error naming why.
- `bounded.Array.constItems`, the prefix through a `const` array or a copy of one, and `appendSlice` and `fromSlice`, which copy a slice in whole or fail with `Full` and change nothing, for a payload that is copied rather than moved: a value that owns a short string by value, such as a host name.

## [0.1.4] - 2026-10-13

### Added

- `units.Duration` and `units.Bytes` have a text form, the same for a command line, a configuration file and a log: `parse(text)` and `format` (`{f}`), exact both ways, with `ParseError` (`Malformed`, `Overflow`, `Inexact`) and `max_text_len`. A duration reads `30s`, `1m30s`, `250ms`, `1.5h` or `2d12h` and writes its nonzero components from days down; a size reads `4096`, `64MiB` or `1.5GB`, binary (`KiB`, powers of 1024) and decimal (`kB`, powers of 1000) units spelled exactly, and writes the largest unit that divides it. A value finer than the type holds is `Inexact` and one past the representation `Overflow`, never rounded.
- Each scalar publishes the parameters it was made from, so generic code can recognize it by rebuilding it: `Representation` on `int.Checked`, `Saturating` and `Ranged`, every unit and `id.Id`, `NonZero` and `Counter`; `minimum` and `maximum` on `Ranged`; `Scale` on `Duration`; `Domain` on `Counter`.
- `int.Ranged.literal(value)`: a value known at compile time, range-checked there, so a default or a constant is `.literal(8)` where `init` needs a `catch`.

## [0.1.3] - 2026-10-12

### Changed

- The benchmarks take shakedown from preflight, which adds the one the package declares, where their imports gave it a second time; the tests' module states that it is shakedown's aegis only while shakedown asks for aegis with the same target and mode.

## [0.1.2] - 2026-10-12

### Changed

- The tests run in aegis's own module, which bay gives shakedown as its aegis, where they built a second module from `src/root.zig` and bound shakedown to it.

## [0.1.1] - 2026-10-12

### Changed

- Pins preflight 0.3.4 and shakedown 0.2.5.

## [0.1.0] - 2026-10-11

### Added

- `int.narrow(Target, source) ?Target`: the one checked narrowing for generic code. It is null where `cast` fails with `Overflow` and the value where it fits, whatever the pair of integer types, where `cast` returns a value for a conversion that cannot fail and an error union otherwise.
- `SpinRwGuarded(T)`: the reader-writer form of `Guarded`, a spin lock with no Io for many readers or one writer (`read`, `write`, `tryRead`, `tryWrite`, `isHeld`, `teardown`). A waiting writer holds off new readers.
- `Guarded.acquireScheduling`: acquire for a section a few system calls long on OS threads with no `Io` to wait through (a reap, a fork gap). A contended waiter yields the thread between tries, where `acquire` pauses, so a holder that was descheduled can run.

### Breaking

- aegis is developed with [bay](https://github.com/pedronaugusto/bay): preflight and shakedown are dev dependencies, and the tests, examples, contract gates and benchmarks are the development build's (`bay test`, `bay contracts`). aegis ships with no dependencies; what a project that depends on it builds is unchanged.
- A conversion that cannot fail carries no error set and no range check. `int.cast`, `Count.convert`, `Bytes.convert`, `Bits.convert`, `Duration.convert`, `Instant.convert`, `Duration.fromIoDuration`, `Instant.fromTimestamp` and `Instant.fromIoTimestamp` return the value where every source value converts and keep exactly the errors that can occur otherwise, so `try` and `catch` on a conversion that cannot fail no longer compile. The decision is portable: `usize` and `isize` count as 32 bits as a target and 64 as a source, so `u32` into `usize` and `usize` into `u64` cannot fail and `u64` into `usize` can, on every target. `Bytes.ConvertError` and `Bits.ConvertError` are `int.CastError`.
- The `rounding` argument of `Duration.convert`, `Instant.convert`, `Duration.fromIoDuration`, `Instant.fromTimestamp` and `Instant.fromIoTimestamp` is comptime, so `.down` and `.up` carry no `Inexact`: only `.exact` can be inexact. A caller that chose its rounding at run time switches on it.
- aegis is one build module, `aegis`. The per-namespace modules (`aegis.int`, `aegis.id`, `aegis.units`, `aegis.assert`, `aegis.secret`, `aegis.sync`, `aegis.handle`, `aegis.input`, `aegis.err`, `aegis.bounded`, `aegis.own`, `aegis.state`, `aegis.scope`) are gone: import `aegis` and use the namespace, `@import("aegis").handle` in place of `@import("aegis.handle")`, and drop the `addImport` and `module("aegis.<namespace>")` lines. Zig compiles only what a program uses, so the split bought nothing at run time or in build time. The layers it protected (the base, then `secret`, which imports only the base, then the rest) are checked at file level by the lint instead.
- The std adapters of `units.Duration` and `units.Instant` (`toIoDuration`, `fromIoDuration`, `toIoTimestamp`, `fromIoTimestamp`) return what the representation and unit allow: a conversion that cannot fail returns its value with no error and no range check, so `try` on it no longer compiles, and one that can fail returns only the errors it can have. Their `*Error` declarations narrow to match, and are empty where the conversion cannot fail. A millisecond `i64` widens into std's nanoseconds, a nanosecond `i128` takes any std duration or timestamp, and a nanosecond `i64` still checks the narrowing.
- Replace A3 scalar extern structs with non-exhaustive enum(Repr) values; factory APIs and checks stay the same. Reflective field construction/access no longer applies.

### Changed

- The move rule (`moveInto` when a type declares it, else assignment) is one file in the base layer, `move.zig`, in place of five copies in `Shared`, `bounded`, `own`, the handle pools and the typestate stages. The handle pools keep their one difference, a copied source is set to `undefined`, as the named `intoPoisoning`.
- The lowered-generation retirement cases run as ordinary tests in every release mode instead of as a separately compiled fixture.

### Fixed

- `Guarded` acquires with one swap, as a hand-written lock does, instead of a weak compare-and-swap loop that cost about 10% more per uncontended acquire; a contended waiter spins on a plain load rather than rewriting the lock line. The paired assembly and timing parity fixtures now use the swap form.
- Unit scale conversions reduce their ratio once per distinct scale with a bounded remainder loop, so many conversions in one caller's inline loops no longer exhaust the comptime branch quota.
- Replace matching typed ABI prototypes with calls to separately compiled raw-integer exports. Retain the failing x86 hidden-return-pointer regression. The C ABI guarantee covers 8–64-bit and usize/isize representations on every configured target. 128-bit representations remain usable Zig types but are not promised C ABI types and are excluded from this ABI fixture/audit.

### Added

- `handle.Index` has `eql` and `compare`.
- `assert.never(message)`: a path that must not run, returning `noreturn` and stopping in every build, so an `unreachable` prong or an `orelse unreachable` can be a checked contract.
- `own.OwnedIo(T, cleanup)`: `Owned` for a resource released through `Io`; cleanup is `fn (*T, std.Io) void` and `deinit(io)` takes the releaser's Io. Same size and Debug witness as `Owned`.
- `Condition.waitUncancelable`, and `acquireOrderedUncancelable`, `readOrderedUncancelable` and `writeOrderedUncancelable` on `Order.Ordered`: waits and acquires for cleanup paths that cancellation cannot interrupt, with the rank check unchanged.
- `Atomic(T)`: a lock-free cell for an id, count, unit or plain enum, with `load`, `store`, `swap`, the exchanges, `fetchMax`, `fetchMin`, checked `fetchAdd` and `fetchSub` (the domain's own `add` and `sub` in a compare-and-swap loop, the cell untouched on overflow) and the hardware `fetchAddWrapping` and `fetchSubWrapping`.
- `Budget.maximum`, `charged` and `reserveKeeping(amount, kept)`, an ordinary reservation that leaves room for a control path that takes plain `reserve`.
- `capacity` and `isFull` on `bounded.Array`, `Ring`, `Buffer` and `RingBuffer`.
- `Guarded.isHeld`, `BlockingGuarded.isHeld` and `Order.Ordered.isHeld`: a read of the lock without taking it, for lock tests.
- `Duration.saturatingAdd`, `saturatingSub` and `saturatingMul`, `Instant.saturatingAdd`, `saturatingSub` and `saturatingDurationTo`: clamped at the representation's bounds. For an unsigned clock `saturatingDurationTo` gives a zero span where the clock stepped back and `durationTo` reports `error.Underflow`.
- `Id` and `NonZero` relations for unsigned representations: `successor`, `predecessor`, `advance`, `retreat` and `distanceTo`, with `IdExhausted`, `IdUnderflow` and `Backwards` instead of a wrap, and `Id.Step`, the `units.Count` they move by (the domain's own, or `pub const Step` on the tag).
- `units.Duration` and `units.Instant` take any whole-byte integer representation up to 128 bits, so `Duration(.nanosecond, i96)` and `Instant(.awake, .nanosecond, i96)` hold std's nanoseconds exactly, with failure-free adapters. The same-scale conversion is the value itself, with no wide product to narrow.
- A12 `scope`: scope lifetimes. `Table(Brand)` keeps a generation per scope in slots the creator owns; `open` gives a scope, `Scope.ref(pointer)` a `Ref(Brand, P)`, `Scope.reborrow` rebinds a reference from another scope or brand, and `Scope.end` moves the generation on. In Debug and ReleaseSafe `Ref.get` stops the program on a reference whose scope ended, and ending a scope twice, using an ended scope and a table torn down with a scope open stop too; in ReleaseFast and ReleaseSmall a reference is exactly its pointer and nothing is kept. 64-bit generations, retirement of a slot that used them all, `error.Full` and `error.Exhausted`. Paired assembly (x86-64 and aarch64, ReleaseFast and ReleaseSafe) and timing against hand-written code, per-mode stop and no-stop contract, compiler-rejection and portable-profile gates (`check-a12`, `test-a12`), and a worked example.
- A10 `state`: comptime typestate machines. `Machine(States, Events, spec)` validates its specification when analyzed (one edge per state and event, every state reachable, terminal states with no edge out) and answers `next` with one table load. `At(state, Payload)` stages a payload by state, with `transition`, `transitionWith` (a fallible preparation that leaves the stage and destination untouched on failure) and `take` from a terminal stage; outside Debug a stage is exactly its payload. `Runtime(Payload)` pairs a payload with its state and checks every event against the table in all build modes: `step`, `plan` and `commit` (`error.IllegalEvent`, `error.Stale`). Paired assembly (x86-64 and aarch64, ReleaseFast and ReleaseSafe) against a hand-written table, timing against it and against a nested switch, mode-matrix, compiler-rejection and portable-profile gates (`check-a10`, `test-a10`), and a worked example.
- `Guarded`: `tryAcquire`, `acquireYielding(io)` (parks through Io between attempts, cancelable, grants no guard on cancellation) and `acquireYieldingUncancelable(io)` and `teardown`; `BlockingGuarded` and `RwGuarded` get an Io-free `teardown` for a sole owner. Debug and ReleaseSafe assert the lock is free.
- `interior_lock`: a declaration that a type is safe to share through a mutable pointer because all of its mutation is behind its own lock. The guards declare it.
- `Lazy(T)`: leaf initialization under the election mutex, with no `InitContext`, the initializer's own errors only and a mutable handout for an `interior_lock` type.
- `Shared(T, cleanup)`: counted shared ownership of one allocated value with `create`, `createFrom`, `retain`, `get` and `release`, a fail-stop count limit and Debug detection of a handle released twice.
- `eql` and `compare` for `Count`, `Bytes`, `Bits`, `Duration` and `Instant`.
- `Instant.toTimestamp` and `fromTimestamp` for the clock-free `Io.Timestamp` that `Clock.now` returns.
- `id.Counter.last`, `bounded.Limit.exceeds` and `own.Owned.initFrom`, which takes its payload by `moveInto` and consumes the source, so a Budget reservation is owned once.
- Paired assembly (x86-64 and aarch64, ReleaseFast and ReleaseSafe) and timing fixtures for each of these against hand-written code, native contention and Io-schedule tests, and release/Debug contract cases for the fail-stop limits.

- A8 generational domains, fixed/growing/dense storage, primary-witness secondary associations and checked typed indices.
- A9 nonowning refined-input adapters and bounded pointer-free public error context with explicit text classification.

- A6 std.Io blocking and bounded read/write guards, bounded condition registration, stable Once publication/retry, explicit logical-task ordering and checked Confined handoff.
- A7 fixed arrays, queues/rings, explicit bounded buffers, finite limits/reservations and static nonblocking Owned/MustUse contracts.
- A5 (work in progress): one-bit Choice, explicit verdict disclosure, byte equality, endian order and fixed-width selection with public length/overlap errors.
- Separate A5 caller/codegen, unsupported-profile/type, disclosure/format and native property tests; own manual paired benchmarks.
- Latest published green preflight/shakedown pins and preflight-generated CI. The contract gates run as `zig build contracts`, in three groups that hosted CI shards across jobs.

- A4 SecretBytes: full-capacity byte ownership, explicit adoption/exposure/reserve/transfer, overlap-rejecting replacement, shrink erasure, zeroed growth and fail-closed formatting. All cleanup wipes full capacity before free, including slack; errors retain promised ownership and borrows. No remap, implicit growth or slice ownership escape API.
- Pre-free observing-allocator regressions, NoResize allocation-failure coverage, shrinking resize properties, portable/all-mode move contracts and paired enclosing dead-use erasure/codegen fixtures with a full-wipe handwritten baseline.

- A3 checked, saturating and ranged integers, failing integer casts, distinct IDs and checked nonwrapping counters.
- Tagged counts, byte/bit conversions, durations and clock-tagged instants with explicit checked scaling, rounding, endian encoding and std.Io adapters.
- Always-on invariant/pre/post contracts, optional Debug predicates and test-only maybe coverage.
- Scalar contract properties, compile rejection fixtures, portable profile/layout checks, strict paired release codegen and own A/B benchmarks.
- Inline Secret(T) with full-region unconditional erasure, explicit exposure/transfer and fail-closed formatting.
- Guarded(T) with cloak's acquire/release spin semantics and explicit borrowed guards.

[Unreleased]: https://github.com/pedronaugusto/aegis/commits/main
