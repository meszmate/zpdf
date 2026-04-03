const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const ImageHandle = zpdf.ImageHandle;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("JPEG 2000 Image Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("JPEG 2000 Image Embedding Demo", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 0, 0),
    });

    try page.drawText("This example demonstrates JPEG 2000 (JP2/J2K) image support.", .{
        .x = 72,
        .y = 755,
        .font = .helvetica,
        .font_size = 11,
        .color = color.rgb(80, 80, 80),
    });

    // Demonstrate JP2 format detection
    const jp2_signature = [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A };
    const j2k_signature = [_]u8{ 0xFF, 0x4F, 0xFF, 0x51 };

    const jp2_format = zpdf.image.image_embedder.detectFormat(&jp2_signature);
    const j2k_format = zpdf.image.image_embedder.detectFormat(&j2k_signature);

    if (jp2_format) |fmt| {
        const name: []const u8 = switch (fmt) {
            .jpeg => "JPEG",
            .png => "PNG",
            .jpeg2000 => "JPEG2000",
        };
        std.debug.print("JP2 container detected as: {s}\n", .{name});
    }

    if (j2k_format) |fmt| {
        const name: []const u8 = switch (fmt) {
            .jpeg => "JPEG",
            .png => "PNG",
            .jpeg2000 => "JPEG2000",
        };
        std.debug.print("J2K codestream detected as: {s}\n", .{name});
    }

    // Demonstrate JPEG 2000 header parsing
    const Jpeg2000Info = zpdf.image.jpeg2000_handler.Jpeg2000Info;
    _ = Jpeg2000Info;

    // Parse a synthetic J2K codestream header
    const synthetic_j2k = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ marker
        0x00, 0x29, // Lsiz = 41
        0x00, 0x00, // Rsiz
        0x00, 0x00, 0x02, 0x00, // Xsiz = 512
        0x00, 0x00, 0x01, 0x00, // Ysiz = 256
        0x00, 0x00, 0x00, 0x00, // XOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YOsiz = 0
        0x00, 0x00, 0x02, 0x00, // XTsiz
        0x00, 0x00, 0x01, 0x00, // YTsiz
        0x00, 0x00, 0x00, 0x00, // XTOsiz
        0x00, 0x00, 0x00, 0x00, // YTOsiz
        0x00, 0x03, // Csiz = 3
        0x07, 0x01, 0x01, // Component 0: 8 bits
        0x07, 0x01, 0x01, // Component 1
        0x07, 0x01, 0x01, // Component 2
    };

    if (zpdf.image.jpeg2000_handler.parseJpeg2000(&synthetic_j2k)) |info| {
        std.debug.print("Parsed J2K: {d}x{d}, {d} components, {d} bpc\n", .{
            info.width, info.height, info.num_components, info.bits_per_component,
        });
    } else |_| {}

    // In a real application with a JPEG 2000 file:
    //   const handle = try zpdf.image.image_embedder.embedImage(allocator, &doc.object_store, &jp2_bytes);
    //   try page.drawImage(handle, .{ .x = 72, .y = 500, .width = 200, .height = 150 });
    //
    // The PDF uses /JPXDecode filter -- the viewer handles JP2 decompression natively.
    const placeholder_handle = ImageHandle{
        .ref = .{ .obj_num = 99, .gen_num = 0 },
        .width = 200,
        .height = 150,
    };

    try page.drawRect(.{
        .x = 72,
        .y = 580,
        .width = 200,
        .height = 150,
        .border_color = color.rgb(150, 150, 150),
        .border_width = 1.0,
    });
    try page.drawText("[JPEG 2000 image placeholder]", .{
        .x = 90,
        .y = 650,
        .font = .helvetica,
        .font_size = 10,
        .color = color.rgb(150, 150, 150),
    });

    try page.drawImage(placeholder_handle, .{
        .x = 300,
        .y = 580,
        .width = 200,
        .height = 150,
    });

    // API summary
    try page.drawText("JPEG 2000 API usage:", .{
        .x = 72,
        .y = 500,
        .font = .helvetica_bold,
        .font_size = 12,
    });
    try page.drawText("1. Supports both JP2 container and raw J2K codestream formats", .{
        .x = 90, .y = 480, .font = .helvetica, .font_size = 10,
    });
    try page.drawText("2. detectFormat() identifies JPEG 2000 from magic bytes", .{
        .x = 90, .y = 465, .font = .helvetica, .font_size = 10,
    });
    try page.drawText("3. embedImage() creates XObject with /JPXDecode filter", .{
        .x = 90, .y = 450, .font = .helvetica, .font_size = 10,
    });
    try page.drawText("4. PDF viewers handle JPEG 2000 decompression natively", .{
        .x = 90, .y = 435, .font = .helvetica, .font_size = 10,
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("jpeg2000_images.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created jpeg2000_images.pdf ({d} bytes)\n", .{bytes.len});
}
