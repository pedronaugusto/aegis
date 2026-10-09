# aegis

Explicit safety types for any Zig project: inline and allocated secrets, guarded data and publication, bounded storage/admission, explicit owners, checked scalar arithmetic, audited value kernels, distinct IDs and units, checked generational storage, refined input adapters, bounded public diagnostics, and executable contracts. Runtime code depends only on std; required wiping, locking, arithmetic, range and conversion checks remain enabled in every build.

Work in progress. Implemented: v0 (`Secret(T)` and spin `Guarded(T)`), A3 numeric/domain foundations, A4 `SecretBytes`, A5 Choice/compare/select value kernels, A6 Io guards/publication/logical-task checks, A7 bounded storage/admission and static owners, and A8/A9 handles, typed indices, checked-input adapters and bounded error context. The full safety catalogue and consumer adoption remain later work.

## Install

Requires Zig 0.17.0:

```sh
zig fetch --save=aegis git+https://github.com/pedronaugusto/aegis#main
```

Add the dependency's `aegis` module, or one standalone namespace such as `aegis.handle`, `aegis.input`, `aegis.err`, `aegis.secret`, `aegis.sync`, `aegis.bounded`, `aegis.own` or `aegis.int`. Wire a namespace with `exe.root_module.addImport("aegis.handle", aegis_dependency.module("aegis.handle"))`. Every implemented namespace is registered separately; root and standalone imports share declaration identities. Consumers fetch neither preflight nor shakedown.

## Usage

<!-- BEGIN GENERATED zig build docs -- usage -->
```zig
const aegis = @import("aegis");

var key = aegis.Secret([32]u8).init(@splat(7));
defer key.deinit();
const bytes = key.expose(); // borrow ends at cleanup/transfer
var counts = aegis.Guarded(usize).init(0);
var held = counts.acquire();
defer held.deinit();
held.value().* += bytes[0];
const Request = aegis.id.NonZero(struct {}, u64);
const request = try Request.fromRaw(1);
const size = try aegis.int.Checked(usize).init(4).mul(8);
const payload = aegis.units.Bytes(usize).fromRaw(size.raw());
const timeout = try aegis.units.Duration(.millisecond, i64).fromRaw(250).toIoDuration();
aegis.assert.post(payload.raw() == 32, "payload fits the record");
_ = request;
_ = timeout;
```
<!-- END GENERATED -->

## Design

`Secret(T)` accepts fixed pointer-free representations and rejects aggregates declaring `deinit`. This checks representation, not the semantic meaning of numeric values; callers must use inline material that owns no external resource. `expose`/`exposeMut` borrow; `moveInto` transfers into uninitialized disjoint storage and securely wipes the source. `deinit` erases the whole representation, including padding, using volatile std erasure. The consumed storage need not be a valid `T`; never read it as `T` afterward. Parser/caller temporaries and displaced values need their own wipes. The direct formatting hook returns `SecretNotFormattable` without writing; std's `{f}` rejects that error set at compile time. Reflection, `{any}`, field access and deliberate exposure can bypass the hook.

`SecretBytes` owns a full byte allocation with explicit live length and capacity. `init(gpa, capacity)` zeros the full region; `adopt(gpa, allocation, len)` consumes a genuine full allocator-owned byte slice only on success. `expose`/`exposeMut` borrow the live prefix. `resizeWithinCapacity` wipes a removed tail and zeros newly live bytes; `replace` rejects overlap with any backing bytes before mutation. `reserve` explicitly allocates, zeros, copies the live prefix and securely wipes the entire old capacity before freeing it; it never resizes or remaps. OOM preserves ownership and borrows. `moveInto` transfers into uninitialized disjoint descriptor storage; cleanup erases full capacity before free. Formatting fails closed. There is no implicit growth, clone, copy-out or bare-slice ownership escape API; ordinary Zig descriptor copies and reflection remain caller bypasses. [Design](https://github.com/pedronaugusto/aegis/blob/main/docs/design.md) records the ownership contract.

`Guarded(T)` keeps data beside cloak's acquire/release atomic spin lock. `acquire`, immediate `defer held.deinit()`, and `held.value()` replace a separate lock/data pair. Published owners have stable addresses. Sections are bounded: no blocking, yielding, recursive acquisition or arbitrary callbacks. Acquisition is noncancelable with no fairness guarantee. The consumer owns data cleanup, reclamation and any escaped-pointer lifetime.

`BlockingGuarded(T)` uses std.Io.Mutex. `acquire(io)` returns Canceled only at std cancellation points, `acquireUncancelable(io)` and `tryAcquire()` preserve their base semantics, and guard cleanup takes the same Io execution domain. `RwGuarded(T)` adds finite admission before std.Io.RwLock counters can overflow; read/write/try/uncancelable operations can return AdmissionLimit. Read guards borrow *const T; mutable pointees still need their own synchronization. No recursive lock, upgrade/downgrade or fairness guarantee is supplied.

`Condition.init()` selects a 65,535 waiter cap; `initLimit(n)` selects another finite cap, including zero. It associates with the first blocking owner in every build. `wait(io, &guard, timeout)` registers before unlocking and always reacquires uncancelably before returning success, Timeout, Canceled or WaiterLimit. Predicate loops end prior borrows and retain one absolute deadline. Cancellation wins raced notification and forwards its unused signal to another waiter. Its intrusive waiter registry allocates nothing and has no epoch wrap; LIFO registration promises no fairness. No spin wait API exists.

`Once(T)` initializes directly into stable unpublished storage. `getOrInit(io, &task, context, init_fn)` takes an explicit `InitContext` per logical task; Debug diagnoses recursive initialization without threadlocal state. The initializer cleans all partial acquisitions on error. Failure/cancellation resets to empty and wakes waiters; success commits ready uncancelably with release publication. `get()` is an acquire load and optional immutable borrow. Waiting cancellation removes only that waiter. Drain readers/initializer/waiters before `deinit(cleanup)`; static cleanup is infallible and nonblocking.

`Order(&ranks)` checks an acyclic caller-defined `after` relation at comptime. Its nested `Ordered(LockType, rank)` accepts `BlockingGuarded` or `RwGuarded` and adds Debug owner/rank checks before blocking, using a caller-carried logical-task `Context`. Context and rank bookkeeping vanish in both release modes. A condition wait reserves its rank during suspension. `Confined(T)` instead accepts explicit `TaskIdentity` values at creation/access/handOff; identity checks remain in Debug and ReleaseSafe, and fast/small stores only T. The caller issues unique identities, ends borrows and externally synchronizes quiescent handoff. Neither type verifies raw aliases or whole-program deadlock freedom.

Zig permits struct copies, field access and escaped pointers. These contracts do not provide a borrow checker, linear types, automatic destructors or universal copied-guard detection. Cleanup is explicit on normal/error returns; abort/process death has no cleanup guarantee. Wipes cover only the specified storage, not old copies, registers, spills, paging, core dumps or hardware side channels. A5 supports only its checked compiler/target boundary; hardware and whole-program constant-time assurance remain unestablished. [Design](https://github.com/pedronaugusto/aegis/blob/main/docs/design.md) defines support, explicit declassification and limits.

## API

`bounded.Array(T, N)` has checked initialized-prefix append/at/pop/items. `Queue(T, N)`/`Ring(T, N)` have checked FIFO push/pop/peek and explicit overwrite with a returned displaced owner; zero ring capacity is rejected, arbitrary nonzero capacity is supported. `Buffer(T)` and `QueueBuffer(T)`/`RingBuffer(T)` accept caller-backed storage or explicitly allocated finite capacity/maximum. Reserve is explicit; OOM leaves storage/owners valid. Entries with `moveInto` transfer through that capability; other T values transfer by caller-disciplined assignment. Full preserves input, Empty preserves destination, mutation ends borrows. Clear/deinit needs a static infallible nonblocking cleanup. Containers are single-owner, without atomics or hidden allocation/growth.

`bounded.Limit(Repr)` has a finite maximum, including zero. Externally synchronized `Budget(Repr)` uses checked reserve/consume; pointer+amount `Reservation` explicitly releases or moves into disjoint storage. It must outlive all reservations. Multi-budget rollback belongs to the admitting operation; caller timeout does not release work that remains admitted. Bounds, overflow prevention and reservation underflow checks remain in every build.

`own.Owned(T, cleanup)` provides borrow/borrowMut/moveInto/take/deinit with static infallible nonblocking cleanup. Debug detects supported use-after-transfer, double cleanup and movement after address binding; release stores only T. Blocking/fallible teardown uses an explicit consumer finish/join before deinit. `MustUse(T, obligation)` takes into a destination or acknowledges a documented non-resource discard; deinit checks discharge only in Debug. Omitted deinit can escape entirely, and release alone does not enforce discharge. Zig still permits copies/reflection.

`int.Checked(Repr).init(raw)` provides fallible add/sub/mul/div/rem/shl with raw operands. `Saturating` explicitly clamps arithmetic; div0 and invalid shift counts still fail. Signed division truncates toward zero, remainder uses that quotient, and min/-1 remainder is zero. `Ranged(Repr, min, max)` checks inclusive bounds on construction and operations. `int.cast(Target, source)` fails on sign or narrowing loss; floating-point conversion is outside this API.

`id.Id(Tag, Repr)` and `NonZero` brand identities; `Counter` externally serializes an unsigned nonwrapping issuer. IDs have eql/compare/hash and explicit endian import/export, with no arithmetic or cross-domain cast. Raw imports do not establish authenticity or uniqueness.

`units.Count(Tag, Repr)`, `Bytes`, `Bits`, `Duration(Unit, Repr)` and `Instant(ClockTag, Unit, Repr)` retain scalar size/alignment. Counts and durations support typed add/sub and scalar mul. Units/representation conversions are checked; `.down` rounds toward negative infinity and `.up` toward positive infinity. Negative input never converts to unsigned. Instants add/subtract durations and compute same-clock differences; changing clock requires sampled correspondence. `.real`, `.awake`, `.boot` and the other std.Io clock tags support checked timestamp adapters. Custom clock types own their epoch interpretation. Wait APIs keep std.Io.Timeout. IDs, units and ranged integers use non-exhaustive enum(Repr) storage. The raw-integer ABI regression validates actual typed calls against separately compiled raw-integer exports, including record fields. The C ABI guarantee covers signed/unsigned 8–64-bit integers and usize/isize on every configured target, including 32-bit x86 and Windows. 128-bit repr values remain usable Zig types but are NOT promised C ABI types and are excluded from the raw-integer ABI fixture/audit; MSVC has no 128-bit integer, and Zig 0.17 lowers enum(u128)/enum(i128) returns differently from raw integers on x86-64 Windows. Equal layout alone never proves call interoperability. Their repr must be a signed/unsigned 8, 16, 32, 64 or 128-bit integer (including usize/isize); other widths are rejected explicitly. Encoding writes the exact repr width/endian rather than copying ABI storage. Checked/Saturating retain arbitrary nonzero integer widths; non-byte widths reject byte encoding. Foreign callers must honor nonzero/range contracts or checked import must validate their return at the boundary.

`assert.invariant`, `pre` and `post` fail-stop in every build with a static public message. Peer failures return errors. `debug` is optional and still evaluates its argument; `debugCheck` removes the predicate call in both release modes. `maybe` accepts a side-effect-free possibility without asserting truth; `maybeCount` instruments caller-owned storage only in test builds. Contracts do not unwind cleanup on panic.

`handle.Domain` issues nonzero pool instances within a caller-supplied unique namespace. `Pool(T, Tag)` uses caller slot storage; `SlotMap` explicitly grows allocator-owned slots; `DenseSlotMap` adds contiguous iteration and swap removal. Keys retain namespace, instance, position and generation. Bounds, instance, occupancy and generation checks remain in every build. Generations never wrap: exhausted slots retire. `SecondaryMap(Key, V)` keeps full keys and requires the primary's liveness witness when resolving; stale associations remain owned until removed or pruned. Insert consumes the source only on success; remove transfers into uninitialized disjoint destination storage. Cleanup receives detached values, with no hidden lock. Growth and structural mutation end the documented borrows. `Index(Tag, Repr)` (also `typedIndex`) brands a position and validates the current slice at every access.

`input.Untrusted(T)` preserves a nonowning value or const pointer view. `parse(context, parser)` invokes a parser with an explicit named error union and distinct refined result. Parsing conveys no authentication, authorization or immutable ownership; borrowed results require the input to remain live and unchanged. The adapter adds no parser engine or implicit allocation.

`err.Context(Frame, N)` retains the first N public frames and marks truncation. `Failure(ErrorSet, Frame, N)` retains the original cause beside an inline context. Frame structs explicitly declare `pub const aegis_public_frame = true`; admitted fields are public booleans, integers, enums, nested admitted frames and `PublicText(N)`. Pointers, slices, owners, unknown aggregates and custom formatters are rejected. This is reviewed classification, not secret-flow proof. Default crypto frames contain no runtime text. Optional runtime text requires `PublicSource.classify(comptime reason, bytes)` and bounded escaping; callers must never classify secrets as public. Context formatting allocates nothing and preserves Writer errors.

## Scope

`aegis.secret` exposes `Choice`, `equal`, `equalBytes`, `compareUnsigned` and `OrderChoices`; choices offer logic, integer/byte selection and explicit `declassify(comptime reason)`. Public length and overlap validation remain enabled.

No reference counting, protocol parsers, stored deleter vtables, hidden workers, automatic destructors or code analysis. Runtime closure is std only. Tags, checks and explicit raw boundaries are API discipline; Zig fields/reflection can bypass them. [Design](https://github.com/pedronaugusto/aegis/blob/main/docs/design.md) records the ownership and foreign-boundary contracts. Glint admission and consumer adoption remain later work. Equal handwritten wipe/locking cost does not mean those operations have zero cost.

## Built with

[preflight](https://github.com/pedronaugusto/preflight) is lazy build tooling; [shakedown](https://github.com/pedronaugusto/shakedown) is a lazy test-only dependency. The public module imports neither.

## Testing

Run A8/A9 cases with `zig build test-handles-input -Dtest-filter=A8 -Dtest-filter=A9`. Run targeted cases with `zig build test -Dtest-filter=A3`, `-Dtest-filter=Secret`, `-Dtest-filter=A4`, `-Dtest-filter=A5`, `-Dtest-filter=Guarded` or `-Dtest-filter=Consumer`. `zig build lint` checks source, docs and structure. `zig build contracts` runs the negative-compilation, consumer-isolation, strict codegen parity and release-mode gates named below; hosted CI runs its three groups, `contracts-values`, `contracts-choices` and `contracts-published`, as separate jobs. `zig build check` compiles the suite; `zig build bench` runs own-operation A/B manually. The `test-secret-bytes` and `check-secret-bytes` gates exercise release cleanup and portable byte-owner contracts. The `check-choices` and `check-choices-negative` gates audit enclosing callers and disclosure/support contracts. The `test-scalars` and `check-contracts` gates retain release-mode failures; `check-negative` rejects cross-domain use. `test-a67` executes both release modes; `check-a67` retains the identity/diagnostic mode matrix and portable value profiles. The A6 race cases use shakedown’s portable baton-thread executor with deterministic seeded scheduling and virtual time. CI smoke-checks benchmark programs without timing gates. `check-handles-input` compiles A8/A9 in all four modes on the configured hosts plus 32-bit, wasm and freestanding; its Fast/Small gate compares handwritten instruction/layout pairs and intended-reason compiler rejections. The hosted merge includes targeted Linux TSan.

## Licence

MIT; see [LICENSE](LICENSE).
