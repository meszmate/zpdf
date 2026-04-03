const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Ref = core.Ref;
const jpeg_handler = @import("jpeg_handler.zig");
const png_handler = @import("png_handler.zig");
const jpeg2000_handler = @import("jpeg2000_handler.zig");

/// Supported image formats.
pub const ImageFormat = enum {
    jpeg,
    png,
    jpeg2000,
};

/// A handle to an embedded image in the PDF object store.
pub const ImageHandle = struct {
    ref: Ref,
    width: u32,
    height: u32,
    format: ImageFormat,
};

pub const ImageError = error{
    UnknownFormat,
};

/// Detect image format from magic bytes at the start of the data.
pub fn detectFormat(data: []const u8) ?ImageFormat {
    // JPEG: starts with 0xFFD8
    if (data.len >= 2 and data[0] == 0xFF and data[1] == 0xD8) {
        return .jpeg;
    }

    // PNG: starts with 137 80 78 71 13 10 26 10
    if (data.len >= 8 and
        data[0] == 137 and data[1] == 80 and data[2] == 78 and data[3] == 71 and
        data[4] == 13 and data[5] == 10 and data[6] == 26 and data[7] == 10)
    {
        return .png;
    }

    // JPEG 2000 JP2 container: starts with signature box 0x0000000C 6A502020 0D0A870A
    if (data.len >= 12 and
        data[0] == 0x00 and data[1] == 0x00 and data[2] == 0x00 and data[3] == 0x0C and
        data[4] == 0x6A and data[5] == 0x50 and data[6] == 0x20 and data[7] == 0x20 and
        data[8] == 0x0D and data[9] == 0x0A and data[10] == 0x87 and data[11] == 0x0A)
    {
        return .jpeg2000;
    }

    // JPEG 2000 raw codestream (J2K): starts with SOC marker 0xFF4F
    if (data.len >= 2 and data[0] == 0xFF and data[1] == 0x4F) {
        return .jpeg2000;
    }

    return null;
}

/// Auto-detect image format and embed the image into the PDF object store.
pub fn embedImage(allocator: Allocator, store: *ObjectStore, data: []const u8) !ImageHandle {
    const format = detectFormat(data) orelse return ImageError.UnknownFormat;

    return switch (format) {
        .jpeg => try jpeg_handler.embedJpeg(allocator, store, data),
        .png => try png_handler.embedPng(allocator, store, data),
        .jpeg2000 => try jpeg2000_handler.embedJpeg2000(allocator, store, data),
    };
}

// -- Tests --

test "detectFormat: JPEG" {
    const jpeg_data = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0 };
    try std.testing.expectEqual(ImageFormat.jpeg, detectFormat(&jpeg_data).?);
}

test "detectFormat: PNG" {
    const png_data = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13 };
    try std.testing.expectEqual(ImageFormat.png, detectFormat(&png_data).?);
}

test "detectFormat: JPEG 2000 JP2 container" {
    const jp2_data = [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A };
    try std.testing.expectEqual(ImageFormat.jpeg2000, detectFormat(&jp2_data).?);
}

test "detectFormat: JPEG 2000 J2K codestream" {
    const j2k_data = [_]u8{ 0xFF, 0x4F, 0xFF, 0x51 };
    try std.testing.expectEqual(ImageFormat.jpeg2000, detectFormat(&j2k_data).?);
}

test "detectFormat: unknown" {
    const unknown = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    try std.testing.expect(detectFormat(&unknown) == null);
}

test "detectFormat: too short" {
    const short = [_]u8{0xFF};
    try std.testing.expect(detectFormat(&short) == null);
}
