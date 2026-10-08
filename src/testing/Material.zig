//! Exact C1 inline declarations, from cloak d3d790f14211924ef974918cdfe2203b8e90ab62:
//! src/credentials/Key.zig Material and src/credentials/Rsa.zig Key.
//! No parser/crypto implementation is copied. Tested with this pinned std's actual curve types.
const std = @import("std");
const Rsa = struct {
    const Key = struct {
        n: [512]u8 = @splat(0),
        e: [8]u8 = @splat(0),
        d: [512]u8 = @splat(0),
        size: usize,
        exponent_size: usize,
    };
};
const P256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;
const P384 = std.crypto.sign.ecdsa.EcdsaP384Sha384;
const Ed25519 = std.crypto.sign.Ed25519;
pub const Material = union(enum) { rsa: Rsa.Key, p256: P256.KeyPair, p384: P384.KeyPair, ed25519: Ed25519.KeyPair };
