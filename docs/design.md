# Design

Aegis supplies explicit safety types for any Zig project. Runtime code depends only on std. Shakedown is test-only; preflight owns the build and CI gate. Modules import representation kernels downward, never consumers or tooling. Numeric values are copyable; secrets and guards have one semantic owner. Zig copying, reflection and escaped pointers remain caller bypasses, so these types do not claim compiler-enforced linearity or a borrow checker.

## Secrets and ownership

`Secret(T)` holds a fixed pointer-free representation inline, including padding. Shape validation rejects pointers and aggregates declaring cleanup. Explicit exposure borrows storage; cleanup and transfer use unconditional volatile std erasure over the entire representation in all modes. Transfer requires uninitialized, disjoint destination storage. Never read consumed storage as T. Caller temporaries, displaced values and escaped copies require their own authorized wipes.

`SecretBytes` stores exactly allocator, full allocation slice and live length. Its layout matches the handwritten full-wipe owner. Initialization zeros full capacity. Adoption validates length before transfer and accepts undefined slack without reading it; the caller supplies a genuine exclusive allocation with allocator-compatible byte alignment. Exposure borrows only the live prefix.

Shrinking securely erases the removed tail; growth zeros newly live bytes. Replacement rejects over-capacity input and any backing-storage overlap before mutation, wipes displaced live data and copies disjoint input. Reserve explicitly allocates, zeros new capacity, copies live bytes, securely erases the entire old capacity, frees and then publishes the replacement. It never resizes/remaps implicitly. OOM preserves ownership, content and existing borrows; successful reserve ends old borrows. Move transfers the descriptor without allocation or backing-byte copies and consumes its source. Both descriptors remain outside backing storage.

Cleanup wipes full capacity before rawFree with the exact extent and alignment, so a lawful pre-free observing allocator sees erased bytes before Debug allocator poison. Consumed descriptors are invalidated without reading them again. Formatting fails before writing. Errors use explicit defer/errdefer cleanup; panic, abort and process death provide no automatic cleanup. Wiping does not promise to erase older compiler copies, registers, paging or core dumps.

Costs are O(capacity) initialization/cleanup, O(removed tail) shrink, O(new live bytes) growth, O(old live + new live) replacement, O(new capacity + live + old capacity) reserve and constant-size descriptor transfer. There are no hidden backing copies, reference counts or extra release fields.

## Guarded data

`Guarded(T)` keeps data beside an acquire/release spin lock. Published owners have stable addresses. Acquire produces an explicit borrowed guard; defer its cleanup immediately. Critical sections are bounded and contain no blocking, yielding, recursive acquisition or arbitrary callbacks. Acquisition is noncancelable and has no fairness guarantee. The consumer owns data cleanup, reclamation and escaped-pointer lifetime. Locks remain in release builds.

## Scalars and foreign boundaries

IDs, NonZero, Counter, Count, Bytes, Bits, Duration, Instant and Ranged use non-exhaustive enum(Repr) storage. Tags, scales and bounds occupy no bytes; scalar size/alignment matches Repr. A one-field extern struct was rejected because equal layout does not imply the integer calling convention: 32-bit x86 can return structs through memory. The C ABI guarantee covers signed/unsigned 8–64-bit and usize/isize representations on every configured target. 128-bit reprs remain usable Zig types with the same factory, arithmetic and encoding APIs, but are NOT promised C ABI types. MSVC has no 128-bit integer and Zig 0.17 lowers enum(u128)/enum(i128) returns differently from raw integers on x86-64 Windows. Only those widths are excluded from the ABI fixture; no target is excluded.

Identity import is explicit and does not establish authenticity or uniqueness. NonZero rejects zero. Counter exhausts without wrapping or mutating on failure and requires external serialization. Counts and durations use checked arithmetic. Conversions check scaling, sign and range in every mode; down rounds toward negative infinity, up toward positive infinity, exact rejects remainders. Instants combine only with matching clock/domain durations; changing clocks requires a sampled correspondence. Wait boundaries retain std.Io.Timeout. Endian encoding reads/writes exact repr bytes, never copies ABI storage. Foreign callers honor nonzero/range contracts or validate returns through checked import.

Checked and Saturating retain arbitrary nonzero integer widths. Division by zero and invalid shifts fail even in saturating operations. Signed division truncates toward zero; min/-1 remainder is zero. Ranged checks inclusive bounds. Integer casts reject sign/narrowing loss. Arithmetic and conversion checks remain enabled in release modes; there is no allocation or indirect dispatch in scalar kernels.

## Executable contracts and evidence

Invariant, pre and post fail-stop with static public messages in every build. Peer errors return named errors. debugCheck omits its predicate in release modes; maybe is not a truth assertion and test-only counting uses caller-owned storage. Fail-stop does not unwind cleanup.

The ABI test calls separately compiled raw-integer exports through both typed and raw declarations, using two runtime arguments and consuming returns. It checks extern-record size/alignment/offsets and raw field access. All configured targets plus 32-bit x86 and wasm are required; cross codegen is distinguished from separately linked native execution. Matching typed prototypes are never interoperability proof. Zig-only 128-bit factory/extreme/encoding tests remain active.

Required SecretBytes checks observe valid allocations before free, cover undefined/nonzero slack, all overlap directions, shrink/regrow, OOM and borrow preservation, NoResize allocation failures, generated live-set properties, explicit move rejection in every execution mode and portable profiles. Paired enclosing release consumers require equal symbol sizes/instructions and volatile full-capacity erasure, including adopted dead-use and error cleanup. Deliberately broken wipes must be rejected by the observer; production is never changed to that mutant. Secret formatting has an intended-reason compile rejection.

Own benchmarks live in bench and CI compiles them without timing gates. Correctness and deterministic checks gate landing. Timing is paired and interleaved with ratios and spread; performance misses remain open objectives. Raw logs, IR, timings and historical defects live in private trials, with immutable citations in the dated results note. Cloak/family adoption, constant-time values and the rest of the planned safety catalogue are later work.
