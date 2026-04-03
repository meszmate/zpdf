const std = @import("std");
const zpdf = @import("zpdf");
const jpeg2000_handler = zpdf.image.jpeg2000_handler;
const Jpeg2000Info = jpeg2000_handler.Jpeg2000Info;
const Jpeg2000Error = jpeg2000_handler.Jpeg2000Error;
const image_embedder = zpdf.image.image_embedder;
const ImageFormat = image_embedder.ImageFormat;

test "detectFormat identifies JP2 container" {
    const jp2_data = [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A, 0x00, 0x00 };
    try std.testing.expectEqual(ImageFormat.jpeg2000, image_embedder.detectFormat(&jp2_data).?);
}

test "detectFormat identifies J2K codestream" {
    const j2k_data = [_]u8{ 0xFF, 0x4F, 0xFF, 0x51 };
    try std.testing.expectEqual(ImageFormat.jpeg2000, image_embedder.detectFormat(&j2k_data).?);
}

test "parseJpeg2000 rejects empty data" {
    const result = jpeg2000_handler.parseJpeg2000(&[_]u8{});
    try std.testing.expectError(Jpeg2000Error.InvalidJpeg2000, result);
}

test "parseJpeg2000 rejects garbage data" {
    const result = jpeg2000_handler.parseJpeg2000(&[_]u8{ 0x12, 0x34, 0x56, 0x78 });
    try std.testing.expectError(Jpeg2000Error.InvalidJpeg2000, result);
}

test "parseJpeg2000 parses J2K codestream RGB" {
    const data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ
        0x00, 0x29, // Lsiz = 41
        0x00, 0x00, // Rsiz
        0x00, 0x00, 0x03, 0x20, // Xsiz = 800
        0x00, 0x00, 0x02, 0x58, // Ysiz = 600
        0x00, 0x00, 0x00, 0x00, // XOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YOsiz = 0
        0x00, 0x00, 0x03, 0x20, // XTsiz
        0x00, 0x00, 0x02, 0x58, // YTsiz
        0x00, 0x00, 0x00, 0x00, // XTOsiz
        0x00, 0x00, 0x00, 0x00, // YTOsiz
        0x00, 0x03, // Csiz = 3
        0x07, 0x01, 0x01, // Component 0: 8 bits
        0x07, 0x01, 0x01, // Component 1
        0x07, 0x01, 0x01, // Component 2
    };

    const info = try jpeg2000_handler.parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 800), info.width);
    try std.testing.expectEqual(@as(u32, 600), info.height);
    try std.testing.expectEqual(@as(u16, 3), info.num_components);
    try std.testing.expectEqual(@as(u8, 8), info.bits_per_component);
    try std.testing.expectEqual(false, info.is_jp2);
}

test "parseJpeg2000 parses J2K codestream grayscale 16-bit" {
    const data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ
        0x00, 0x27, // Lsiz = 39
        0x00, 0x00, // Rsiz
        0x00, 0x00, 0x01, 0x00, // Xsiz = 256
        0x00, 0x00, 0x01, 0x00, // Ysiz = 256
        0x00, 0x00, 0x00, 0x00, // XOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YOsiz = 0
        0x00, 0x00, 0x01, 0x00, // XTsiz
        0x00, 0x00, 0x01, 0x00, // YTsiz
        0x00, 0x00, 0x00, 0x00, // XTOsiz
        0x00, 0x00, 0x00, 0x00, // YTOsiz
        0x00, 0x01, // Csiz = 1
        0x0F, 0x01, 0x01, // Component 0: Ssiz=15 -> 16 bits
    };

    const info = try jpeg2000_handler.parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 256), info.width);
    try std.testing.expectEqual(@as(u32, 256), info.height);
    try std.testing.expectEqual(@as(u16, 1), info.num_components);
    try std.testing.expectEqual(@as(u8, 16), info.bits_per_component);
}

test "parseJpeg2000 parses JP2 container with ihdr" {
    const data = [_]u8{
        // Signature box (12 bytes)
        0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A,
        // File type box (20 bytes)
        0x00, 0x00, 0x00, 0x14,
        0x66, 0x74, 0x79, 0x70,
        0x6A, 0x70, 0x32, 0x20,
        0x00, 0x00, 0x00, 0x00,
        0x6A, 0x70, 0x32, 0x20,
        // JP2 Header superbox containing ihdr
        0x00, 0x00, 0x00, 0x1E,
        0x6A, 0x70, 0x32, 0x68,
        // Image Header box (ihdr)
        0x00, 0x00, 0x00, 0x16,
        0x69, 0x68, 0x64, 0x72,
        0x00, 0x00, 0x04, 0x00, // height = 1024
        0x00, 0x00, 0x08, 0x00, // width = 2048
        0x00, 0x04, // num_components = 4
        0x07, // bpc = 7 -> 8 bits
        0x07, // compression type
        0x00, // colorspace unknown
        0x00, // intellectual property
    };

    const info = try jpeg2000_handler.parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 2048), info.width);
    try std.testing.expectEqual(@as(u32, 1024), info.height);
    try std.testing.expectEqual(@as(u16, 4), info.num_components);
    try std.testing.expectEqual(@as(u8, 8), info.bits_per_component);
    try std.testing.expectEqual(true, info.is_jp2);
}

test "parseJpeg2000 rejects J2K with missing SIZ" {
    const data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x52, // not SIZ (0x52 instead of 0x51)
    };
    const result = jpeg2000_handler.parseJpeg2000(&data);
    try std.testing.expectError(Jpeg2000Error.InvalidJpeg2000, result);
}

test "parseJpeg2000 with image offset" {
    // Test that width/height correctly subtracts the origin offset
    const data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ
        0x00, 0x29, // Lsiz = 41
        0x00, 0x00, // Rsiz
        0x00, 0x00, 0x04, 0x00, // Xsiz = 1024
        0x00, 0x00, 0x03, 0x00, // Ysiz = 768
        0x00, 0x00, 0x00, 0x10, // XOsiz = 16
        0x00, 0x00, 0x00, 0x08, // YOsiz = 8
        0x00, 0x00, 0x04, 0x00, // XTsiz
        0x00, 0x00, 0x03, 0x00, // YTsiz
        0x00, 0x00, 0x00, 0x00, // XTOsiz
        0x00, 0x00, 0x00, 0x00, // YTOsiz
        0x00, 0x03, // Csiz = 3
        0x07, 0x01, 0x01, // Component 0
        0x07, 0x01, 0x01, // Component 1
        0x07, 0x01, 0x01, // Component 2
    };

    const info = try jpeg2000_handler.parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 1024 - 16), info.width);
    try std.testing.expectEqual(@as(u32, 768 - 8), info.height);
}

test "embedJpeg2000 creates valid image handle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ObjectStore = zpdf.ObjectStore;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    // Minimal valid J2K codestream
    const data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ
        0x00, 0x29, // Lsiz = 41
        0x00, 0x00, // Rsiz
        0x00, 0x00, 0x00, 0x40, // Xsiz = 64
        0x00, 0x00, 0x00, 0x20, // Ysiz = 32
        0x00, 0x00, 0x00, 0x00, // XOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YOsiz = 0
        0x00, 0x00, 0x00, 0x40, // XTsiz
        0x00, 0x00, 0x00, 0x20, // YTsiz
        0x00, 0x00, 0x00, 0x00, // XTOsiz
        0x00, 0x00, 0x00, 0x00, // YTOsiz
        0x00, 0x03, // Csiz = 3
        0x07, 0x01, 0x01,
        0x07, 0x01, 0x01,
        0x07, 0x01, 0x01,
    };

    const handle = try jpeg2000_handler.embedJpeg2000(allocator, &store, &data);
    try std.testing.expectEqual(@as(u32, 64), handle.width);
    try std.testing.expectEqual(@as(u32, 32), handle.height);
    try std.testing.expectEqual(ImageFormat.jpeg2000, handle.format);
}
