const std = @import("std");
const Allocator = std.mem.Allocator;
const flate = std.compress.flate;
const Decompress = flate.Decompress;
const Writer = std.Io.Writer;

/// Decompresses zlib-compressed data (RFC 1950).
///
/// This is the primary decompression function for PDF's FlateDecode filter.
/// The caller owns the returned slice and must free it with the same allocator.
pub fn inflate(allocator: Allocator, data: []const u8) ![]u8 {
    return inflateWithContainer(allocator, data, .zlib);
}

/// Decompresses raw deflate data without zlib header/trailer (RFC 1951).
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn inflateRaw(allocator: Allocator, data: []const u8) ![]u8 {
    return inflateWithContainer(allocator, data, .raw);
}

/// Decompresses deflate data with the specified container format.
fn inflateWithContainer(allocator: Allocator, data: []const u8, container: flate.Container) ![]u8 {
    var reader: std.Io.Reader = .fixed(data);
    var aw: Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var decomp: Decompress = .init(&reader, container, &.{});
    _ = try decomp.reader.streamRemaining(&aw.writer);

    return try aw.toOwnedSlice();
}

/// Decompresses zlib data and writes into a pre-allocated buffer.
///
/// Returns the number of decompressed bytes written. Returns an error if
/// the decompressed data does not fit in the output buffer.
pub fn inflateInto(data: []const u8, output: []u8) !usize {
    var reader: std.Io.Reader = .fixed(data);
    var writer: Writer = .fixed(output);

    var decomp: Decompress = .init(&reader, .zlib, &.{});
    return try decomp.reader.streamRemaining(&writer);
}

test "inflate zlib data" {
    const allocator = std.testing.allocator;
    const deflate_mod = @import("deflate.zig");

    const original = "The quick brown fox jumps over the lazy dog.";
    const compressed = try deflate_mod.deflate(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try inflate(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}

test "inflate raw deflate data" {
    const allocator = std.testing.allocator;
    const deflate_mod = @import("deflate.zig");

    const original = "Raw deflate stream test.";
    const compressed = try deflate_mod.deflateRaw(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try inflateRaw(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}

test "inflate into pre-allocated buffer" {
    const allocator = std.testing.allocator;
    const deflate_mod = @import("deflate.zig");

    const original = "Buffer test data.";
    const compressed = try deflate_mod.deflate(allocator, original);
    defer allocator.free(compressed);

    var buf: [256]u8 = undefined;
    const n = try inflateInto(compressed, &buf);
    try std.testing.expectEqualSlices(u8, original, buf[0..n]);
}
