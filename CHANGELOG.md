# Changelog

All notable changes are documented here, following Keep a Changelog 1.1.0.

## [Unreleased]

### Added

- A5 (work in progress): one-bit Choice, explicit verdict disclosure, byte equality, endian order and fixed-width selection with public length/overlap errors.
- Separate A5 caller/codegen, unsupported-profile/type, disclosure/format and native property tests; own manual paired benchmarks.
- Latest published green preflight/shakedown pins and preflight-generated CI.


- A3 checked, saturating and ranged integers, failing integer casts, distinct IDs and checked nonwrapping counters.
- Tagged counts, byte/bit conversions, durations and clock-tagged instants with explicit checked scaling, rounding, endian encoding and std.Io adapters.
- Always-on invariant/pre/post contracts, optional Debug predicates and test-only maybe coverage.
- Scalar contract properties, compile rejection fixtures, portable profile/layout checks, strict paired release codegen and own A/B benchmarks.
- Inline Secret(T) with full-region unconditional erasure, explicit exposure/transfer and fail-closed formatting.
- Guarded(T) with cloak's acquire/release spin semantics and explicit borrowed guards.

[Unreleased]: https://github.com/pedronaugusto/aegis/commits/main
