const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Ref = core.Ref;
const PdfObject = core.PdfObject;
const image_embedder = @import("image_embedder.zig");
const ImageHandle = image_embedder.ImageHandle;
const ImageFormat = image_embedder.ImageFormat;
const deflate_mod = @import("../compress/deflate.zig");
const inflate_mod = @import("../compress/inflate.zig");

/// PNG signature bytes.
const png_signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

/// Information extracted from a PNG header (IHDR chunk).
pub const PngInfo = struct {
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    has_alpha: bool,
};

pub const PngError = error{
    InvalidPng,
    UnsupportedPng,
    UnexpectedEndOfData,
    InvalidFilterType,
    DecompressionFailed,
};

/// Parse a PNG header (IHDR chunk) to extract image information.
/// Verifies the PNG signature and reads the IHDR chunk for width, height,
/// bit depth, and color type.
pub fn parsePng(data: []const u8) PngError!PngInfo {
    if (data.len < 8) return PngError.InvalidPng;

    // Verify PNG signature
    if (!std.mem.eql(u8, data[0..8], &png_signature)) return PngError.InvalidPng;

    // IHDR must be the first chunk
    if (data.len < 8 + 8 + 13) return PngError.UnexpectedEndOfData;

    // Read chunk length (4 bytes big-endian)
    const chunk_len = readU32(data[8..12]);
    if (chunk_len != 13) return PngError.InvalidPng; // IHDR is always 13 bytes

    // Verify chunk type is IHDR
    if (!std.mem.eql(u8, data[12..16], "IHDR")) return PngError.InvalidPng;

    const width = readU32(data[16..20]);
    const height = readU32(data[20..24]);
    const bit_depth = data[24];
    const color_type = data[25];

    // Color type 4 = grayscale+alpha, 6 = RGBA
    const has_alpha = (color_type == 4 or color_type == 6);

    return PngInfo{
        .width = width,
        .height = height,
        .bit_depth = bit_depth,
        .color_type = color_type,
        .has_alpha = has_alpha,
    };
}

/// Read a big-endian u32 from a 4-byte slice.
fn readU32(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .big);
}

/// Extract and concatenate all IDAT chunk data from a PNG file.
fn extractIdatChunks(allocator: Allocator, data: []const u8) ![]u8 {
    var idat_data: std.ArrayListUnmanaged(u8) = .empty;
    defer idat_data.deinit(allocator);

    var offset: usize = 8; // Skip signature

    while (offset + 8 <= data.len) {
        const chunk_len = readU32(data[offset..][0..4]);
        const chunk_type = data[offset + 4 .. offset + 8];
        offset += 8;

        if (offset + chunk_len > data.len) break;

        if (std.mem.eql(u8, chunk_type, "IDAT")) {
            try idat_data.appendSlice(allocator, data[offset .. offset + chunk_len]);
        }

        // Skip chunk data + CRC (4 bytes)
        offset += chunk_len + 4;
    }

    return try idat_data.toOwnedSlice(allocator);
}

/// Remove PNG filter bytes from decompressed image data.
/// Each scanline is prefixed with a filter type byte that must be processed.
fn removeFilterBytes(allocator: Allocator, raw_data: []const u8, width: u32, height: u32, bytes_per_pixel: u8) ![]u8 {
    const stride = @as(usize, width) * @as(usize, bytes_per_pixel);
    const scanline_len = stride + 1; // +1 for filter byte

    if (raw_data.len < scanline_len * @as(usize, height)) {
        return PngError.UnexpectedEndOfData;
    }

    var result = try allocator.alloc(u8, stride * @as(usize, height));
    errdefer allocator.free(result);

    // Previous scanline for filter reconstruction
    var prev_line: ?[]const u8 = null;

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const line_start = y * scanline_len;
        const filter_type = raw_data[line_start];
        const line_data = raw_data[line_start + 1 .. line_start + scanline_len];
        const out_start = y * stride;
        const out_line = result[out_start .. out_start + stride];

        switch (filter_type) {
            0 => {
                // None
                @memcpy(out_line, line_data);
            },
            1 => {
                // Sub
                for (0..stride) |i| {
                    const a: u8 = if (i >= bytes_per_pixel) out_line[i - bytes_per_pixel] else 0;
                    out_line[i] = line_data[i] +% a;
                }
            },
            2 => {
                // Up
                for (0..stride) |i| {
                    const b: u8 = if (prev_line) |pl| pl[i] else 0;
                    out_line[i] = line_data[i] +% b;
                }
            },
            3 => {
                // Average
                for (0..stride) |i| {
                    const a: u16 = if (i >= bytes_per_pixel) out_line[i - bytes_per_pixel] else 0;
                    const b: u16 = if (prev_line) |pl| pl[i] else 0;
                    out_line[i] = line_data[i] +% @as(u8, @intCast((a + b) / 2));
                }
            },
            4 => {
                // Paeth
                for (0..stride) |i| {
                    const a: i16 = if (i >= bytes_per_pixel) @as(i16, out_line[i - bytes_per_pixel]) else 0;
                    const b: i16 = if (prev_line) |pl| @as(i16, pl[i]) else 0;
                    const c: i16 = if (i >= bytes_per_pixel and prev_line != null) @as(i16, prev_line.?[i - bytes_per_pixel]) else 0;
                    out_line[i] = line_data[i] +% paethPredictor(a, b, c);
                }
            },
            else => return PngError.InvalidFilterType,
        }

        prev_line = out_line;
    }

    return result;
}

/// Paeth predictor function used in PNG filter type 4.
fn paethPredictor(a: i16, b: i16, c: i16) u8 {
    const p = a + b - c;
    const pa = @as(u16, @intCast(if (p - a < 0) -(p - a) else p - a));
    const pb = @as(u16, @intCast(if (p - b < 0) -(p - b) else p - b));
    const pc = @as(u16, @intCast(if (p - c < 0) -(p - c) else p - c));

    if (pa <= pb and pa <= pc) return @intCast(@as(u16, @intCast(a)));
    if (pb <= pc) return @intCast(@as(u16, @intCast(b)));
    return @intCast(@as(u16, @intCast(c)));
}

/// Separate alpha channel from pixel data.
const SeparatedChannels = struct {
    color: []u8,
    alpha: []u8,
};

fn separateAlpha(allocator: Allocator, pixel_data: []const u8, width: u32, height: u32, color_type: u8) !SeparatedChannels {
    const pixel_count = @as(usize, width) * @as(usize, height);

    if (color_type == 6) {
        // RGBA -> RGB + A
        var color = try allocator.alloc(u8, pixel_count * 3);
        errdefer allocator.free(color);
        var alpha = try allocator.alloc(u8, pixel_count);
        errdefer allocator.free(alpha);

        for (0..pixel_count) |i| {
            color[i * 3 + 0] = pixel_data[i * 4 + 0];
            color[i * 3 + 1] = pixel_data[i * 4 + 1];
            color[i * 3 + 2] = pixel_data[i * 4 + 2];
            alpha[i] = pixel_data[i * 4 + 3];
        }

        return .{ .color = color, .alpha = alpha };
    } else if (color_type == 4) {
        // Gray+Alpha -> Gray + A
        var color = try allocator.alloc(u8, pixel_count);
        errdefer allocator.free(color);
        var alpha = try allocator.alloc(u8, pixel_count);
        errdefer allocator.free(alpha);

        for (0..pixel_count) |i| {
            color[i] = pixel_data[i * 2 + 0];
            alpha[i] = pixel_data[i * 2 + 1];
        }

        return .{ .color = color, .alpha = alpha };
    }

    unreachable;
}

/// Get the number of bytes per pixel for a given color type (at 8-bit depth).
fn bytesPerPixel(color_type: u8) u8 {
    return switch (color_type) {
        0 => 1, // Grayscale
        2 => 3, // RGB
        3 => 1, // Indexed
        4 => 2, // Grayscale + Alpha
        6 => 4, // RGBA
        else => 1,
    };
}

/// Get the PDF color space name for a PNG color type.
fn pngColorSpaceName(color_type: u8) []const u8 {
    return switch (color_type) {
        0, 4 => "DeviceGray",
        2, 3, 6 => "DeviceRGB",
        else => "DeviceRGB",
    };
}

/// Create a PDF image XObject for a PNG image.
/// Extracts IDAT chunks, decompresses, removes filter bytes, handles alpha
/// channel separately as SMask, and creates the image stream with /FlateDecode.
pub fn embedPng(allocator: Allocator, store: *ObjectStore, data: []const u8) !ImageHandle {
    const info = try parsePng(data);

    // Extract IDAT data (concatenated zlib stream)
    const idat_data = try extractIdatChunks(allocator, data);
    defer allocator.free(idat_data);

    // Decompress zlib data using the project's inflate module
    const decompressed = inflate_mod.inflate(allocator, idat_data) catch return PngError.DecompressionFailed;
    defer allocator.free(decompressed);

    const bpp = bytesPerPixel(info.color_type);
    const pixel_data = try removeFilterBytes(allocator, decompressed, info.width, info.height, bpp);
    defer allocator.free(pixel_data);

    var smask_ref: ?Ref = null;

    // Determine the color data to compress
    var color_data: []u8 = undefined;
    var alpha_data: ?[]u8 = null;
    defer if (alpha_data) |a| allocator.free(a);

    if (info.has_alpha) {
        const separated = try separateAlpha(allocator, pixel_data, info.width, info.height, info.color_type);
        color_data = separated.color;
        alpha_data = separated.alpha;

        // Create SMask object for alpha channel
        const smask_compressed = try deflate_mod.deflate(allocator, separated.alpha);
        defer allocator.free(smask_compressed);

        smask_ref = try store.allocate();

        var smask_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try smask_dict.put(allocator, "Type", core.pdfName("XObject"));
        try smask_dict.put(allocator, "Subtype", core.pdfName("Image"));
        try smask_dict.put(allocator, "Width", core.pdfInt(@intCast(info.width)));
        try smask_dict.put(allocator, "Height", core.pdfInt(@intCast(info.height)));
        try smask_dict.put(allocator, "ColorSpace", core.pdfName("DeviceGray"));
        try smask_dict.put(allocator, "BitsPerComponent", core.pdfInt(@intCast(info.bit_depth)));
        try smask_dict.put(allocator, "Filter", core.pdfName("FlateDecode"));
        try smask_dict.put(allocator, "Length", core.pdfInt(@intCast(smask_compressed.len)));

        // Duplicate compressed data for stream storage
        const smask_stream_data = try allocator.dupe(u8, smask_compressed);

        const smask_obj = PdfObject{ .stream_obj = .{
            .dict = smask_dict,
            .data = smask_stream_data,
        } };

        store.put(smask_ref.?, smask_obj);
    } else {
        color_data = try allocator.dupe(u8, pixel_data);
    }
    defer allocator.free(color_data);

    // Compress color data using the project's deflate module
    const compressed = try deflate_mod.deflate(allocator, color_data);
    defer allocator.free(compressed);

    const ref = try store.allocate();

    var dict: std.StringHashMapUnmanaged(PdfObject) = .{};
    try dict.put(allocator, "Type", core.pdfName("XObject"));
    try dict.put(allocator, "Subtype", core.pdfName("Image"));
    try dict.put(allocator, "Width", core.pdfInt(@intCast(info.width)));
    try dict.put(allocator, "Height", core.pdfInt(@intCast(info.height)));
    try dict.put(allocator, "ColorSpace", core.pdfName(pngColorSpaceName(info.color_type)));
    try dict.put(allocator, "BitsPerComponent", core.pdfInt(@intCast(info.bit_depth)));
    try dict.put(allocator, "Filter", core.pdfName("FlateDecode"));
    try dict.put(allocator, "Length", core.pdfInt(@intCast(compressed.len)));

    if (smask_ref) |sr| {
        try dict.put(allocator, "SMask", core.pdfRef(sr.obj_num, sr.gen_num));
    }

    // Duplicate compressed data for stream storage
    const stream_data = try allocator.dupe(u8, compressed);

    const stream_obj = PdfObject{ .stream_obj = .{
        .dict = dict,
        .data = stream_data,
    } };

    store.put(ref, stream_obj);

    return ImageHandle{
        .ref = ref,
        .width = info.width,
        .height = info.height,
        .format = .png,
    };
}

// -- Tests --

test "parsePng: valid minimal PNG" {
    const data = [_]u8{
        // PNG signature
        137, 80, 78, 71, 13, 10, 26, 10,
        // IHDR chunk
        0x00, 0x00, 0x00, 0x0D, // chunk length = 13
        'I',  'H',  'D',  'R', // chunk type
        0x00, 0x00, 0x00, 0x10, // width = 16
        0x00, 0x00, 0x00, 0x08, // height = 8
        0x08, // bit depth = 8
        0x02, // color type = 2 (RGB)
        0x00, // compression method
        0x00, // filter method
        0x00, // interlace method
        0x00, 0x00, 0x00, 0x00, // CRC (ignored in parse)
    };

    const info = try parsePng(&data);
    try std.testing.expectEqual(@as(u32, 16), info.width);
    try std.testing.expectEqual(@as(u32, 8), info.height);
    try std.testing.expectEqual(@as(u8, 8), info.bit_depth);
    try std.testing.expectEqual(@as(u8, 2), info.color_type);
    try std.testing.expect(!info.has_alpha);
}

test "parsePng: RGBA has alpha" {
    const data = [_]u8{
        137, 80, 78, 71, 13, 10, 26, 10,
        0x00, 0x00, 0x00, 0x0D,
        'I',  'H',  'D',  'R',
        0x00, 0x00, 0x00, 0x04, // width = 4
        0x00, 0x00, 0x00, 0x04, // height = 4
        0x08, // bit depth = 8
        0x06, // color type = 6 (RGBA)
        0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };

    const info = try parsePng(&data);
    try std.testing.expect(info.has_alpha);
    try std.testing.expectEqual(@as(u8, 6), info.color_type);
}

test "parsePng: invalid signature" {
    const data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const result = parsePng(&data);
    try std.testing.expectError(PngError.InvalidPng, result);
}

test "parsePng: too short" {
    const data = [_]u8{ 137, 80, 78, 71 };
    const result = parsePng(&data);
    try std.testing.expectError(PngError.InvalidPng, result);
}

test "paethPredictor" {
    try std.testing.expectEqual(@as(u8, 15), paethPredictor(10, 20, 15));
    try std.testing.expectEqual(@as(u8, 0), paethPredictor(0, 0, 0));
}
