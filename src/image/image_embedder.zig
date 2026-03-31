const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Ref = core.Ref;
const jpeg_handler = @import("jpeg_handler.zig");
const png_handler = @import("png_handler.zig");

/// Supported image formats.
pub const ImageFormat = enum {
    jpeg,
    png,
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

    return null;
}

/// Auto-detect image format and embed the image into the PDF object store.
pub fn embedImage(allocator: Allocator, store: *ObjectStore, data: []const u8) !ImageHandle {
    const format = detectFormat(data) orelse return ImageError.UnknownFormat;

    return switch (format) {
        .jpeg => try jpeg_handler.embedJpeg(allocator, store, data),
        .png => try png_handler.embedPng(allocator, store, data),
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

test "detectFormat: unknown" {
    const unknown = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    try std.testing.expect(detectFormat(&unknown) == null);
}

test "detectFormat: too short" {
    const short = [_]u8{0xFF};
    try std.testing.expect(detectFormat(&short) == null);
}
