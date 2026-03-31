const std = @import("std");
const Allocator = std.mem.Allocator;
const flate = std.compress.flate;
const Decompress = flate.Decompress;
const Writer = std.Io.Writer;

/// Compresses data using zlib deflate (RFC 1950).
///
/// Uses stored (uncompressed) deflate blocks. This produces valid zlib
/// streams that are compatible with all PDF readers. The output is slightly
/// larger than the input due to framing overhead, but compression is very
/// fast and the implementation is reliable.
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn deflate(allocator: Allocator, data: []const u8) ![]u8 {
    return compressWithContainer(allocator, data, .zlib);
}

/// Compresses raw deflate data without zlib header/trailer (RFC 1951).
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn deflateRaw(allocator: Allocator, data: []const u8) ![]u8 {
    return compressWithContainer(allocator, data, .raw);
}

const ContainerFormat = enum { zlib, raw };

fn compressWithContainer(allocator: Allocator, data: []const u8, container: ContainerFormat) ![]u8 {
    // Calculate output size:
    // - Zlib header: 2 bytes (if zlib)
    // - Per stored block: 5 bytes overhead (1 byte BFINAL/BTYPE + 2 bytes LEN + 2 bytes NLEN)
    // - Adler32 footer: 4 bytes (if zlib)
    const max_block_size: usize = 65535;
    const num_blocks = if (data.len == 0) 1 else (data.len + max_block_size - 1) / max_block_size;
    const header_size: usize = if (container == .zlib) 2 else 0;
    const footer_size: usize = if (container == .zlib) 4 else 0;
    const total_size = header_size + num_blocks * 5 + data.len + footer_size;

    var result = try allocator.alloc(u8, total_size);
    errdefer allocator.free(result);

    var pos: usize = 0;

    // Write zlib header (RFC 1950)
    if (container == .zlib) {
        // CMF: CM=8 (deflate), CINFO=7 (32K window)
        result[pos] = 0x78;
        pos += 1;
        // FLG: FLEVEL=0 (fastest), FDICT=0, FCHECK computed for CMF*256+FLG % 31 == 0
        // 0x78 * 256 + FLG must be divisible by 31
        // 0x7800 = 30720, 30720 % 31 = 0, so FLG = 0x01 (30720 + 1 = 30721, 30721 % 31 = 1)
        // Actually: 30720 % 31 = 30720 - 991*31 = 30720 - 30721 = ... let me compute properly
        // 30720 / 31 = 990.967... -> 990 * 31 = 30690 -> 30720 - 30690 = 30 -> FCHECK = 31 - 30 = 1
        result[pos] = 0x01;
        pos += 1;
    }

    // Write stored deflate blocks (RFC 1951, section 3.2.4)
    var offset: usize = 0;
    while (true) {
        const remaining = data.len - offset;
        const block_size: u16 = @intCast(@min(remaining, max_block_size));
        const is_final = (offset + block_size >= data.len);

        // BFINAL (1 bit) + BTYPE=00 (2 bits) = stored block, rest of byte is 0
        result[pos] = if (is_final) 0x01 else 0x00;
        pos += 1;

        // LEN (2 bytes, little-endian)
        std.mem.writeInt(u16, result[pos..][0..2], block_size, .little);
        pos += 2;

        // NLEN (one's complement of LEN, 2 bytes, little-endian)
        std.mem.writeInt(u16, result[pos..][0..2], ~block_size, .little);
        pos += 2;

        // Block data
        if (block_size > 0) {
            @memcpy(result[pos..][0..block_size], data[offset..][0..block_size]);
            pos += block_size;
        }

        offset += block_size;
        if (is_final) break;
    }

    // Write Adler-32 checksum (RFC 1950) in big-endian
    if (container == .zlib) {
        const checksum = std.hash.Adler32.hash(data);
        std.mem.writeInt(u32, result[pos..][0..4], checksum, .big);
        pos += 4;
    }

    std.debug.assert(pos == total_size);

    return result;
}

/// Decompresses zlib deflate compressed data (RFC 1950).
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn inflate(allocator: Allocator, data: []const u8) ![]u8 {
    return decompressWithContainer(allocator, data, .zlib);
}

/// Decompresses raw deflate data without zlib header/trailer (RFC 1951).
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn inflateRaw(allocator: Allocator, data: []const u8) ![]u8 {
    return decompressWithContainer(allocator, data, .raw);
}

fn decompressWithContainer(allocator: Allocator, data: []const u8, container: ContainerFormat) ![]u8 {
    const flate_container: flate.Container = switch (container) {
        .zlib => .zlib,
        .raw => .raw,
    };

    var reader: std.Io.Reader = .fixed(data);
    var aw: Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var decomp: Decompress = .init(&reader, flate_container, &.{});
    _ = try decomp.reader.streamRemaining(&aw.writer);

    return try aw.toOwnedSlice();
}

test "deflate and inflate round-trip" {
    const allocator = std.testing.allocator;
    const original = "Hello, PDF World! This is a test of zlib compression.";

    const compressed = try deflate(allocator, original);
    defer allocator.free(compressed);

    // Zlib header starts with 0x78
    try std.testing.expect(compressed[0] == 0x78);

    const decompressed = try inflate(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}

test "deflate and inflate empty data" {
    const allocator = std.testing.allocator;

    const compressed = try deflate(allocator, "");
    defer allocator.free(compressed);

    const decompressed = try inflate(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqual(@as(usize, 0), decompressed.len);
}

test "raw deflate and inflate round-trip" {
    const allocator = std.testing.allocator;
    const original = "Raw deflate without zlib wrapper test data.";

    const compressed = try deflateRaw(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try inflateRaw(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}

test "deflate large data spanning multiple blocks" {
    const allocator = std.testing.allocator;

    // Create data larger than max_block_size (65535) to test multi-block
    var original: [100000]u8 = undefined;
    for (&original, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    const compressed = try deflate(allocator, &original);
    defer allocator.free(compressed);

    const decompressed = try inflate(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &original, decompressed);
}

test "deflate single byte" {
    const allocator = std.testing.allocator;
    const original = "X";

    const compressed = try deflate(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try inflate(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}
