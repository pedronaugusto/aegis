# Changelog

All notable changes are documented here, following Keep a Changelog 1.1.0.

## [Unreleased]

### Breaking

- Replace A3 scalar extern structs with non-exhaustive enum(Repr) values; factory APIs and checks stay the same. Reflective field construction/access no longer applies.

### Fixed

- Replace matching typed ABI prototypes with calls to separately compiled raw-integer exports. Retain the failing x86 hidden-return-pointer regression. The new gate exposes a remaining Zig 0.17 x86-64 Windows 128-bit enum return defect; this candidate cannot claim complete ABI interoperability or land until resolved.

### Added

- A3 checked, saturating and ranged integers, failing integer casts, distinct IDs and checked nonwrapping counters.
- Tagged counts, byte/bit conversions, durations and clock-tagged instants with explicit checked scaling, rounding, endian encoding and std.Io adapters.
- Always-on invariant/pre/post contracts, optional Debug predicates and test-only maybe coverage.
- Scalar contract properties, compile rejection fixtures, portable profile/layout checks, strict paired release codegen and own A/B benchmarks.
- Inline Secret(T) with full-region unconditional erasure, explicit exposure/transfer and fail-closed formatting.
- Guarded(T) with cloak's acquire/release spin semantics and explicit borrowed guards.

[Unreleased]: https://github.com/pedronaugusto/aegis/commits/main
