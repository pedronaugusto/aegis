# aegis

Explicit safety types for any Zig project: inline and allocated secrets, guarded data and publication, bounded storage/admission, explicit owners, checked scalar arithmetic, audited value kernels, distinct IDs and units, checked generational storage, refined input adapters, bounded public diagnostics, comptime typestate machines, scope lifetimes, and executable contracts. Runtime code depends only on std; required wiping, locking, arithmetic, range and conversion checks remain enabled in every build.

Every module has a release contract the gate holds and an example the build runs ([Release contracts](#release-contracts)). The API can still change before 1.0.

## Install

Requires Zig 0.17.0:

```sh
zig fetch --save=aegis git+https://github.com/pedronaugusto/aegis#main
```

Add the dependency's one module, `aegis`, and import it as `@import("aegis")`; everything below is a namespace of it (`aegis.handle`, `aegis.secret`, `aegis.sync`, `aegis.int`, ...). Zig compiles only what a program uses, so the namespaces left alone cost nothing. Consumers fetch neither preflight nor shakedown.

## Usage

<!-- BEGIN GENERATED zig build docs -- usage -->
```zig
const std = @import("std");
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
const timeout = aegis.units.Duration(.millisecond, i64).fromRaw(250).toIoDuration();
aegis.assert.post(payload.eql(.fromRaw(32)), "payload fits the record");
// One text form for durations and sizes, exact both ways: `1m30s`, `64MiB`.
const grace = try aegis.units.Duration(.millisecond, u32).parse("1m30s");
const limit = try aegis.units.Bytes(u64).parse("64MiB");
var line: [64]u8 = undefined;
var w: std.Io.Writer = .fixed(&line);
try w.print("grace {f}, limit {f}", .{ grace, limit });
aegis.assert.post(std.mem.eql(u8, w.buffered(), "grace 1m30s, limit 64MiB"), "text reads back");
_ = request;
_ = timeout;
```
<!-- END GENERATED -->

## Typestate

<!-- BEGIN GENERATED zig build docs -- state -->
```zig
const aegis = @import("aegis");

const Session = aegis.state.Machine(enum { pending, authenticated, closed }, enum { verify, close }, .{
    .initial = .pending,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .pending, .on = .verify, .to = .authenticated },
        .{ .from = .authenticated, .on = .close, .to = .closed },
    },
});
const Credentials = struct { token: u64 };
const Receipt = struct { account: u32 };
const Pending = Session.At(.pending, Credentials);
const Authenticated = Session.At(.authenticated, Receipt);

/// The one place a receipt is made: it checks the credentials and fails before anything moves.
fn verify(expected: u64, credentials: *Credentials, receipt: *Receipt) error{BadToken}!void {
    if (credentials.token != expected) return error.BadToken;
    receipt.* = .{ .account = 7 };
}

/// Takes an authenticated stage, so a pending one does not compile here.
fn send(session: *Authenticated, message: []const u8) usize {
    return message.len + session.get().account;
}

pub fn main() !void {
    var pending = Pending.init(.{ .token = 42 });
    var authenticated: Authenticated = undefined;
    if (pending.transitionWith(.verify, &authenticated, @as(u64, 41), verify)) |_| unreachable else |err| aegis.assert.invariant(err == error.BadToken, "a wrong token is refused");
    try pending.transitionWith(.verify, &authenticated, @as(u64, 42), verify); // consumes `pending`
    aegis.assert.post(send(&authenticated, "hello") == 12, "a message is sent on the authenticated stage");

    // Events from a peer arrive at run time: an undeclared one is an error, never a state change.
    var link = Session.Runtime(u32).init(0);
    _ = try link.step(.verify);
    if (link.step(.verify)) |_| unreachable else |err| aegis.assert.invariant(err == error.IllegalEvent, "an undeclared event is refused");
    aegis.assert.post(link.current() == .authenticated, "the refused event changed nothing");
}
```
<!-- END GENERATED -->

## Scope lifetimes

<!-- BEGIN GENERATED zig build docs -- scope -->
```zig
const aegis = @import("aegis");

const std = @import("std");

/// The brand: a reference made in a request scope is a different type from one made in any other kind.
const Request = struct {};
const Requests = aegis.scope.Table(Request);

pub fn main() !void {
    // The connection keeps the table. One slot per request that can be open and checked at once.
    var slots: [4]Requests.Slot = undefined;
    var requests = Requests.init(&slots);
    defer requests.deinit();

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const body = try arena.allocator().dupe(u8, "GET /index");
    const request = try requests.open();
    const view = request.ref(body); // good while `request` is open
    aegis.assert.post(view.get().len == 10, "the body is readable while its request is open");

    request.end();
    _ = arena.reset(.free_all);
    // `view.get()` from here on stops the program in Debug and ReleaseSafe: its scope ended.
    // In ReleaseFast and ReleaseSmall nothing is checked and `view` is just the slice.
}
```
<!-- END GENERATED -->

## Release contracts

What each module is in ReleaseFast and ReleaseSmall, what it keeps checking in every build, and what Debug and ReleaseSafe, or Debug alone, add. Each row is held by the gate: the layout against hand-written storage on every portable profile and mode, paired kernels whose instructions equal hand-written code, and a stop in exactly the builds a column names. Every module has an example the build runs. Every module is required by a danger rule of [glint](https://github.com/pedronaugusto/glint)'s aegis pack at the sites where its danger exists, or a module so required builds on it; the catalogue refuses a module with neither.

<!-- BEGIN GENERATED zig build catalogue -->
| Module | Required by | In ReleaseFast and ReleaseSmall | In every build | Debug and ReleaseSafe | Debug | Example |
|---|---|---|---|---|---|---|
| `Secret` | A008 | exactly `T` | the whole representation, padding included, wiped by volatile stores at `deinit` and after `moveInto`; a move into overlapping storage stops; formatting refused at compile time | — | — | [secret.zig](examples/secret.zig) |
| `SecretBytes` | A008 | allocator, allocation and live length, as a hand-written owner | full capacity wiped before free and on `reserve`; capacity and overlap errors before any change; a move into overlapping storage stops | — | — | [secret_bytes.zig](examples/secret_bytes.zig) |
| `secret` | A008 | a `Choice` is one byte holding one bit | the instructions of hand-written mask arithmetic, with no branch or load on a secret in the audited profiles; unequal lengths and partial overlap are errors | — | — | [choice.zig](examples/choice.zig) |
| `secret.Timing` | `secret` builds on it | `Timing` is the mode it found, one `u64` | data-independent timing set for the span where the processor has it, nothing where it has none; `scrubStack` zeroes its frame with volatile stores | — | — | [timing.zig](examples/timing.zig) |
| `Guarded` | A007 | a lock word beside `T`; a guard is one pointer | acquire is one swap and release one store | `teardown` while the lock is held stops | — | [guarded.zig](examples/guarded.zig) |
| `SpinRwGuarded` | A007 | one state word beside `T`; a guard is one pointer | readers share and a writer excludes them, a waiting writer holding off new readers | `teardown` while the lock is held stops | — | [spin_rw_guarded.zig](examples/spin_rw_guarded.zig) |
| `BlockingGuarded` | A007 | a `std.Io.Mutex` beside `T`; a guard is one pointer | the mutex's own operations; a canceled acquire grants nothing | `teardown` while the lock is held stops | — | [blocking_guarded.zig](examples/blocking_guarded.zig) |
| `RwGuarded` | A007 | a `std.Io.RwLock`, an admission count and its limit beside `T` | admission past the limit is `AdmissionLimit`, before std's packed counters can overflow | `teardown` while the lock is held stops | — | [rw_guarded.zig](examples/rw_guarded.zig) |
| `Condition` | A007 | the hand-written waiter registry | the waiter limit; the guard held again on every return; a wait with another owner's guard stops | — | — | [condition.zig](examples/condition.zig) |
| `Once` | A007 | state, mutex, a condition and `T`; `InitContext` is empty | initialized once and published by a release store; the waiter limit | — | a recursive initializer stops | [once.zig](examples/once.zig) |
| `Lazy` | A007 | state, mutex and `T` | initialized once and published by a release store; only the initializer's errors | — | — | [lazy.zig](examples/lazy.zig) |
| `Atomic` | A007 | the backing integer's atomic cell | checked `fetchAdd` and `fetchSub` report overflow with the cell unchanged | — | — | [atomic.zig](examples/atomic.zig) |
| `Shared` | A007 | one pointer | the static cleanup runs once, at the last release; a count past its limit stops | — | a handle released twice stops | [shared.zig](examples/shared.zig) |
| `Order` | A021 | `Context` is empty; an ordered lock is its lock | the lock's own operations | — | an acquire out of rank or of an owner already held stops | [order.zig](examples/order.zig) |
| `Confined` | A007 | exactly `T` | nothing: the payload is plain data | access or hand-off by a task that does not own it stops | — | [confined.zig](examples/confined.zig) |
| `int` | A010 | the integer | overflow, division by zero, invalid shifts, range and narrowing are errors; a conversion that cannot fail carries none | — | — | [int.zig](examples/int.zig) |
| `id` | A016 | the integer | ids never wrap: exhaustion, underflow and a backwards distance are errors; `NonZero` refuses zero | — | — | [id.zig](examples/id.zig) |
| `units` | A011 | the integer | arithmetic and conversions checked, a conversion that cannot fail carrying no check; text read and written exactly | — | — | [units.zig](examples/units.zig) |
| `assert` | A013 | no storage; a check is a compare and a cold stop | `invariant`, `pre`, `post` and `never` stop | — | `debug` and `debugCheck` stop | [assert.zig](examples/assert.zig) |
| `bounded` | A012 | storage and counters, as hand-written | `Full`, `Empty`, `OutOfBounds` and `LimitExceeded` returned; a budget never holds more than its maximum; a reservation underflow stops | — | — | [bounded.zig](examples/bounded.zig) |
| `own` | A015 | exactly `T` | the static cleanup once, at `deinit` | — | a second cleanup and an undischarged `MustUse` stop | [own.zig](examples/own.zig) |
| `state` | A017 | a stage is its payload; a runtime machine is its payload and state | an undeclared event is `IllegalEvent` and changes nothing; a commit of an edge the machine does not declare stops | a transition into its own source stops | a stage used after its payload moved on stops | [state.zig](examples/state.zig) |
| `scope` | A014 | a reference is its pointer; a table keeps nothing | nothing: these checks follow Zig's runtime safety | a reference used after its scope ended, a scope ended twice or used after its end, and a table torn down with a scope open stop | — | [scope.zig](examples/scope.zig) |
| `handle` | A014 | keys and slots as hand-written; an index is its integer | stale, foreign and out-of-range keys are errors; generations never wrap, a worn-out slot retires | — | — | [handle.zig](examples/handle.zig) |
| `input` | A009 | the value or view it wraps | the parser's own checks and errors, unchanged | — | — | [input.zig](examples/input.zig) |
| `err` | A018 | inline frames, a length and a truncation mark | frames kept up to the capacity and truncation marked; nothing allocated | — | — | [err.zig](examples/err.zig) |
<!-- END GENERATED -->

## Design

`Secret(T)` accepts fixed pointer-free representations and rejects aggregates declaring `deinit`. This checks representation, not the semantic meaning of numeric values; callers must use inline material that owns no external resource. `expose`/`exposeMut` borrow; `moveInto` transfers into uninitialized disjoint storage and securely wipes the source. `deinit` erases the whole representation, including padding, using volatile std erasure. The consumed storage need not be a valid `T`; never read it as `T` afterward. Parser/caller temporaries and displaced values need their own wipes. The direct formatting hook returns `SecretNotFormattable` without writing; std's `{f}` rejects that error set at compile time. Reflection, `{any}`, field access and deliberate exposure can bypass the hook.

`SecretBytes` owns a full byte allocation with explicit live length and capacity. `init(gpa, capacity)` zeros the full region; `adopt(gpa, allocation, len)` consumes a genuine full allocator-owned byte slice only on success. `expose`/`exposeMut` borrow the live prefix. `resizeWithinCapacity` wipes a removed tail and zeros newly live bytes; `replace` rejects overlap with any backing bytes before mutation. `reserve` explicitly allocates, zeros, copies the live prefix and securely wipes the entire old capacity before freeing it; it never resizes or remaps. `appendSlice` and `Writer` (a `std.Io.Writer` whose buffer is the allocation itself, published as the live prefix at `flush`) grow only through `reserve`, at least doubling, so text built a piece at a time leaves no unwiped copy behind. OOM preserves ownership and borrows. `moveInto` transfers into uninitialized disjoint descriptor storage; cleanup erases full capacity before free. Formatting fails closed. There is no growth but through `reserve`, no clone, copy-out or bare-slice ownership escape API; ordinary Zig descriptor copies and reflection remain caller bypasses. [Design](https://github.com/pedronaugusto/aegis/blob/main/docs/design.md) records the ownership contract.

`Guarded(T)` keeps data beside cloak's acquire/release atomic spin lock. `acquire`, immediate `defer held.deinit()`, and `held.value()` replace a separate lock/data pair. Published owners have stable addresses. Sections are bounded: no blocking, yielding, recursive acquisition or arbitrary callbacks. Acquisition is noncancelable with no fairness guarantee: one acquire swap when the lock is free, and a contended waiter spins on a plain load so the held lock's cache line is not rewritten. `tryAcquire()` returns null instead of waiting. `isHeld()` reads the lock without taking it, a snapshot for tests and diagnostics (`BlockingGuarded` and an `Order.Ordered` over either have it too). `acquireYielding(io)` is for an owner whose holder may not be running, such as on a cooperative Io: after a short spin it sleeps through `io` between attempts, returns Canceled without granting a guard (`acquireYieldingUncancelable(io)` blocks cancellation for the wait), and still needs a bounded section. `teardown()` hands a sole owner its data with no lock and no Io (Debug and ReleaseSafe assert the lock is free). `guard.handOff()` gives the release of a held lock to code that runs it past the holder's frame, as a scheduler releases a bucket lock once the holder's task is off its stack: the guard is consumed and the returned `Handoff` is released exactly once (`release()`); glint's A003 reads the hand-off as a declared transfer. `SpinRwGuarded(T)` is the reader-writer form of the same lock: `read()` and `tryRead()` give a shared `*const T`, `write()` and `tryWrite()` an exclusive `*T`, with the same bounded-section rules, no Io, no upgrade or downgrade and `isHeld()` and `teardown()` as above. A waiting writer holds off new readers, so a stream of readers cannot starve it. The consumer owns data cleanup, reclamation and any escaped-pointer lifetime.

`BlockingGuarded(T)` uses std.Io.Mutex. `acquire(io)` returns Canceled only at std cancellation points, `acquireUncancelable(io)` and `tryAcquire()` preserve their base semantics, and guard cleanup takes the same Io execution domain. `RwGuarded(T)` adds finite admission before std.Io.RwLock counters can overflow; read/write/try/uncancelable operations can return AdmissionLimit. Read guards borrow *const T; mutable pointees still need their own synchronization. No recursive lock, upgrade/downgrade or fairness guarantee is supplied. Both have the same Io-free `teardown()` for a sole owner. Every aegis guard declares `pub const interior_lock = true`: all access is behind its lock, so a shared owner may hand it out through a mutable pointer. A type with its own locking may declare it too.

`Condition.init()` selects a 65,535 waiter cap; `initLimit(n)` selects another finite cap, including zero. It associates with the first blocking owner in every build. `wait(io, &guard, timeout)` registers before unlocking and always reacquires uncancelably before returning success, Timeout, Canceled or WaiterLimit. Predicate loops end prior borrows and retain one absolute deadline. Cancellation wins raced notification and forwards its unused signal to another waiter. Its intrusive waiter registry allocates nothing and has no epoch wrap; LIFO registration promises no fairness. `waitUncancelable(io, &guard, timeout)` is the wait for a cleanup path that must see the state change: cancellation is blocked for it, so it returns only on a wake, the timeout or the waiter limit, with the guard held as `wait` leaves it. No spin wait API exists.

`Once(T)` initializes directly into stable unpublished storage. `getOrInit(io, &task, context, init_fn)` takes an explicit `InitContext` per logical task; Debug diagnoses recursive initialization without threadlocal state. The initializer cleans all partial acquisitions on error. Failure/cancellation resets to empty and wakes waiters; success commits ready uncancelably with release publication. `get()` is an acquire load and optional immutable borrow. Waiting cancellation removes only that waiter. Drain readers/initializer/waiters before `deinit(cleanup)`; static cleanup is infallible and nonblocking.

`Lazy(T)` is `Once` for a leaf initializer: `getOrInit(io, context, init_fn)` takes no `InitContext`, and `init_fn(context, *T)` returns void or an error union of void, whose errors are the only ones `getOrInit` returns. The initializer gets no Io, so it cannot wait or reach another Lazy; it runs under the election mutex, so waiters block, uncancelably, for its bounded time. Failure leaves it empty for the next caller. A `T` declaring `interior_lock` is handed out mutable (`Lazy(T).Ref` is `*T`), any other const. Use `Once` for an initializer that waits, allocates through Io or must be canceled.

`Shared(T, cleanup)` is counted ownership of one allocated `T`: `create(gpa, value)` or `createFrom(gpa, &source)` (by `moveInto`, source untouched on OOM), `retain()` for another handle, `get()`, and `release()`, whose last call runs the static cleanup and frees the block. A handle is one pointer; Debug diagnoses a handle released twice. The count is a resource limit and fails stop before it can wrap. A `T` declaring `interior_lock` is handed out mutable, any other const.

`Atomic(T)` is a lock-free cell for one id, count, unit or plain enum, read and written whole: `load`, `store`, `swap`, `cmpxchgStrong`/`cmpxchgWeak`, `fetchMax` and `fetchMin`, with the size and alignment of the backing integer (8 to 64 bits) and the instructions of `std.atomic.Value`. Where the domain has its own checked `add` and `sub` (`Count`, `Bytes`, `Bits`, `Duration`), `fetchAdd` and `fetchSub` apply them atomically with a compare-and-swap loop and report overflow with the cell untouched; `fetchAddWrapping` and `fetchSubWrapping` are the hardware instruction, for a counter whose width cannot be reached. The checked form is the same loop written by hand and costs about the same as it; against the hardware instruction it is a few percent dearer uncontended and several times dearer when four tasks hammer one cell.

`Order(&ranks)` checks an acyclic caller-defined `after` relation at comptime. Its nested `Ordered(LockType, rank)` accepts `BlockingGuarded` or `RwGuarded` and adds Debug owner/rank checks before blocking, using a caller-carried logical-task `Context`. Context and rank bookkeeping vanish in both release modes. A condition wait reserves its rank during suspension. A cleanup path that cannot take a cancellation takes `acquireOrderedUncancelable`, `readOrderedUncancelable` or `writeOrderedUncancelable`, which check the same rank and are not interrupted. `Confined(T)` instead accepts explicit `TaskIdentity` values at creation/access/handOff; identity checks remain in Debug and ReleaseSafe, and fast/small stores only T. The caller issues unique identities, ends borrows and externally synchronizes quiescent handoff. Neither type verifies raw aliases or whole-program deadlock freedom.

Zig permits struct copies, field access and escaped pointers. These contracts do not provide a borrow checker, linear types, automatic destructors or universal copied-guard detection. Cleanup is explicit on normal/error returns; abort/process death has no cleanup guarantee. Wipes cover only the specified storage, not old copies, registers, spills, paging, core dumps or hardware side channels. A5's kernels compile everywhere and `Choice.audited` says whether this build's lowering is one `check-choices` inspects; hardware and whole-program constant-time assurance remain unestablished. [Design](https://github.com/pedronaugusto/aegis/blob/main/docs/design.md) defines support, explicit declassification and limits.

## API

`state.Machine(States, Events, spec)` declares a protocol's shape once: the initial state, the terminal states and one edge per state and event. A mistake in the specification does not compile: a duplicate edge, a terminal state with an edge out, a state with no way out that is not terminal, a state no edge reaches, or an initial state that is terminal. `Machine.At(state, Payload)` stages a payload at one state, and the stage is part of its type, so a function that takes the authenticated stage cannot be called with the pending one. `transition(event, &next)` moves the payload along a declared edge into storage apart from the stage and consumes the stage; `transitionWith(event, &next, context, prepare)` builds a payload of another type, and when `prepare` fails the stage is untouched and the destination unwritten. Only the initial stage is constructed, and a payload leaves only a terminal stage by `take`. Zig still lets a caller copy a stage and keep using the old one: Debug reports a stage used after its payload moved on, and no build mode claims more. Outside Debug a stage is exactly its payload. `Machine.Runtime(Payload)` pairs a payload with its current state for events that arrive at run time. `step(event)` checks the table in every build mode, answers an event the state does not declare with `error.IllegalEvent` and changes nothing; `plan` and `commit` split the step around work that can fail or suspend, and `commit` returns `error.Stale` once the machine has left the state the plan was made in. The table is one byte load, as small as a hand-written table. That an event is genuine, ordered or authorized is the caller's check; one driver owns a runtime machine.

`scope.Table(Brand)` is what a creator keeps for the scopes it opens: a connection for its requests, a server for its connections. `Brand` is a type naming the kind of scope. The creator owns the table and the slots under it, so the record a check reads is never inside the scope's own memory and is still there after the scope ends. `open()` hands out a scope, `ref(pointer)` makes a `Ref(Brand, P)` for a pointer or slice the scope vouches for, and `end()` moves the scope's generation on. `Ref.get()` returns the pointer and, in Debug and ReleaseSafe, stops the program with a message if the scope has ended, whether or not the slot has been reused since. A reference from one brand is a different type from a reference from another, so the compiler rejects mixing them. A reference moves to another scope only by `reborrow` on that scope, which checks the source first and says in the code that the memory now lives under the new scope. Ending a scope twice, using an ended scope and tearing the table down with a scope open are stopped the same way. The generation is 64 bits, a slot that has used every generation is retired and never reused, and `open` returns `Full` when every slot is open and `Exhausted` when every slot is retired. These checks follow Zig's runtime safety: ReleaseFast and ReleaseSmall keep no table, no generation and no check, a reference is exactly its pointer, and `open` cannot fail there, so a slot count is the number of scopes that can be open and checked, never an admission limit. This catches a use after the scope ended when the reference is used; a raw pointer taken out of `get` and kept, or a reference never used, is not seen. A check that must be handled instead of stopping the program belongs to a handle, which is checked in every mode.

`bounded.Array(T, N)` has checked initialized-prefix append/at/pop/items. `Queue(T, N)`/`Ring(T, N)` have checked FIFO push/pop/peek and explicit overwrite with a returned displaced owner; zero ring capacity is rejected, arbitrary nonzero capacity is supported. `Buffer(T)` and `QueueBuffer(T)`/`RingBuffer(T)` accept caller-backed storage or explicitly allocated finite capacity/maximum. Reserve is explicit; OOM leaves storage/owners valid. Entries with `moveInto` transfer through that capability; other T values transfer by caller-disciplined assignment. Full preserves input, Empty preserves destination, mutation ends borrows. Clear/deinit needs a static infallible nonblocking cleanup. Every container reports `capacity()` (what it holds as it stands; a buffer's grows with `reserve`) and `isFull()`, true exactly when the next append or push would fail with Full. Containers are single-owner, without atomics or hidden allocation/growth.

`bounded.Limit(Repr)` has a finite maximum, including zero. Externally synchronized `Budget(Repr)` uses checked reserve/consume; pointer+amount `Reservation` explicitly releases, moves into disjoint storage, or is consumed, keeping its amount as consumed work (an allocation charged before it is made, once it succeeds). It must outlive all reservations. `maximum()`, `charged()` and `remaining()` read it. `reserveKeeping(amount, kept)` is the ordinary admission that leaves `kept` unreserved, so a control path that must still be admitted (the cancellation or termination of work already admitted) takes plain `reserve` and finds the room; the budget never holds more than its maximum. Multi-budget rollback belongs to the admitting operation; caller timeout does not release work that remains admitted. Bounds, overflow prevention and reservation underflow checks remain in every build. `Limit.exceeds(amount)` is the boolean form of `check`.

`own.Owned(T, cleanup)` provides borrow/borrowMut/moveInto/move/take/lend/deinit with static infallible nonblocking cleanup. `init(value)` copies its payload; `initFrom(&source)` takes it by `moveInto` when `T` declares one (a Budget `Reservation`, a `Secret`) and consumes the source. Debug detects supported use-after-transfer, double cleanup and movement after address binding; release stores only T. `move()` hands a used owner on by value: it consumes the source as `moveInto` does and returns a fresh owner that binds at its first use, so one opened and used in a function can be returned and stored. `lend()` gives `own.Lent(T)`, a copy of a payload copied by value (a file, a directory) that has no `deinit`: what an accessor hands out of a handle its owner closes. A payload with its own `moveInto` is moved by `moveInto` and reached by `borrow`, never by `move` or `lend`. Blocking/fallible teardown uses an explicit consumer finish/join before deinit. `own.OwnedIo(T, cleanup)` is the same owner for a resource released through `Io`, such as an open file: its cleanup is `fn (*T, std.Io) void` and `deinit(io)` takes the Io of whoever releases it, since an owner stores none. `own.readFile(io, dir, sub_path, gpa, limit)` reads a whole file (`readFileSentinel` ends it with a sentinel, as a parser wants), at most `limit` bytes (`units.Bytes(u64)`), into memory the caller owns: it reads the file's length first and returns its error, so a cancel that lands there is `Canceled`, where std's `Dir.readFileAlloc` reads on; a file longer than the limit is refused before anything is allocated, and the read is as long as the length said. `MustUse(T, obligation)` takes into a destination or acknowledges a documented non-resource discard; deinit checks discharge only in Debug. Omitted deinit can escape entirely, and release alone does not enforce discharge. Zig still permits copies/reflection.

`int.Checked(Repr).init(raw)` provides fallible add/sub/mul/div/rem/shl with raw operands. `Saturating` explicitly clamps arithmetic; div0 and invalid shift counts still fail. Signed division truncates toward zero, remainder uses that quotient, and min/-1 remainder is zero. `Ranged(Repr, min, max)` checks inclusive bounds on construction and operations; `literal(value)` checks a value known at compile time there, for a default or a constant. `int.cast(Target, source)` fails on sign or narrowing loss, and carries no error where every source value fits (`u32` into `u64`, or into `usize`, on every supported target alike: `usize` and `isize` count as 32 to 64 bits, so code that compiles on one target compiles on all); floating-point conversion is outside this API. `int.narrow(Target, source)` is the same check for generic code: the value where it fits and `null` where `cast` would fail with `Overflow`, whatever the pair of integer types, so one function can narrow what `cast` types two ways.

`id.Id(Tag, Repr)` and `NonZero` brand identities; `Counter` externally serializes an unsigned nonwrapping issuer; `last()` reads the last ID issued, or null before the first. IDs have eql/compare/hash and explicit endian import/export, with no arithmetic or cross-domain cast. Unsigned ids relate to counts of steps and never wrap: `successor`, `predecessor`, `advance(count)`, `retreat(count)` and `distanceTo(other)`, with `error.IdExhausted` past the largest id, `error.IdUnderflow` before the first (zero, or one for `NonZero`) and `error.Backwards` for a distance that runs the other way. The count is `Id.Step`: a `units.Count` of the id's own domain, or the one the tag names with `pub const Step = ...`, so a sequence number moves by a count of records and by nothing else. Raw imports do not establish authenticity or uniqueness.

`units.Count(Tag, Repr)`, `Bytes`, `Bits`, `Duration(Unit, Repr)` and `Instant(ClockTag, Unit, Repr)` retain scalar size/alignment. Counts and durations support typed add/sub and scalar mul. Every unit has `eql` and `compare`, like IDs. Units/representation conversions are checked, and a conversion that cannot fail carries no error and no range check, whether `convert` between representations or between units and the std adapters (`rounding` is comptime, since only `.exact` can be inexact: `.down` and `.up` always have an answer); `.down` rounds toward negative infinity and `.up` toward positive infinity. Negative input never converts to unsigned. Instants add/subtract durations and compute same-clock differences; a clock that saturates on purpose has `saturatingAdd`, `saturatingSub` and `saturatingMul` on durations and `saturatingAdd`, `saturatingSub` and `saturatingDurationTo` on instants, which clamp at the representation's bounds (an unsigned clock read out of order gives a zero span where `durationTo` reports `error.Underflow`); changing clock requires sampled correspondence. `.real`, `.awake`, `.boot` and the other std.Io clock tags support timestamp adapters: `toIoDuration`/`fromIoDuration`, `toTimestamp`/`fromTimestamp` for the clock-free `Io.Timestamp` that `Clock.now` returns, and the clock-tagged `toIoTimestamp`/`fromIoTimestamp`. A conversion that cannot fail for the representation and unit carries no error and no range check (a millisecond `i64` widens into std's nanoseconds, a nanosecond `i128` takes any std timestamp); one that can lose data keeps its check and only the errors it can have. Custom clock types own their epoch interpretation. Wait APIs keep std.Io.Timeout. IDs, units and ranged integers use non-exhaustive enum(Repr) storage. The raw-integer ABI regression validates actual typed calls against separately compiled raw-integer exports, including record fields. The C ABI guarantee covers signed/unsigned 8–64-bit integers and usize/isize on every configured target, including 32-bit x86 and Windows. 128-bit repr values remain usable Zig types but are NOT promised C ABI types and are excluded from the raw-integer ABI fixture/audit; MSVC has no 128-bit integer, and Zig 0.17 lowers enum(u128)/enum(i128) returns differently from raw integers on x86-64 Windows. Equal layout alone never proves call interoperability. Their repr must be a signed/unsigned 8, 16, 32, 64 or 128-bit integer (including usize/isize); other widths are rejected explicitly. `Duration` and `Instant` also take any whole-byte width up to 128 bits, so a nanosecond `i96` holds std's `Io.Duration` and `Io.Timestamp` exactly and their adapters carry no error. Encoding writes the exact repr width/endian rather than copying ABI storage. Checked/Saturating retain arbitrary nonzero integer widths; non-byte widths reject byte encoding. Foreign callers must honor nonzero/range contracts or checked import must validate their return at the boundary.

Durations and sizes have one text form, for a command line, a configuration file and a log alike. `Duration.parse` reads components from the coarsest unit to the finest, each at most once (`30s`, `1m30s`, `250ms`, `1.5h`, `2d12h`; units `d`, `h`, `m`, `s`, `ms`, `us` or `µs`, `ns`; a leading `-`; `0` alone), and `Bytes.parse` a number and a unit or bytes alone (`4096`, `64MiB`, `1.5GB`), binary units (`KiB` to `YiB`, powers of 1024) and decimal ones (`kB` to `YB`, powers of 1000) spelled exactly, so `KB` or `mb` is refused rather than read as either. The value is exact: one finer than the type holds is `error.Inexact` (`1.5s` as whole seconds, `0.1KiB`), one the representation cannot hold `error.Overflow`, anything else `error.Malformed`; nothing is rounded. `format` (`{f}`) writes the canonical form that `parse` reads back to the same value: a duration's nonzero components from days down (`1h30m`, `-250ms`, `0s`), a size in the largest unit that divides it (`64MiB`, `1500kB`, `1500B`). `max_text_len` is the longest text `format` writes for the type, to size a buffer by. A `std.Io.Duration` reads and writes through `Duration(.nanosecond, i96)`, which holds it exactly with failure-free adapters.

Each scalar publishes the parameters it was made from: `Representation` on `int.Checked`, `Saturating` and `Ranged`, on every unit and on `id.Id`, `NonZero` and `Counter`; `minimum` and `maximum` on `Ranged`; `Domain` on `Count` and the ids; `Scale` on `Duration` and `Instant`, and `Clock` on `Instant`. Each also says what it is to generic code built on any copy of aegis, in one declaration, `aegis_scalar`: `.{ .contract = 1, .kind = .ranged, .representation = u16, .minimum = 1, .maximum = 4096 }`. `contract` is the version of this declaration; `kind` an enum literal, `.checked`, `.saturating` or `.ranged`, `.count`, `.bytes`, `.bits`, `.duration` or `.instant`, `.id`, `.nonzero` or `.counter`; `representation` the integer it is held in; then `minimum` and `maximum` for `.ranged`, `unit` for `.duration` and `.instant`, `clock` for `.instant`, and `domain` for `.count` and the ids. Contract 1 builds and reads each kind through its own checked functions only: `init` and `raw` for `.checked`, `.saturating` and `.ranged` (a `Ranged`'s `init` refusing what is out of range), `fromRaw` and `raw` for the units and `.id`, `.nonzero`'s `fromRaw` refusing zero, `.counter`'s `init` and `last`, and `parse`, `format` and `max_text_len` for the text of `.duration` and `.bytes`. Generic code recognizes an aegis type by this declaration, refuses a contract it does not know by its number, and never compares the type with one it rebuilds: a dependency pinning another aegis version builds another copy of aegis, whose `Ranged(u16, 1, 4096)` is never equal to this one's, while the declaration reads the same in both. A change to any of it is a new contract.


`assert.invariant`, `pre` and `post` fail-stop in every build with a static public message. Peer failures return errors. `debug` is optional and still evaluates its argument; `debugCheck` removes the predicate call in both release modes. `never(message)` returns `noreturn` and stops in every build, for the path that must not run where a value is needed (`else => assert.never("only files arrive")`, `x orelse assert.never("promised")`); Zig's `unreachable` is undefined behavior in ReleaseFast and ReleaseSmall, this is not. `maybe` accepts a side-effect-free possibility without asserting truth; `maybeCount` instruments caller-owned storage only in test builds. Contracts do not unwind cleanup on panic.

`handle.Domain` issues nonzero pool instances within a caller-supplied unique namespace. `Pool(T, Tag)` uses caller slot storage; `SlotMap` explicitly grows allocator-owned slots; `DenseSlotMap` adds contiguous iteration and swap removal. Keys retain namespace, instance, position and generation. Bounds, instance, occupancy and generation checks remain in every build. Generations never wrap: exhausted slots retire. `SecondaryMap(Key, V)` keeps full keys and requires the primary's liveness witness when resolving; stale associations remain owned until removed or pruned. Insert consumes the source only on success; remove transfers into uninitialized disjoint destination storage. Cleanup receives detached values, with no hidden lock. Growth and structural mutation end the documented borrows. `Index(Tag, Repr)` (also `typedIndex`) brands a position and validates the current slice at every access; it has `eql` and `compare` like the ids.

`input.Untrusted(T)` preserves a nonowning value or const pointer view. `parse(context, parser)` invokes a parser with an explicit named error union and distinct refined result. Parsing conveys no authentication, authorization or immutable ownership; borrowed results require the input to remain live and unchanged. The adapter adds no parser engine or implicit allocation.

`err.Context(Frame, N)` retains the first N public frames and marks truncation. `Failure(ErrorSet, Frame, N)` retains the original cause beside an inline context. Frame structs explicitly declare `pub const aegis_public_frame = true`; admitted fields are public booleans, integers, enums, nested admitted frames and `PublicText(N)`. Pointers, slices, owners, unknown aggregates and custom formatters are rejected. This is reviewed classification, not secret-flow proof. Default crypto frames contain no runtime text. Optional runtime text requires `PublicSource.classify(comptime reason, bytes)` and bounded escaping; callers must never classify secrets as public. Context formatting allocates nothing and preserves Writer errors.

## Scope

`aegis.secret` exposes `Choice`, `equal`, `equalBytes`, `compareUnsigned` and `OrderChoices`; choices offer logic, integer/byte selection and explicit `declassify(comptime reason)`. `Choice.audited` is true when the build is one of `secret.audited_profiles`, whose lowering `zig build check-choices` inspects. A choice's lowering is free of secret-dependent branches and loads; its time on the hardware is independent of the data only inside `secret.Timing` (`Timing.begin()`/`end`), where the processor has a data-independent mode: on AArch64 without FEAT_DIT set, a comparison's time depends on its operands (cloak's timing campaign). Public length and overlap validation remain enabled.

No implicit reference counting (`Shared` counts by explicit `retain` and `release`), protocol parsers, stored deleter vtables, hidden workers, automatic destructors or code analysis. Runtime closure is std only. Tags, checks and explicit raw boundaries are API discipline; Zig fields/reflection can bypass them. [Design](https://github.com/pedronaugusto/aegis/blob/main/docs/design.md) records the ownership and foreign-boundary contracts. [glint](https://github.com/pedronaugusto/glint)'s aegis pack checks these contracts at the call sites it resolves. Equal handwritten wipe/locking cost does not mean those operations have zero cost.

## Built with

aegis ships with no dependencies. [preflight](https://github.com/pedronaugusto/preflight) and [shakedown](https://github.com/pedronaugusto/shakedown) are dev dependencies, which [bay](https://github.com/pedronaugusto/bay) gives aegis's own development and a project that depends on aegis never sees.

## Testing

Development runs through bay. `bay test` runs the suite, the examples and `bay lint` (source, docs and structure); `bay test -Dtest-filter=A8` runs the cases whose names contain it, and `bay test-handles-input -Dtest-filter=A8 -Dtest-filter=A9` the A8/A9 cases alone. `bay check` compiles the suite and the examples; `bay bench` runs own-operation A/B by hand, and CI compiles the benchmark programs without timing them.

`bay contracts` runs the release contracts; hosted CI runs its three groups, `contracts-values`, `contracts-choices` and `contracts-published`, as separate jobs. `bay catalogue` checks that every public name, paired fixture, mode case, layout row and example belongs to one module, and prints the table above. `check-layouts` holds each module's layout against hand-written storage on the portable profiles in all four modes. `check-parity` and `check-handles-input` require paired release builds on x86-64 and AArch64 to emit the instructions of hand-written code, with volatile full-capacity erasure and lock ordering where they apply; `check-choices` audits the enclosing callers of the Choice kernels on the 20 audited profiles at three mitigation levels, and `check-choices-negative` the disclosure and support contracts. `check-modes` runs every deliberate violation in each mode and requires a stop exactly where the contract names one. The release tier runs the whole suite in ReleaseSafe and ReleaseFast under preflight's runner, beside Debug. `check-negative`, `check-a10` and `check-a12` require intended-reason compile rejections; `check-contracts` calls through the raw integer ABI; `check-secret-bytes`, `check-a67`, `check-a10` and `check-a12` compile the portable 32-bit, wasm and freestanding profiles. The A6 race cases use shakedown's portable baton-thread executor with deterministic seeded scheduling and virtual time; `test-native-races` contends natively and runs under TSan in the hosted merge. `bay artifacts` writes the layout of every profile and the instructions of every pair under `zig-out/artifacts`.

## Licence

MIT; see [LICENSE](LICENSE).
