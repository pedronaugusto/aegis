//! secret.Timing's whole span, compiled for every architecture by `check-timing`: where the
//! processor has no data-independent timing mode the span is a no-op, and its AArch64
//! instructions must never reach another architecture's assembler.
const aegis = @import("aegis");

export fn aegisTimingSpan() bool {
    const timing = aegis.secret.Timing.begin();
    defer timing.end();
    return aegis.secret.Timing.active() == aegis.secret.Timing.supported();
}
