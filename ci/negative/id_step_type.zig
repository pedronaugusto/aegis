const a = @import("aegis");
const Tag = struct {
    pub const Step = u32;
};
export fn bad() usize {
    return @sizeOf(a.id.Id(Tag, u64).Step);
}
