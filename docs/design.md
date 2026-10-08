# Architecture

The public root reexports std-only safety concerns downward. Inline secret
ownership, spin-guarded data and scalar foundations preserve their existing
contracts and adjacent documentation. Runtime modules do not import build or
test tooling. Test roots explicitly import test support; shakedown is test-only.

## A5 value kernels (work in progress)

`constant_time.zig` owns `secret.Choice`, equality, unsigned ordering and select.
Its one-bit decisions are copyable; no ownership transfer or automatic erasure
is implied. Required public validation stays enabled; volatile full-length
loads and opaque register-mask barriers resist secret-dependent lowering.
[Contracts, compiler catalogue and limits](constant-time.md) define the checked
boundary. Tests and own benchmarks stay here; raw evidence lives in private
trials. Whole-program information flow and consumer adoption are separate work.

The default own-build target uses the audited baseline CPU. Instantiating a
Choice kernel outside the listed compiler/backend/CPU/OS/ABI/root options fails
explicitly. Final integration awaits genuinely landed A4 main and revalidation
of its repaired ABI and SecretBytes gates alongside A5.
