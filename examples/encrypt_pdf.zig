const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    _ = zpdf.EncryptionOptions; // available as zpdf.EncryptionOptions
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Encrypted Document");
    doc.setAuthor("zpdf");

    const page = try doc.addPage(PageSize.a4);
    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

    // Title
    try page.drawText("Encrypted PDF", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 28,
        .color = color.rgb(139, 0, 0),
    });

    // Lock icon (drawn with shapes)
    try page.drawRect(.{
        .x = 72,
        .y = 660,
        .width = 50,
        .height = 40,
        .color = color.rgb(184, 134, 11),
        .corner_radius = 4,
    });
    try page.drawCircle(.{
        .cx = 97,
        .cy = 718,
        .r = 18,
        .border_color = color.rgb(184, 134, 11),
        .border_width = 5.0,
    });

    try page.drawText("This document is password-protected.", .{
        .x = 140,
        .y = 700,
        .font = .helvetica,
        .font_size = 14,
        .color = color.rgb(0, 0, 0),
    });
    try page.drawText("User password: \"reader\"", .{
        .x = 140,
        .y = 678,
        .font = .helvetica,
        .font_size = 11,
        .color = color.rgb(80, 80, 80),
    });
    try page.drawText("Owner password: \"admin123\"", .{
        .x = 140,
        .y = 660,
        .font = .helvetica,
        .font_size = 11,
        .color = color.rgb(80, 80, 80),
    });

    // Some confidential content
    try page.drawRect(.{
        .x = 72,
        .y = 560,
        .width = 451,
        .height = 70,
        .color = color.rgb(255, 248, 220),
        .border_color = color.rgb(218, 165, 32),
        .border_width = 1.0,
        .corner_radius = 6,
    });
    try page.drawText("CONFIDENTIAL: Budget projection Q3 2026 - $1,234,567", .{
        .x = 90,
        .y = 605,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(139, 0, 0),
    });
    try page.drawText("This information is for authorized personnel only.", .{
        .x = 90,
        .y = 585,
        .font = .helvetica,
        .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // Enable encryption
    doc.encrypt(.{
        .user_password = "reader",
        .owner_password = "admin123",
        .permissions = 0xFFFFF0C4, // Allow printing and copying
        .key_length = 128,
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("encrypted.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created encrypted.pdf ({d} bytes)\n", .{bytes.len});
}
