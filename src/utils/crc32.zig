const std = @import("std");

/// CRC32 lookup table, generated at compile time using the standard polynomial (0xEDB88320).
const crc_table: [256]u32 = blk: {
    @setEvalBranchQuota(3000);
    var table: [256]u32 = undefined;
    for (0..256) |i| {
        var crc: u32 = @intCast(i);
        for (0..8) |_| {
            if (crc & 1 == 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc = crc >> 1;
            }
        }
        table[i] = crc;
    }
    break :blk table;
};

/// Update a running CRC32 value with additional data.
/// To start a new CRC computation, pass 0xFFFFFFFF as the initial crc value,
/// then XOR the final result with 0xFFFFFFFF (or just use `compute`).
pub fn update(crc: u32, data: []const u8) u32 {
    var c = crc;
    for (data) |byte| {
        c = crc_table[@as(u8, @truncate(c)) ^ byte] ^ (c >> 8);
    }
    return c;
}

/// Compute the CRC32 checksum of the given data.
pub fn compute(data: []const u8) u32 {
    return update(0xFFFFFFFF, data) ^ 0xFFFFFFFF;
}

test "CRC32: empty data" {
    try std.testing.expectEqual(@as(u32, 0x00000000), compute(""));
}

test "CRC32: known value for 'Hello'" {
    // CRC32 of "Hello" is 0xF7D18982
    try std.testing.expectEqual(@as(u32, 0xF7D18982), compute("Hello"));
}

test "CRC32: known value for '123456789'" {
    // The standard CRC32 check value
    try std.testing.expectEqual(@as(u32, 0xCBF43926), compute("123456789"));
}

test "CRC32: incremental update matches single compute" {
    const data = "Hello, World!";
    const full = compute(data);

    // Compute in two parts
    var crc = update(0xFFFFFFFF, data[0..5]);
    crc = update(crc, data[5..]);
    crc ^= 0xFFFFFFFF;

    try std.testing.expectEqual(full, crc);
}

test "CRC32: incremental update byte by byte" {
    const data = "test data";
    const full = compute(data);

    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc = update(crc, &[_]u8{byte});
    }
    crc ^= 0xFFFFFFFF;

    try std.testing.expectEqual(full, crc);
}

test "CRC32: single byte" {
    // CRC32 of a single zero byte
    try std.testing.expectEqual(@as(u32, 0xD202EF8D), compute(&[_]u8{0x00}));
}

test "CRC32: table spot check" {
    // First entry should be 0 (CRC of 0x00 starting from 0)
    try std.testing.expectEqual(@as(u32, 0x00000000), crc_table[0]);
    // Entry for 1 should be the polynomial (reflected)
    try std.testing.expectEqual(@as(u32, 0x77073096), crc_table[1]);
}
