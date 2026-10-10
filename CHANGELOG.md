# Changelog

All notable changes are documented here, following Keep a Changelog 1.1.0.

## [Unreleased]

### Added

- `int.narrow(Target, source) ?Target`: the one checked narrowing for generic code. It is null where `cast` fails with `Overflow` and the value where it fits, whatever the pair of integer types, where `cast` returns a value for a conversion that cannot fail and an error union otherwise.
- `SpinRwGuarded(T)`: the reader-writer form of `Guarded`, a spin lock with no Io for many readers or one writer (`read`, `write`, `tryRead`, `tryWrite`, `isHeld`, `teardown`). A waiting writer holds off new readers.
- `Guarded.acquireScheduling`: acquire for a section a few system calls long on OS threads with no `Io` to wait through (a reap, a fork gap). A contended waiter yields the thread between tries, where `acquire` pauses, so a holder that was descheduled can run.

### Breaking

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
