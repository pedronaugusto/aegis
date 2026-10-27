//! Units as text, and the parameters every scalar publishes: the grammar `Duration.parse` and `Bytes.parse`
//! read, the canonical form `format` writes, and how a generic consumer recognizes each scalar by its declarations.
const std = @import("std");
const shake = @import("shakedown");
const a = @import("../root.zig");
const U = a.units;
const t = std.testing;

fn expectText(value: anytype, want: []const u8) !void {
    var buffer: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try value.format(&w);
    try t.expectEqualStrings(want, w.buffered());
}

fn expectRead(comptime T: type, text: []const u8, raw: T.Representation, canonical: []const u8) !void {
    const value = T.parse(text) catch |err| {
        std.debug.print("'{s}' as {s}: {t}\n", .{ text, @typeName(T), err });
        return err;
    };
    try t.expectEqual(raw, value.raw());
    try expectText(value, canonical);
}

fn expectRefused(comptime T: type, err: T.ParseError, texts: []const []const u8) !void {
    for (texts) |text| t.expectError(err, T.parse(text)) catch |failed| {
        std.debug.print("'{s}' as {s}\n", .{ text, @typeName(T) });
        return failed;
    };
}

test "A3 a duration reads the components people write and writes the canonical form" {
    const Ms = U.Duration(.millisecond, u64);
    try expectRead(Ms, "30s", 30_000, "30s");
    try expectRead(Ms, "1m30s", 90_000, "1m30s");
    try expectRead(Ms, "250ms", 250, "250ms");
    try expectRead(Ms, "1.5h", 5_400_000, "1h30m");
    try expectRead(Ms, "90m", 5_400_000, "1h30m");
    try expectRead(Ms, "0", 0, "0s");
    try expectRead(Ms, "0s", 0, "0s");
    try expectRead(Ms, "-0", 0, "0s");
    try expectRead(Ms, "2d12h", 216_000_000, "2d12h");
    try expectRead(Ms, "36h", 129_600_000, "1d12h");
    try expectRead(Ms, "1.25s", 1_250, "1s250ms");
    try expectRead(Ms, "1500000us", 1_500, "1s500ms");
    try expectRead(Ms, "1500000\u{b5}s", 1_500, "1s500ms");
    try expectRead(Ms, "1500000\u{3bc}s", 1_500, "1s500ms");
    try expectRead(Ms, "0.001s", 1, "1ms");
    try expectRead(Ms, "1h0m5s", 3_605_000, "1h5s");
    try expectRead(Ms, "007s", 7_000, "7s");
    try expectRead(Ms, "1d1h1m1s1ms1000us1000000ns", 90_061_003, "1d1h1m1s3ms");
    try expectRead(Ms, "18446744073709551615ms", std.math.maxInt(u64), "213503982334d14h25m51s615ms");
    const Ns = U.Duration(.nanosecond, i64);
    try expectRead(Ns, "0.000000001s", 1, "1ns");
    try expectRead(Ns, "1.000000000000000000000000000000s", 1_000_000_000, "1s");
    try expectRead(Ns, "-1m30.5s", -90_500_000_000, "-1m30s500ms");
    try expectRead(Ns, "1.5us", 1_500, "1us500ns");
    const Small = U.Duration(.second, i8);
    try expectRead(Small, "-2m8s", -128, "-2m8s");
    try expectRead(Small, "127s", 127, "2m7s");
    const Days = U.Duration(.day, u16);
    try expectRefused(Days, error.Inexact, &.{ "1.5d", "1h" });
    try expectRead(Days, "48h", 2, "2d");
}

test "A3 a duration's text is exact: finer than the unit, beyond the representation or malformed is an error" {
    const Ms = U.Duration(.millisecond, u64);
    try expectRefused(Ms, error.Inexact, &.{ "1.5ms", "1500us", "1ns", "0.0001s", "1s1ns" });
    try expectRefused(Ms, error.Overflow, &.{ "-1s", "-1ms", "300000000000d", "18446744073709551616ms", "99999999999999999999999999999999999999999999999h" });
    try expectRefused(Ms, error.Malformed, &.{
        "",      "-",   "s",   "1",     "30",   "1.s",  ".5s",     "1s1s",    "30s1m", "1ms1s",  "1m 30s", " 1s",
        "1s ",   "+1s", "1S",  "1sec",  "1min", "1x",   "1_000ms", "--1s",    "1-s",   "1.5.5s", "1e3ms",  "0x10s",
        "1h-1m", "00",  "-00", "1d 1h", "1hh",  "1m1m", "\u{b5}s", "1\u{b5}", "s1",
    });
    const Small = U.Duration(.second, i8);
    try expectRefused(Small, error.Overflow, &.{ "128s", "-129s", "3m", "-3m" });
    try expectRefused(Small, error.Inexact, &.{ "0.5s", "1ms", "-1s1ms" });
    const Ns = U.Duration(.nanosecond, i64);
    try expectRefused(Ns, error.Inexact, &.{ "0.0000000001s", "1.0000000001s", "0.5ns" });
}

test "A3 a size names its unit binary or decimal, exactly as written, and writes the largest that divides it" {
    const B = U.Bytes(u64);
    try expectRead(B, "4096", 4096, "4KiB");
    try expectRead(B, "4096B", 4096, "4KiB");
    try expectRead(B, "64MiB", 64 << 20, "64MiB");
    try expectRead(B, "1.5GB", 1_500_000_000, "1500MB");
    try expectRead(B, "1.5GiB", 3 << 29, "1536MiB");
    try expectRead(B, "1kB", 1000, "1kB");
    try expectRead(B, "1KiB", 1024, "1KiB");
    try expectRead(B, "1000KiB", 1_024_000, "1000KiB");
    try expectRead(B, "0", 0, "0B");
    try expectRead(B, "0.5KiB", 512, "512B");
    try expectRead(B, "1500", 1500, "1500B");
    try expectRead(B, "1500000", 1_500_000, "1500kB");
    try expectRead(B, "1.000GB", 1_000_000_000, "1GB");
    try expectRead(B, "15EiB", 15 << 60, "15EiB");
    try expectRead(B, "18446744073709551615", std.math.maxInt(u64), "18446744073709551615B");
    try expectRefused(B, error.Malformed, &.{ "", "B", "KiB", "1KB", "1kb", "1kiB", "1 MiB", "1MiBs", "1.KiB", ".5KiB", "-", "1Ki", "1b", "+1B", "1_000", "1e3", "0x10", "1kB1B", "1mB", "1\u{b5}B" });
    try expectRefused(B, error.Inexact, &.{ "0.1KiB", "1.5B", "0.0001kB", "1.5" });
    try expectRefused(B, error.Overflow, &.{ "16EiB", "18446744073709551616", "-1B", "-1", "1YB", "1ZiB" });
    const Signed = U.Bytes(i16);
    try expectRead(Signed, "-32KiB", -32768, "-32KiB");
    try expectRead(Signed, "-1", -1, "-1B");
    try expectRefused(Signed, error.Overflow, &.{ "32KiB", "-32769" });
    const Wide = U.Bytes(u128);
    try expectRead(Wide, "1YiB", 1 << 80, "1YiB");
    try expectRead(Wide, "2.5YB", 2_500_000_000_000_000_000_000_000, "2500ZB");
}

/// Each duration and size type the properties run over: every unit, signed and unsigned, narrow to 128 bits.
const spans = .{
    U.Duration(.nanosecond, i64),  U.Duration(.nanosecond, i96),  U.Duration(.nanosecond, i128),
    U.Duration(.microsecond, u32), U.Duration(.millisecond, u64), U.Duration(.second, i32),
    U.Duration(.minute, u16),      U.Duration(.hour, i8),         U.Duration(.day, u128),
    U.Duration(.day, i24),
};
const sizes = .{ U.Bytes(u8), U.Bytes(i16), U.Bytes(u32), U.Bytes(i64), U.Bytes(u64), U.Bytes(u128), U.Bytes(i128) };

fn backAgain(comptime T: type, value: T) !void {
    // A buffer of exactly `max_text_len` holds every value's text.
    var buffer: [T.max_text_len]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try value.format(&w);
    const read = T.parse(w.buffered()) catch |err| {
        std.debug.print("{s} {d}: '{s}' gives {t}\n", .{ @typeName(T), value.raw(), w.buffered(), err });
        return err;
    };
    try t.expect(read.eql(value));
}

/// A whole multiple of one of the size units, where it fits, so that every unit is chosen and written.
fn sizeOf(comptime T: type, s: *shake.Source) T {
    const R = T.Representation;
    const raw = shake.gen.int(s, R);
    if (shake.gen.boolean(s)) return .fromRaw(raw);
    const scales = [_]u128{ 1 << 80, 1_000_000_000_000_000_000_000_000, 1 << 60, 1_000_000_000_000_000_000, 1 << 30, 1_000_000_000, 1 << 20, 1_000_000, 1 << 10, 1_000 };
    const scale = std.math.cast(R, shake.gen.oneOf(s, u128, &scales)) orelse return .fromRaw(raw);
    const small = shake.gen.int(s, i8);
    return .fromRaw(std.math.mul(R, std.math.cast(R, small) orelse 0, scale) catch raw);
}

fn roundTrip(_: void, c: *shake.Case) !void {
    inline for (spans) |T| try backAgain(T, .fromRaw(shake.gen.int(c.source, T.Representation)));
    inline for (sizes) |T| try backAgain(T, sizeOf(T, c.source));
}

test "A3 max_text_len bounds the text format writes, so a buffer of it holds any value" {
    // `-`, 106751991167300 days (2^63 seconds), and at most 23h59m59s below them.
    try t.expectEqual(@as(usize, 1 + 15 + 1 + 9), U.Duration(.second, i64).max_text_len);
    // 20 digits and the longest unit.
    try t.expectEqual(@as(usize, 1 + 20 + 3), U.Bytes(u64).max_text_len);
}

test "A3 parse reads back what format writes, for every unit and width" {
    inline for (spans ++ sizes) |T| {
        const R = T.Representation;
        for ([_]R{ std.math.minInt(R), std.math.maxInt(R), 0, 1, std.math.maxInt(R) - 1 }) |raw| try backAgain(T, .fromRaw(raw));
    }
    try shake.check(t.allocator, {}, roundTrip, .{ .cases = 2048, .seed = 0x7e47 });
}

const Text = struct {
    buffer: [512]u8 = undefined,
    len: usize = 0,
    fn add(text: *Text, comptime fmt: []const u8, args: anytype) !void {
        var w: std.Io.Writer = .fixed(text.buffer[text.len..]);
        try w.print(fmt, args);
        text.len += w.end;
    }
    fn slice(text: *const Text) []const u8 {
        return text.buffer[0..text.len];
    }
};

/// A decimal number with up to `max_digits` fraction digits, written into `text`; its exact value times
/// `scale`, or null where that leaves part of one.
fn number(s: *shake.Source, text: *Text, scale: u256, max_digits: u8) !?u256 {
    const whole = shake.gen.intRange(s, u64, 0, 1_000_000);
    try text.add("{d}", .{whole});
    const places = shake.gen.intRange(s, u8, 0, max_digits);
    if (places == 0) return whole * scale;
    try text.add(".", .{});
    var fraction: u256 = 0;
    for (0..places) |_| {
        const digit = shake.gen.intRange(s, u8, 0, 9);
        try text.add("{d}", .{digit});
        fraction = fraction * 10 + digit;
    }
    const tenths = std.math.pow(u256, 10, places);
    if ((fraction * scale) % tenths != 0) return null;
    return whole * scale + fraction * scale / tenths;
}

fn spanOracle(_: void, c: *shake.Case) !void {
    const units = [_]struct { a.units.Unit, []const u8 }{ .{ .day, "d" }, .{ .hour, "h" }, .{ .minute, "m" }, .{ .second, "s" }, .{ .millisecond, "ms" }, .{ .microsecond, "us" }, .{ .nanosecond, "ns" } };
    var text: Text = .{};
    const negative = shake.gen.boolean(c.source);
    if (negative) try text.add("-", .{});
    var total: ?u256 = 0;
    var any = false;
    for (units) |unit| {
        if (!shake.gen.boolean(c.source)) continue;
        any = true;
        const part = try number(c.source, &text, unit[0].nanoseconds(), 12);
        try text.add("{s}", .{unit[1]});
        total = if (total != null and part != null) total.? + part.? else null;
    }
    if (!any) return;
    c.note("'{s}'", .{text.slice()});
    const T = U.Duration(.nanosecond, i128);
    const want = total orelse return t.expectError(error.Inexact, T.parse(text.slice()));
    const signed: i256 = if (negative) -@as(i256, @intCast(want)) else @intCast(want);
    try t.expectEqual(signed, (try T.parse(text.slice())).raw());
    // The same text in whole milliseconds: exact where the nanoseconds are whole milliseconds.
    const Ms = U.Duration(.millisecond, i128);
    if (want % 1_000_000 != 0) return t.expectError(error.Inexact, Ms.parse(text.slice()));
    try t.expectEqual(@divExact(signed, 1_000_000), (try Ms.parse(text.slice())).raw());
}

const SizeUnit = struct { u256, []const u8 };

fn sizeOracle(_: void, c: *shake.Case) !void {
    const units = [_]SizeUnit{ .{ 1, "" }, .{ 1, "B" }, .{ 1000, "kB" }, .{ 1 << 10, "KiB" }, .{ 1_000_000, "MB" }, .{ 1 << 20, "MiB" }, .{ 1 << 40, "TiB" }, .{ 1_000_000_000_000_000, "PB" }, .{ 1 << 80, "YiB" }, .{ 1_000_000_000_000_000_000_000_000, "YB" } };
    const unit = shake.gen.oneOf(c.source, SizeUnit, &units);
    var text: Text = .{};
    const want = try number(c.source, &text, unit[0], 24);
    try text.add("{s}", .{unit[1]});
    c.note("'{s}'", .{text.slice()});
    const T = U.Bytes(u128);
    const exact = want orelse return t.expectError(error.Inexact, T.parse(text.slice()));
    if (exact > std.math.maxInt(u128)) return t.expectError(error.Overflow, T.parse(text.slice()));
    try t.expectEqual(@as(u128, @intCast(exact)), (try T.parse(text.slice())).raw());
}

test "A3 parse agrees with an exact oracle on generated components, fractions and units" {
    try shake.check(t.allocator, {}, spanOracle, .{ .cases = 2048, .seed = 0x5a4 });
    try shake.check(t.allocator, {}, sizeOracle, .{ .cases = 2048, .seed = 0x512e });
}

/// Which aegis scalar `T` is, found the way a generic consumer finds it: by the `aegis_scalar` declaration
/// it carries, at the one contract this reader knows, never by its name or by rebuilding it, so a type made
/// by another copy of aegis (a dependency pinning another version) is recognized alike.
const Kind = enum { checked, saturating, ranged, count, bytes, bits, duration, instant, id, nonzero, counter, other };

fn kindOf(comptime T: type) Kind {
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => {},
        else => return .other,
    }
    if (!@hasDecl(T, "aegis_scalar")) return .other;
    const scalar = T.aegis_scalar;
    if (@typeInfo(@TypeOf(scalar)) != .@"struct" or !@hasField(@TypeOf(scalar), "contract") or scalar.contract != 1) return .other;
    const name = @tagName(scalar.kind);
    return if (@hasField(Kind, name)) @field(Kind, name) else .other;
}

test "A3 every scalar publishes the parameters it was made from and which scalar it is, as another copy of aegis reads it" {
    const Tag = struct {};
    const Jobs = a.int.Ranged(u16, 1, 256);
    comptime std.debug.assert(Jobs.Representation == u16);
    comptime std.debug.assert(Jobs.minimum == 1);
    comptime std.debug.assert(Jobs.maximum == 256);
    const default: Jobs = .literal(8);
    try t.expectEqual(@as(u16, 8), default.raw());
    comptime std.debug.assert(U.Duration(.millisecond, u64).Scale == .millisecond);
    comptime std.debug.assert(U.Count(Tag, u8).Domain == Tag);
    comptime std.debug.assert(a.id.Counter(Tag, u32).Domain == Tag);
    // The declaration states the parameters too.
    comptime std.debug.assert(Jobs.aegis_scalar.representation == u16 and Jobs.aegis_scalar.minimum == 1 and Jobs.aegis_scalar.maximum == 256);
    comptime std.debug.assert(U.Duration(.millisecond, u64).aegis_scalar.unit == .millisecond);
    comptime std.debug.assert(U.Instant(.awake, .second, i64).aegis_scalar.clock == .awake);
    comptime std.debug.assert(U.Count(Tag, u8).aegis_scalar.domain == Tag);
    comptime std.debug.assert(a.id.NonZero(Tag, u64).aegis_scalar.domain == Tag);
    const cases = .{
        .{ a.int.Checked(u7), Kind.checked },               .{ a.int.Saturating(i64), Kind.saturating },
        .{ Jobs, Kind.ranged },                             .{ a.int.Ranged(i8, -1, 1), Kind.ranged },
        .{ U.Count(Tag, u32), Kind.count },                 .{ U.Bytes(u64), Kind.bytes },
        .{ U.Bits(u64), Kind.bits },                        .{ U.Duration(.second, i96), Kind.duration },
        .{ U.Instant(.awake, .second, i64), Kind.instant }, .{ a.id.Id(Tag, u64), Kind.id },
        .{ a.id.NonZero(Tag, u64), Kind.nonzero },          .{ a.id.Counter(Tag, u64), Kind.counter },
        .{ enum(u16) { _ }, Kind.other },
        .{ struct {
            pub const Representation = u8;
        }, Kind.other },
        // Another copy of aegis's Ranged(u16, 1, 256): never equal to `Jobs`, recognized alike.
        .{ enum(u16) {
            pub const aegis_scalar = .{ .contract = 1, .kind = .ranged, .representation = u16, .minimum = 1, .maximum = 256 };
            pub const Representation = u16;
            pub const minimum: u16 = 1;
            pub const maximum: u16 = 256;
            _,
        }, Kind.ranged },
        // A later contract this reader does not know: refused, not misread.
        .{ enum(u16) {
            pub const aegis_scalar = .{ .contract = 2, .kind = .ranged, .representation = u16 };
            _,
        }, Kind.other },
        .{ u16, Kind.other },                               .{ a.int.Checked(u7), Kind.checked },
        .{ a.id.Id(Tag, i32), Kind.id },                    .{ U.Count(Tag, i8), Kind.count },
    };
    inline for (cases) |case| try t.expectEqual(case[1], comptime kindOf(case[0]));
}
