const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Basic Example");
    doc.setAuthor("zpdf");
    doc.setSubject("Demonstrating basic text rendering");

    const page = try doc.addPage(PageSize.a4);

    // Register fonts on the page
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    const times = try doc.getStandardFont(.times_roman);
    _ = try page.addFont(times.font.pdfName(), times.ref);

    const courier = try doc.getStandardFont(.courier);
    _ = try page.addFont(courier.font.pdfName(), courier.ref);

    // Title in large bold text
    try page.drawText("zpdf - Basic Example", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = color.rgb(0, 51, 102),
    });

    // Subtitle in italic
    try page.drawText("A simple PDF created with the zpdf Zig library", .{
        .x = 72,
        .y = 720,
        .font = .helvetica,
        .font_size = 12,
        .color = color.rgb(100, 100, 100),
    });

    // Separator line
    try page.drawLine(.{
        .x1 = 72,
        .y1 = 710,
        .x2 = 523,
        .y2 = 710,
        .color = color.rgb(0, 51, 102),
        .line_width = 1.5,
    });

    // Body text in different fonts
    try page.drawText("Helvetica 12pt - The quick brown fox jumps over the lazy dog.", .{
        .x = 72,
        .y = 680,
        .font = .helvetica,
        .font_size = 12,
        .color = .{ .named = .black },
    });

    try page.drawText("Times Roman 14pt - Pack my box with five dozen liquor jugs.", .{
        .x = 72,
        .y = 655,
        .font = .times_roman,
        .font_size = 14,
        .color = color.rgb(139, 0, 0),
    });

    try page.drawText("Courier 10pt - Fixed-width font for code snippets.", .{
        .x = 72,
        .y = 630,
        .font = .courier,
        .font_size = 10,
        .color = color.rgb(0, 100, 0),
    });

    // Color showcase
    try page.drawText("Red text", .{ .x = 72, .y = 590, .font_size = 16, .color = .{ .named = .red } });
    try page.drawText("Blue text", .{ .x = 72, .y = 565, .font_size = 16, .color = .{ .named = .blue } });
    try page.drawText("Custom hex color", .{ .x = 72, .y = 540, .font_size = 16, .color = try color.hexColor("#FF6600") });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("basic.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created basic.pdf ({d} bytes)\n", .{bytes.len});
}
