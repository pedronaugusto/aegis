# ABI and A4 results — 2026-10-08

Retained ABI correction 7b62798 and full-capacity SecretBytes d427c59 continue from 74a9a02. Owner db221e55f412007ae3474075d1f9851d96fbc94b approves C ABI types for 8–64-bit and usize/isize only. 128-bit representations remain Zig types, not promised C ABI types; every target remains required. The profile audits 505 scalar and 505 extern-record pairs per target. Historical 606-pair audits, 202 Windows mismatches and failing-before 32-bit struct lowering remain historical evidence.

[New profile proof and historical archive](https://github.com/pedronaugusto/trials/tree/27002a8e998eef0e28e472ec209c882a747ae226/aegis/a4/profile) record all nine targets with zero mismatches, separately linked native raw-integer execution, and local 24/24 steps with 33/33 targeted Debug tests. The run began at 9d69d13; production/ABI sources stayed unchanged during documentation cleanup. Full-wipe mutation/failure proofs and 37 equal-size/instruction pairs per x86_64/aarch64 Linux release configuration remain in [retained trials](https://github.com/pedronaugusto/trials/tree/21ab0854764f3738dc925bc5e88ac3372d738fd9/aegis/a4).

Native aarch64 ReleaseFast, 64 balanced interleaved ABBA/BAAB pairs, retained timing only. Every paired 95% interval includes 1.00; callbacks share their compiled entry, so no resolved abstraction slowdown remains. Earlier positive intervals were retained and attributed to temporal/scheduling effects in identical callbacks. This is handwritten full-wipe consumer parity, not adoption speedup or a paired comparison against previous main, which has no SecretBytes implementation. This profile-only continuation changes no runtime hot path and introduces no new timing campaign.

| Workload | Baseline/wrapper ns/op | Paired ratio 95% interval |
|---|---:|---:|
| 32-byte owner | 13.125/13.130 | 0.99865318–1.00169999 |
| 48-byte owner | 14.507/14.505 | 0.99808017–1.00095433 |
| 1056-byte extent | 35.079/35.075 | 0.99837658–1.00078288 |
| 32 live/256 capacity | 12.627/12.678 | 0.99751874–1.00227611 |
| shrink 48→8/256 | 17.274/17.275 | 0.99843849–1.00000243 |
| reserve 64→256/48 live | 24.549/24.573 | 0.99825434–1.00054136 |
| reserve OOM | 12.500/12.531 | 0.99997657–1.00354736 |
| parser error cleanup | 13.073/13.056 | 0.99888565–1.00039737 |
| move/cleanup | 14.134/14.138 | 0.99960216–1.00081463 |

Native x86 timing, real cloak/family adoption and workload performance remain open; timing/size misses do not gate landing. Full-capacity wiping, codegen, ownership, failure, portable and actual CI correctness remain gates. Landing requires exact-head FAST and MERGE success; immutable hosted run outcomes remain in [GitHub Actions](https://github.com/pedronaugusto/aegis/actions/workflows/ci.yml).
