# v0 validation and hosted status

Local evidence, 2026-10-08, Zig 0.17.0 / Apple M3 Max / Darwin 25.2.0. The retained local results below precede the resume. Hosted acceptance requires fast and merge on the exact final candidate commit, including Linux TSan and native macOS/Windows execution; earlier-commit runs are not acceptance.

## Focused checks

| Selection | Debug | ReleaseSafe | ReleaseFast |
|---|---:|---:|---:|
| `zig build test -Dtest-filter=Secret` | 7/7 | 7/7 | 7/7 |
| `zig build test -Dtest-filter=Guarded` | 5/5 | 5/5 | 5/5 |
| `zig build test -Dtest-filter=Consumer` | 7/7 | 7/7 | 7/7 |

Commands additionally select `-Doptimize=safe` / `fast`, and `-Dci-lint=false` after the separate mandatory lint. Each row includes the three anonymous import/root test blocks, so the counts must not be summed as unique tests. The ten substantive cases cover full-region/padding wipes, representation transfer, explicit exposure, zero-output formatting, guard error/early release and reacquisition, native 2/8-worker exclusion/publication, shakedown Material transfer (512 cases, seed 0xae615), Budget conservation/caps (256, seed 0xb0d6e7), every construction allocation failure plus post-publication error, and 32 native Job run/abandon/take races with late-reap charge conservation. This is a model of the named consumer boundaries, not cloak native/security acceptance.

Final Consumer runner seeds: Debug 3229692198, ReleaseSafe 960450737, ReleaseFast 1765974378. Allocation observation is before destruction: the slice uses rawFree because std Allocator.free poisons before invoking its vtable in Debug. Every free observes all-zero bytes and each successful allocation has exactly one free. Lexical acquisition scopes end error defers at publication; later errors run only the final live owner's defer.

`zig build lint` passes format, gantry production layers/entries and std-only closure, source quality/ziglint, namespace/cast/function/docs/test-import/package-path rules, isolated consumer compilation with fetching off, eight unsupported-shape fixtures plus rejected std formatting, and the four-way strict parity gate. The public module has only Secret/Guarded and std; preflight/shakedown remain lazy and outside the runtime graph. By-path consumers return before own-tree tooling and fetch neither.

`zig build check` passes Debug; `zig build check -Doptimize=small` passes ReleaseSmall compilation. The generated Windows Debug portable path `zig build ci-build -Dtarget=x86_64-windows-gnu -Dci-lint=false` compiled tests, usage example and benchmark smoke binary, and exported their three-command manifest; this is compilation, not Windows execution. Native macOS targeted tests executed. No manual unfiltered whole-suite run was used.

[Performance evidence](performance.md) records four strict codegen objects, dead-storage consumer cleanup, actual Material representation comparison and both final 32-pair timing replicates. All erasure/locking operations remain in both release modes; no timing gate is placed on shared CI.

## Hosted gate

The workflow's fast/merge/release matrices come from pinned preflight `zig build plan`; merge uses Linux Debug plus Linux-produced portable macOS/Windows artifacts. A separate merge/release job runs the targeted native Guarded/Job cases under Linux TSan. The generated release tier also has preflight's full sanitizer and cross-compile rows. None has been waived.

The floor's automatic [run 37773839032](https://github.com/pedronaugusto/aegis/actions/runs/37773839032), commit `7e3962fc4e221734ba55ff43792483181ec3eac5`, did not start its main-status job. [Check 113299684373](https://github.com/pedronaugusto/aegis/actions/runs/37773839032/job/113299684373) has no steps; its failure annotation says account payments failed or the spending limit must be increased. That is an owner/nav billing blocker, not test execution or permission to bypass CI. The explicit v0 fast dispatch [run 37781886548](https://github.com/pedronaugusto/aegis/actions/runs/37781886548), source candidate `1a82a5030aa0771031475dff476e92c9266f9c42`, failed before any steps: [check 113326792651](https://github.com/pedronaugusto/aegis/actions/runs/37781886548/job/113326792651) has an empty step list and the same billing annotation. The gate and TSan jobs were skipped. Merge was not dispatched because fast never passed. This documentation follow-up changes no implementation, tests, benchmark or parity fixture; the final branch head still needs exact-commit hosted acceptance.

## Resume and exact-head acceptance

The owner cleared hosted billing and authorized resuming v0 from `5386bf0dde3da330105b81c8729eb01284141e57`. Remote main/default main were verified at the existing `7e3962fc4e221734ba55ff43792483181ec3eac5` floor. The repository is now PUBLIC by owner action; the resume changes no visibility or settings. The billing failures above remain historical failures, not current test evidence.

The fresh standalone resume preserves published ancestry and the two-type scope. Before dispatch, it rechecks targeted Secret/Guarded/Consumer cases in Debug, ReleaseSafe and ReleaseFast, lint (including nine compile-negative fixtures and four strict parity objects), and check. Retained codegen and raw timing artifacts remain unchanged. No library hot path changed, so historical timing is reported as retained evidence rather than a new measurement.

For hosted evidence, inspect this commit's workflow-dispatch runs in the [CI history](https://github.com/pedronaugusto/aegis/actions/workflows/ci.yml): fast first, then merge, both with `headSha` equal to the final v0 head. Merge must execute native macOS/Windows artifacts and the separate Linux targeted TSan job successfully. No skipped job or billing failure substitutes for those gates. Run IDs and the actual remote branch/main SHA are reported by the landing operation after inspection. This candidate document does not predeclare their outcomes.

Fast-forward main only after both gates pass; re-read remote heads and preserve concurrent upstream work without force or history rewriting. Cancel the automatic main push/status run after landing. No cloak adoption or pin change is included; its separate [open gates](extraction.md) remain open. The wider package remains work in progress.
