# Changelog

All notable changes are documented here, following Keep a Changelog 1.1.0.

## [Unreleased]

## [0.1.9] - 2026-10-15

The change tagged v0.2.0 the same day, released on the 0.1 line: it breaks no caller (only builds that failed to compile now compile), and a family resolves aegis within one line, so a new minor would have split every package that also reaches aegis through shakedown. Use 0.1.9; v0.2.0 is withdrawn.

### Changed

- `secret.Choice` and its kernels compile for every target, backend and CPU instead of failing outside the checked profiles: a build that relied on the compile error to keep unaudited lowering out asserts `secret.Choice.audited` instead.

### Added

- `secret.Choice.audited`: whether this build (compiler, backend, target, CPU model and features, mitigation level) is one whose lowering `zig build check-choices` inspects; `secret.audited_profiles` lists them.
- check-choices covers x86_64-linux-gnu at x86_64_v2/v3/v4, aarch64-linux-gnu at neoverse_n1/v2, aarch64-macos at apple_m2/m3/m4, x86_64 FreeBSD, OpenBSD, NetBSD and DragonFly, and wasm32-freestanding: 20 profiles, 240 builds.

## [0.2.0] - 2026-10-15 [withdrawn]

The same tree as 0.1.9 under a minor; withdrawn for it.

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
