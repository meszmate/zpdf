const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AesError = error{
    InvalidKeyLength,
    InvalidDataLength,
    InvalidPadding,
};

/// AES-CBC encryption with PKCS7 padding.
/// Supports 128-bit (16-byte) and 256-bit (32-byte) keys.
/// Returns a newly allocated slice containing the ciphertext.
pub fn aesEncryptCbc(allocator: Allocator, key: []const u8, iv: [16]u8, data: []const u8) (Allocator.Error || AesError)![]u8 {
    // Determine key length and get the appropriate AES context
    if (key.len == 16) {
        return aesEncryptCbc128(allocator, key[0..16].*, iv, data);
    } else if (key.len == 32) {
        return aesEncryptCbc256(allocator, key[0..32].*, iv, data);
    } else {
        return AesError.InvalidKeyLength;
    }
}

/// AES-CBC decryption with PKCS7 unpadding.
/// Returns a newly allocated slice containing the plaintext.
pub fn aesDecryptCbc(allocator: Allocator, key: []const u8, iv: [16]u8, data: []const u8) (Allocator.Error || AesError)![]u8 {
    if (data.len == 0 or data.len % 16 != 0) {
        return AesError.InvalidDataLength;
    }

    if (key.len == 16) {
        return aesDecryptCbc128(allocator, key[0..16].*, iv, data);
    } else if (key.len == 32) {
        return aesDecryptCbc256(allocator, key[0..32].*, iv, data);
    } else {
        return AesError.InvalidKeyLength;
    }
}

fn aesEncryptCbc128(allocator: Allocator, key: [16]u8, iv: [16]u8, data: []const u8) Allocator.Error![]u8 {
    const ctx = std.crypto.core.aes.Aes128.initEnc(key);

    // PKCS7 padding
    const pad_len: u8 = @intCast(16 - (data.len % 16));
    const padded_len = data.len + pad_len;
    const padded = try allocator.alloc(u8, padded_len);
    defer allocator.free(padded);

    @memcpy(padded[0..data.len], data);
    @memset(padded[data.len..], pad_len);

    // CBC encryption
    const output = try allocator.alloc(u8, padded_len);
    var prev_block: [16]u8 = iv;

    var i: usize = 0;
    while (i < padded_len) : (i += 16) {
        var block: [16]u8 = padded[i..][0..16].*;
        // XOR with previous ciphertext block
        for (0..16) |j| {
            block[j] ^= prev_block[j];
        }
        var encrypted: [16]u8 = undefined;
        ctx.encrypt(&encrypted, &block);
        @memcpy(output[i..][0..16], &encrypted);
        prev_block = encrypted;
    }

    return output;
}

fn aesEncryptCbc256(allocator: Allocator, key: [32]u8, iv: [16]u8, data: []const u8) Allocator.Error![]u8 {
    const ctx = std.crypto.core.aes.Aes256.initEnc(key);

    const pad_len: u8 = @intCast(16 - (data.len % 16));
    const padded_len = data.len + pad_len;
    const padded = try allocator.alloc(u8, padded_len);
    defer allocator.free(padded);

    @memcpy(padded[0..data.len], data);
    @memset(padded[data.len..], pad_len);

    const output = try allocator.alloc(u8, padded_len);
    var prev_block: [16]u8 = iv;

    var i: usize = 0;
    while (i < padded_len) : (i += 16) {
        var block: [16]u8 = padded[i..][0..16].*;
        for (0..16) |j| {
            block[j] ^= prev_block[j];
        }
        var encrypted: [16]u8 = undefined;
        ctx.encrypt(&encrypted, &block);
        @memcpy(output[i..][0..16], &encrypted);
        prev_block = encrypted;
    }

    return output;
}

fn aesDecryptCbc128(allocator: Allocator, key: [16]u8, iv: [16]u8, data: []const u8) (Allocator.Error || AesError)![]u8 {
    const ctx = std.crypto.core.aes.Aes128.initDec(key);

    const output = try allocator.alloc(u8, data.len);
    var prev_block: [16]u8 = iv;

    var i: usize = 0;
    while (i < data.len) : (i += 16) {
        const cipher_block: [16]u8 = data[i..][0..16].*;
        var decrypted: [16]u8 = undefined;
        ctx.decrypt(&decrypted, &cipher_block);
        for (0..16) |j| {
            decrypted[j] ^= prev_block[j];
        }
        @memcpy(output[i..][0..16], &decrypted);
        prev_block = cipher_block;
    }

    // Remove PKCS7 padding
    const pad_byte = output[output.len - 1];
    if (pad_byte == 0 or pad_byte > 16) {
        allocator.free(output);
        return AesError.InvalidPadding;
    }

    // Validate padding bytes
    for (output[output.len - pad_byte ..]) |b| {
        if (b != pad_byte) {
            allocator.free(output);
            return AesError.InvalidPadding;
        }
    }

    const unpadded_len = output.len - pad_byte;
    const result = try allocator.alloc(u8, unpadded_len);
    @memcpy(result, output[0..unpadded_len]);
    allocator.free(output);
    return result;
}

fn aesDecryptCbc256(allocator: Allocator, key: [32]u8, iv: [16]u8, data: []const u8) (Allocator.Error || AesError)![]u8 {
    const ctx = std.crypto.core.aes.Aes256.initDec(key);

    const output = try allocator.alloc(u8, data.len);
    var prev_block: [16]u8 = iv;

    var i: usize = 0;
    while (i < data.len) : (i += 16) {
        const cipher_block: [16]u8 = data[i..][0..16].*;
        var decrypted: [16]u8 = undefined;
        ctx.decrypt(&decrypted, &cipher_block);
        for (0..16) |j| {
            decrypted[j] ^= prev_block[j];
        }
        @memcpy(output[i..][0..16], &decrypted);
        prev_block = cipher_block;
    }

    const pad_byte = output[output.len - 1];
    if (pad_byte == 0 or pad_byte > 16) {
        allocator.free(output);
        return AesError.InvalidPadding;
    }

    for (output[output.len - pad_byte ..]) |b| {
        if (b != pad_byte) {
            allocator.free(output);
            return AesError.InvalidPadding;
        }
    }

    const unpadded_len = output.len - pad_byte;
    const result = try allocator.alloc(u8, unpadded_len);
    @memcpy(result, output[0..unpadded_len]);
    allocator.free(output);
    return result;
}

// -- Tests --

test "aes-cbc 128: encrypt and decrypt roundtrip" {
    const allocator = std.testing.allocator;
    const key = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f };
    const iv = [_]u8{0} ** 16;
    const plaintext = "Hello, AES-CBC!!";

    const encrypted = try aesEncryptCbc(allocator, &key, iv, plaintext);
    defer allocator.free(encrypted);

    try std.testing.expect(encrypted.len > 0);
    try std.testing.expect(encrypted.len % 16 == 0);

    const decrypted = try aesDecryptCbc(allocator, &key, iv, encrypted);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);
}

test "aes-cbc 256: encrypt and decrypt roundtrip" {
    const allocator = std.testing.allocator;
    const key = [_]u8{0x42} ** 32;
    const iv = [_]u8{0} ** 16;
    const plaintext = "AES-256 test data for roundtrip.";

    const encrypted = try aesEncryptCbc(allocator, &key, iv, plaintext);
    defer allocator.free(encrypted);

    const decrypted = try aesDecryptCbc(allocator, &key, iv, encrypted);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);
}

test "aes-cbc: invalid key length" {
    const allocator = std.testing.allocator;
    const key = [_]u8{0} ** 10;
    const iv = [_]u8{0} ** 16;

    const result = aesEncryptCbc(allocator, &key, iv, "test");
    try std.testing.expectError(AesError.InvalidKeyLength, result);
}

test "aes-cbc: decrypt invalid data length" {
    const allocator = std.testing.allocator;
    const key = [_]u8{0} ** 16;
    const iv = [_]u8{0} ** 16;

    const result = aesDecryptCbc(allocator, &key, iv, "odd");
    try std.testing.expectError(AesError.InvalidDataLength, result);
}
