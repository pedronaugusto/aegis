# Changelog

All notable changes are documented here, following Keep a Changelog 1.1.0.

## [Unreleased]

### Breaking

- Replace A3 scalar extern structs with non-exhaustive enum(Repr) values; factory APIs and checks stay the same. Reflective field construction/access no longer applies.

### Fixed

- Replace matching typed ABI prototypes with calls to separately compiled raw-integer exports. Retain the failing x86 hidden-return-pointer regression. The C ABI guarantee covers 8–64-bit and usize/isize representations on every configured target. 128-bit representations remain usable Zig types but are not promised C ABI types and are excluded from this ABI fixture/audit.

### Added
- A7 fixed arrays, queues/rings, explicit bounded buffers, finite limits/reservations and static nonblocking Owned/MustUse contracts.

- A4 SecretBytes: full-capacity byte ownership, explicit adoption/exposure/reserve/transfer, overlap-rejecting replacement, shrink erasure, zeroed growth and fail-closed formatting. All cleanup wipes full capacity before free, including slack; errors retain promised ownership and borrows. No remap, implicit growth or slice ownership escape API.
- Pre-free observing-allocator regressions, NoResize allocation-failure coverage, shrinking resize properties, portable/all-mode move contracts and paired enclosing dead-use erasure/codegen fixtures with a full-wipe handwritten baseline.

- A3 checked, saturating and ranged integers, failing integer casts, distinct IDs and checked nonwrapping counters.
- Tagged counts, byte/bit conversions, durations and clock-tagged instants with explicit checked scaling, rounding, endian encoding and std.Io adapters.
- Always-on invariant/pre/post contracts, optional Debug predicates and test-only maybe coverage.
- Scalar contract properties, compile rejection fixtures, portable profile/layout checks, strict paired release codegen and own A/B benchmarks.
- Inline Secret(T) with full-region unconditional erasure, explicit exposure/transfer and fail-closed formatting.
- Guarded(T) with cloak's acquire/release spin semantics and explicit borrowed guards.

[Unreleased]: https://github.com/pedronaugusto/aegis/commits/main
