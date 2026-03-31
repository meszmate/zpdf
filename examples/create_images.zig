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

    doc.setTitle("Image Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("Image Embedding Demo", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 0, 0),
    });

    try page.drawText("This example demonstrates the image embedding API pattern.", .{
        .x = 72,
        .y = 755,
        .font = .helvetica,
        .font_size = 11,
        .color = color.rgb(80, 80, 80),
    });

    // Create a synthetic minimal JPEG (smallest valid JPEG: SOI + APP0 + minimal data + EOI).
    // This is a 1x1 pixel red JPEG for demonstration purposes.
    const synthetic_jpeg = [_]u8{
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, // SOI + APP0 header
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, // JFIF identifier
        0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9, // thumbnail + EOI
    };

    // Detect the image format to verify it is recognized as JPEG
    const format = zpdf.image.image_embedder.detectFormat(&synthetic_jpeg);
    if (format) |fmt| {
        const fmt_name: []const u8 = switch (fmt) {
            .jpeg => "JPEG",
            .png => "PNG",
        };
        std.debug.print("Detected image format: {s}\n", .{fmt_name});
    }

    // In a real application, you would embed the image into the document's object store:
    //   const handle = try zpdf.image.image_embedder.embedImage(allocator, &doc.object_store, &jpeg_bytes);
    //   try page.drawImage(handle, .{ .x = 72, .y = 500, .width = 200, .height = 150 });
    //
    // For this demo, we use a placeholder ImageHandle and draw it to show the API.
    const placeholder_handle = ImageHandle{
        .ref = .{ .obj_num = 99, .gen_num = 0 },
        .width = 200,
        .height = 150,
    };

    // Draw a border where the image would appear
    try page.drawRect(.{
        .x = 72,
        .y = 580,
        .width = 200,
        .height = 150,
        .border_color = color.rgb(150, 150, 150),
        .border_width = 1.0,
    });
    try page.drawText("[Image placeholder]", .{
        .x = 115,
        .y = 650,
        .font = .helvetica,
        .font_size = 11,
        .color = color.rgb(150, 150, 150),
    });

    // Show the drawImage API call (content stream operators are written)
    try page.drawImage(placeholder_handle, .{
        .x = 300,
        .y = 580,
        .width = 200,
        .height = 150,
    });
    try page.drawText("drawImage called at (300, 580)", .{
        .x = 300,
        .y = 565,
        .font = .helvetica,
        .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    // API summary
    try page.drawText("Image API usage:", .{
        .x = 72,
        .y = 500,
        .font = .helvetica_bold,
        .font_size = 12,
    });
    try page.drawText("1. Load image bytes from file or memory", .{
        .x = 90, .y = 480, .font = .helvetica, .font_size = 10,
    });
    try page.drawText("2. Call detectFormat() to identify JPEG or PNG", .{
        .x = 90, .y = 465, .font = .helvetica, .font_size = 10,
    });
    try page.drawText("3. Call embedImage() to get an ImageHandle", .{
        .x = 90, .y = 450, .font = .helvetica, .font_size = 10,
    });
    try page.drawText("4. Call page.drawImage(handle, options) to place it", .{
        .x = 90, .y = 435, .font = .helvetica, .font_size = 10,
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("images.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created images.pdf ({d} bytes)\n", .{bytes.len});
}
