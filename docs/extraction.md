# C1 extraction and report reconciliation

Inspected 2026-10-08. This is aegis v0 extraction evidence, not independent security review or permission to adopt it in cloak. The original book design snapshot is `33495f5d324b904c6e8ebe33f6c54a970bb11303`. The complete refreshed catalogue was read at `f5cc108aa101a2065a27c252bab6426ea0d0537a`, `workspaces/tycho/missions/packages-released/designs/aegis.md`; its §3.1.1 Secret and §3.2.1 spin Guarded preserve v0, §4 retains the wiping/locking parity gate, and §5 preserves A0–A2 before future A3–A11. Safety §3/§6 remain binding. Book and active cloak were read only.

## Immutable inputs

| Input | Inspected commit | What it establishes |
|---|---|---|
| Original published cloak c1 | `d3d790f14211924ef974918cdfe2203b8e90ab62` | Actual forms and original reports; published, NOT LANDED. |
| Active cloak-c1b committed checkpoint | `6495d069fc3d683b3fe8c80dc22b12f4df539a35` | Floor ancestry reconciliation. Secret, Guarded, PrivateKey, Material, Budget and Job have no committed changes from the published input. |
| Current published C1 remediation | `3a66309c49ab024be4e2647c9c3da4550e740ac0` | Read exact committed source/notes; same extracted forms and consumer ownership, specific scalar-copy entry-path remediation, security closure still open. |
| preflight main | `9af905ed85cab6dbb19d9431c65ee3f41fbaa74d` | Current lazy build, consumer, source and hosted contracts. |
| shakedown main | `d5d19d39bc60cec59456aca947a3a7b484b87318` | Current lazy test-only gen/check and NoResize. Its reported merge `37768627963` is upstream evidence, not aegis acceptance. |
| aegis first main floor | `7e3962fc4e221734ba55ff43792483181ec3eac5` | Build/CI/LICENSE/README bootstrap only; default main verified, visibility PRIVATE. |

No cloak pin or adoption changed. The first remediation survey was read-only working-tree inspection at 6495d06; during this batch the owner published c1 at 3a66309. Its exact immutable source and final notes were re-read, and the actual Material compile-only comparison also passes at that checkpoint. Remediation is published, NOT LANDED or independently closed. The current committed source-content SHA-256 fingerprints are:

| File at 3a66309 | SHA-256 |
|---|---|
| src/credentials/Curve.zig | `85439b65a2c7a192e63067b666c1fa2c87dcacde78ae4202f9d0fe113c0b0915` |
| src/credentials/Key.zig | `85442dc4189893f17a4045b7a3e744af25a55588d379e2e752110e4a3ce74736` |
| src/credentials/EdKey.zig | `fcf0a798d0365e0bfdd279dece0aa073aac46fbbe3616d5d3a7ecc4dc7a6cfc2` |
| docs/internal/C1-review.md | `e88d0871493a63dcac6b298b35b5ca71a5b7f26117a65d891a47ab2ca5c70b8a` |
| docs/internal/C1-primitives.md | `af38138c45868ecf85260a5c9b01a1c4ca75493093f59a3772a5e96b6766804b` |

The original source links below identify the extraction input; current remediation links identify the later immutable checkpoint. Publication is not independent review or security acceptance.

## Actual forms and consumers

[Secret](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/credentials/Secret.zig) owns one inline T; std secureZero wipes its representation; the formatting hook refuses content. [PrivateKey](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/credentials/PrivateKey.zig) stages parsed material, retains it in a reference-counted State, and wipes before last-release destruction. Parsing buffers, staging copies, KDF and private primitive temporaries are separate owners. Aegis extracts the inline operation; it supplies no refcount, parser or crypto.

[Material](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/credentials/Key.zig) is the RSA/P256/P384/Ed25519 tagged union. [Rsa.Key](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/credentials/Rsa.zig) contains n[512], e[8], d[512], size and exponent_size. Curve keypairs are the actual installed std types. The minimal test-only declaration in [Material.zig](../src/testing/Material.zig) copies these declarations only. A compile-only comparison against the complete immutable published source checked union field names, every variant's size/alignment, exact curve type identity, RSA field types/offsets, and successful Secret(actual Material) instantiation. Material is 1,056 bytes, alignment 8 on the inspected 64-bit targets. No cloak runtime dependency or crypto implementation was vendored.

[Guarded](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/services/Guarded.zig) is one atomic bool beside T, weak CAS acquire/monotonic failure with spin hints, pointer guard, and release store. [Budget](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/services/Budget.zig) reserves/releases bounded counts under that guard. [Job](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/services/Job.zig) retains completion state independently of a connection, drops the lock for native evaluation, and keeps abandoned work charged until executor reaping. The aegis consumer fixture models only these charge/phase/result boundaries, including run/abandon/take races; it does not execute native trust or prove OS policy.

Job's abandon, discarded-result and final teardown paths can call Path.deinit while held; take computes the request digest while held. Allocator cleanup and input-scaled digest work have not been established as bounded nonblocking spin sections. Cloak adoption must detach cleanup outside the section or establish the required bounds in its own authorized batch. Aegis adds no alternative lock backend and changes no Job source. Lookout callback/overflow migration and its TSan remain later W1 adoption work, not a v0 admission requirement.

## Reports reconciled, limits retained

The owner/nav relay identifies the original ship3/task1 and ship4/task2 durable results (nodes3/4), rather than unrelated task IDs3/4. Read the complete published [C1-review](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/docs/internal/C1-review.md), [C1-interfaces](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/docs/internal/C1-interfaces.md), [C1-performance](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/docs/internal/C1-performance.md), and [verification evidence](https://github.com/pedronaugusto/cloak/blob/d3d790f14211924ef974918cdfe2203b8e90ab62/src/verify/fixtures/evidence.txt), plus the current [review](https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/docs/internal/C1-review.md), [primitive evidence](https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/docs/internal/C1-primitives.md), [assembly record](https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/docs/internal/C1-curve-assembly.txt), failure ledger and performance notes. The relay is provenance, not an independent review.

The reports establish their historical claims: published c1 remained NOT LANDED; verification's assigned paths were released; 80 focused tests passed in both release modes; both builders matched 9,802 Limbo cases; 6,955 Wycheproof vectors had zero mismatches. The 19,562 certificate and 10,355 revocation fuzz executions are SMOKE, before final scratch/admission changes. The common heap sample was 7,165 bytes and receipt 941 bytes. None proves 24 CPU-hour campaigns, full coverage, total/worst/default-cap stack plus heap, native all-platform behavior, private-kernel constant time or erasure, or independent final-code closure. C2/C0 shared integration files and admission/lifetime duties remain as C1-interfaces specifies.

The installed std source confirms the reported scalar copies: Edwards25519.clampedMul copies s to local t; P256/P384.mul copies/endian-swaps s_; ECDSA.fromSecretKey calls that mul by value. Those locals have no corresponding wipes. Installed source SHA-256 pins are Edwards25519 `1b3bb241dc6bc275a7558e1983a9311f307d494a1f70ad94751fad2bd7aba988`, P256 `b45d8e9026c21f4f05a41c364e57bd1b174e72ed42165959b05ccaa7183ae727`, P384 `e76b5ff2b137ceb913fc5c61d815e05db9dbc49c0d465b80ea5c52a74ff6e2e4`. Caller wiping does not erase those callee copies.

At 3a66309, [Curve.base](https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/src/credentials/Curve.zig) reads borrowed scalars, scans public tables and wipes named scratch; [Key](https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/src/credentials/Key.zig) uses it for P-curves, and [EdKey](https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/src/credentials/EdKey.zig) clamps its owned expansion before calling it. This bypasses the specific std scalar-copy entry paths. It does not erase every Point return/by-value callee temporary or spill. Current notes explicitly report secret-derived x86 field carry/reduction branches and uncovered point/spill copies, retaining F03/F04/F06/F93 and independent-review gates. Aegis's storage wipe is neither remediation nor certification of those kernels.

## Deliberate extraction changes

Secret adds recursive pointer/resource-shape rejection, explicit pointer exposure and representation transfer into disjoint uninitialized storage. It wipes the entire region, including padding, without a following undefined assignment: Zig Debug would otherwise poison the bytes just wiped. Consumption is semantic; callers must end borrows, avoid copies and clean displaced values. Guard release likewise consumes the capability by contract without adding diagnostic state. There is no promised borrow checker, destructor or general stale/copy detection.

The named SecretNotFormattable error is preserved. Zig 0.17 Writer `{f}` accepts only its WriteFailed error set, so that use fails compilation; the direct hook test proves the named error and zero output. Reflection `{any}` bypasses it, as do deliberate exposure and raw fields. Neither is presented as compiler-enforced secrecy.

The current C1 ledger adds catalogue regressions and updated smoke counts; their duration/security/resource limits remain explicit. Its 12-target checks are compile evidence, and the Windows test early returns on macOS are not native Windows execution. The later source does not turn the original reports into aegis acceptance proof.

The original design's baseline and visibility questions are resolved by owner instructions: equivalent hand-written locking/wiping is the release baseline; the repo remains PRIVATE. The refreshed §6 original-report gap is reconciled above for A0 extraction, while C1 security and spin-site adoption gates remain open. V0 branch implementation, local tests and measured parity/timing now have evidence in this repository; later catalogue API/cost/constant-time/ownership claims remain proposed gates, not measured evidence. Main remains the floor until hosted acceptance. No book change was made and no A3–A11 work or cloak adoption is included.
