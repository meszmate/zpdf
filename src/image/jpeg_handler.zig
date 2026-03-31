const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Ref = core.Ref;
const PdfObject = core.PdfObject;
const image_embedder = @import("image_embedder.zig");
const ImageHandle = image_embedder.ImageHandle;
const ImageFormat = image_embedder.ImageFormat;

/// Color space types found in JPEG files.
pub const ColorSpace = enum {
    device_gray,
    device_rgb,
    device_cmyk,

    /// Returns the PDF name for this color space.
    pub fn pdfName(self: ColorSpace) []const u8 {
        return switch (self) {
            .device_gray => "DeviceGray",
            .device_rgb => "DeviceRGB",
            .device_cmyk => "DeviceCMYK",
        };
    }
};

/// Information extracted from a JPEG header.
pub const JpegInfo = struct {
    width: u32,
    height: u32,
    components: u8,
    bits_per_component: u8,
    color_space: ColorSpace,
};

pub const JpegError = error{
    InvalidJpeg,
    UnsupportedJpeg,
    UnexpectedEndOfData,
};

/// Parse a JPEG header to extract dimensions and color information.
/// Reads the SOI marker (0xFFD8) and scans for SOF0 (0xFFC0) or SOF2 (0xFFC2)
/// markers to extract width, height, and component count.
pub fn parseJpeg(data: []const u8) JpegError!JpegInfo {
    if (data.len < 2) return JpegError.InvalidJpeg;

    // Verify SOI marker
    if (data[0] != 0xFF or data[1] != 0xD8) return JpegError.InvalidJpeg;

    var offset: usize = 2;

    while (offset + 1 < data.len) {
        // Find next marker
        if (data[offset] != 0xFF) return JpegError.InvalidJpeg;

        // Skip padding 0xFF bytes
        while (offset + 1 < data.len and data[offset + 1] == 0xFF) {
            offset += 1;
        }

        if (offset + 1 >= data.len) return JpegError.UnexpectedEndOfData;

        const marker = data[offset + 1];
        offset += 2;

        // SOF0 (baseline) or SOF2 (progressive)
        if (marker == 0xC0 or marker == 0xC2) {
            if (offset + 8 > data.len) return JpegError.UnexpectedEndOfData;

            const bits_per_component = data[offset + 2];
            const height = @as(u32, data[offset + 3]) << 8 | @as(u32, data[offset + 4]);
            const width = @as(u32, data[offset + 5]) << 8 | @as(u32, data[offset + 6]);
            const components = data[offset + 7];

            const color_space: ColorSpace = switch (components) {
                1 => .device_gray,
                3 => .device_rgb,
                4 => .device_cmyk,
                else => return JpegError.UnsupportedJpeg,
            };

            return JpegInfo{
                .width = width,
                .height = height,
                .components = components,
                .bits_per_component = bits_per_component,
                .color_space = color_space,
            };
        }

        // EOI marker
        if (marker == 0xD9) return JpegError.InvalidJpeg;

        // SOS marker - data follows, no SOF found before SOS
        if (marker == 0xDA) return JpegError.InvalidJpeg;

        // Skip marker segment (read length and advance)
        if (offset + 2 > data.len) return JpegError.UnexpectedEndOfData;
        const seg_len = @as(usize, data[offset]) << 8 | @as(usize, data[offset + 1]);
        if (seg_len < 2) return JpegError.InvalidJpeg;
        offset += seg_len;
    }

    return JpegError.InvalidJpeg;
}

/// Create a PDF image XObject for a JPEG image.
/// The raw JPEG data is stored as the stream with /DCTDecode filter.
pub fn embedJpeg(allocator: Allocator, store: *ObjectStore, data: []const u8) !ImageHandle {
    const info = try parseJpeg(data);

    const ref = try store.allocate();

    var dict: std.StringHashMapUnmanaged(PdfObject) = .{};
    try dict.put(allocator, "Type", core.pdfName("XObject"));
    try dict.put(allocator, "Subtype", core.pdfName("Image"));
    try dict.put(allocator, "Width", core.pdfInt(@intCast(info.width)));
    try dict.put(allocator, "Height", core.pdfInt(@intCast(info.height)));
    try dict.put(allocator, "ColorSpace", core.pdfName(info.color_space.pdfName()));
    try dict.put(allocator, "BitsPerComponent", core.pdfInt(@intCast(info.bits_per_component)));
    try dict.put(allocator, "Filter", core.pdfName("DCTDecode"));
    try dict.put(allocator, "Length", core.pdfInt(@intCast(data.len)));

    const stream_obj = PdfObject{ .stream_obj = .{
        .dict = dict,
        .data = data,
    } };

    store.put(ref, stream_obj);

    return ImageHandle{
        .ref = ref,
        .width = info.width,
        .height = info.height,
        .format = .jpeg,
    };
}

// -- Tests --

test "parseJpeg: invalid data" {
    const result = parseJpeg(&[_]u8{ 0x00, 0x00 });
    try std.testing.expectError(JpegError.InvalidJpeg, result);
}

test "parseJpeg: too short" {
    const result = parseJpeg(&[_]u8{0xFF});
    try std.testing.expectError(JpegError.InvalidJpeg, result);
}

test "parseJpeg: valid minimal JPEG with SOF0" {
    // SOI + APP0 marker (minimal) + SOF0 marker
    const data = [_]u8{
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, // APP0
        0x00, 0x02, // length = 2 (just the length field)
        0xFF, 0xC0, // SOF0
        0x00, 0x0B, // length = 11
        0x08, // bits per component
        0x00, 0x40, // height = 64
        0x00, 0x80, // width = 128
        0x03, // 3 components (RGB)
        0x01, 0x11, 0x00, // component 1
        0x02, 0x11, 0x01, // component 2
        0x03, 0x11, 0x01, // component 3
    };

    const info = try parseJpeg(&data);
    try std.testing.expectEqual(@as(u32, 128), info.width);
    try std.testing.expectEqual(@as(u32, 64), info.height);
    try std.testing.expectEqual(@as(u8, 3), info.components);
    try std.testing.expectEqual(@as(u8, 8), info.bits_per_component);
    try std.testing.expectEqual(ColorSpace.device_rgb, info.color_space);
}

test "parseJpeg: grayscale" {
    const data = [_]u8{
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, // SOF0
        0x00, 0x08, // length = 8
        0x08, // bits per component
        0x00, 0x10, // height = 16
        0x00, 0x20, // width = 32
        0x01, // 1 component (grayscale)
        0x01, 0x11, 0x00, // component 1
    };

    const info = try parseJpeg(&data);
    try std.testing.expectEqual(@as(u32, 32), info.width);
    try std.testing.expectEqual(@as(u32, 16), info.height);
    try std.testing.expectEqual(ColorSpace.device_gray, info.color_space);
}
