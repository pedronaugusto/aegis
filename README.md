# aegis

Explicit inline secret ownership and short spin-guarded data for Zig. Only `Secret(T)` and `Guarded(T)` are exported. Both are allocation-free; wiping and locking remain enabled in every build.

Work in progress. V0 acceptance requires hosted fast and merge on the exact candidate commit, including native macOS/Windows and Linux TSan; the wider safety catalogue and consumer adoption follow in separate batches.

## Install

Requires Zig 0.17.0. Main publishes the accepted v0 after its hosted gates pass:

```sh
zig fetch --save=aegis git+https://github.com/pedronaugusto/aegis#main
```

Add the dependency's `aegis` module to your build. Consumers fetch neither preflight nor shakedown.

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
```
<!-- END GENERATED -->

## Design

`Secret(T)` accepts fixed pointer-free representations and rejects aggregates declaring `deinit`. This checks representation, not the semantic meaning of numeric values; callers must use inline material that owns no external resource. `expose`/`exposeMut` borrow; `moveInto` transfers into uninitialized disjoint storage and securely wipes the source. `deinit` erases the whole representation, including padding, using volatile std erasure. The consumed storage need not be a valid `T`; never read it as `T` afterward. Parser/caller temporaries and displaced values need their own wipes. The direct formatting hook returns `SecretNotFormattable` without writing; std's `{f}` rejects that error set at compile time. Reflection, `{any}`, field access and deliberate exposure can bypass the hook.

`Guarded(T)` keeps data beside cloak's acquire/release atomic spin lock. `acquire`, immediate `defer held.deinit()`, and `held.value()` replace a separate lock/data pair. Published owners have stable addresses. Sections are bounded: no blocking, yielding, recursive acquisition or arbitrary callbacks. Acquisition is noncancelable with no fairness guarantee. The consumer owns data cleanup, reclamation and any escaped-pointer lifetime.

Zig permits struct copies, field access and escaped pointers. These contracts do not provide a borrow checker, linear types, automatic destructors or universal copied-guard detection. Cleanup is explicit on normal/error returns; abort/process death has no cleanup guarantee. Wipes cover only the specified storage, not old copies, registers, spills, paging, core dumps or hardware side channels. No constant-time cryptographic guarantee is supplied.

## Scope

No allocated secret buffers, reference counting, blocking locks, pools, handles, generic deleters or code analysis. Runtime closure is std only. [Extraction provenance](docs/extraction.md) distinguishes published cloak evidence from open consumer adoption gates. [Performance evidence](docs/performance.md) compares identical wipe/locking semantics: zero abstraction overhead does not mean those operations have zero cost.

## Built with

[preflight](https://github.com/pedronaugusto/preflight) is lazy build tooling; [shakedown](https://github.com/pedronaugusto/shakedown) is a lazy test-only dependency. The public module imports neither.

## Testing

Run targeted cases with `zig build test -Dtest-filter=Secret`, `-Dtest-filter=Guarded` or `-Dtest-filter=Consumer`. `zig build lint` checks source/docs/structure, negative compilation, consumer isolation and strict codegen parity. `zig build check` compiles the suite; `zig build bench` runs own-operation A/B manually. CI smoke-checks benchmark programs without timing gates. The hosted merge includes targeted Linux TSan; [validation status](docs/validation.md) records execution evidence.

## Licence

MIT; see [LICENSE](LICENSE).
