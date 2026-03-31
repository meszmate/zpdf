const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const ascii85 = zpdf.compress.ascii85;
const ascii_hex = zpdf.compress.ascii_hex;
const run_length = zpdf.compress.run_length;
const deflate_mod = zpdf.compress.deflate_mod;

test "ASCII85 encode and decode roundtrip" {
    const original = "Hello, World! This is a test.";
    const encoded = try ascii85.encode(testing.allocator, original);
    defer testing.allocator.free(encoded);

    const decoded = try ascii85.decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, original, decoded);
}

test "ASCII85 encode known value" {
    const encoded = try ascii85.encode(testing.allocator, "Man ");
    defer testing.allocator.free(encoded);
    try testing.expectEqualSlices(u8, "<~9jqo^~>", encoded);
}

test "ASCII85 zero group" {
    const encoded = try ascii85.encode(testing.allocator, &[_]u8{ 0, 0, 0, 0 });
    defer testing.allocator.free(encoded);
    try testing.expectEqualSlices(u8, "<~z~>", encoded);
}

test "ASCII hex encode and decode roundtrip" {
    const original = "Hello, PDF!";
    const encoded = try ascii_hex.encode(testing.allocator, original);
    defer testing.allocator.free(encoded);

    const decoded = try ascii_hex.decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, original, decoded);
}

test "ASCII hex encode known value" {
    const encoded = try ascii_hex.encode(testing.allocator, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF });
    defer testing.allocator.free(encoded);
    try testing.expectEqualSlices(u8, "DEADBEEF>", encoded);
}

test "run-length encode and decode roundtrip" {
    const original = "AAABBBCCDDDDDDDDEFFGH";
    const encoded = try run_length.encode(testing.allocator, original);
    defer testing.allocator.free(encoded);

    const decoded = try run_length.decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, original, decoded);
}

test "run-length encode repeated bytes" {
    const encoded = try run_length.encode(testing.allocator, "AAAA");
    defer testing.allocator.free(encoded);
    // 253 (257-4), 'A', 128 (EOD)
    try testing.expectEqualSlices(u8, &[_]u8{ 253, 'A', 128 }, encoded);
}

test "deflate and inflate roundtrip" {
    const original = "Hello, PDF World! This is a test of zlib compression.";
    const compressed = try deflate_mod.deflate(testing.allocator, original);
    defer testing.allocator.free(compressed);

    try testing.expect(compressed[0] == 0x78);

    const decompressed = try deflate_mod.inflate(testing.allocator, compressed);
    defer testing.allocator.free(decompressed);
    try testing.expectEqualSlices(u8, original, decompressed);
}
