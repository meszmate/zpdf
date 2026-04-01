const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    // Enable PDF/A-1b conformance (basic archival level)
    doc.setPdfAConformance(.pdfa_1b);

    // Set document metadata (reflected in both Info dict and XMP)
    doc.setTitle("PDF/A-1b Archival Document");
    doc.setAuthor("zpdf library");
    doc.setSubject("Demonstration of PDF/A-1b conformance");
    doc.setKeywords("pdf/a, archival, long-term preservation");
    doc.setCreator("zpdf pdfa_document example");

    // Add a page with content
    const page = try doc.addPage(.a4);
    try page.drawText("PDF/A-1b Compliant Document", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = zpdf.rgb(0, 51, 102),
    });

    try page.drawText("This document conforms to the PDF/A-1b standard for long-term archival.", .{
        .x = 72,
        .y = 710,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawText("PDF/A-1b ensures visual appearance is preserved over time by requiring:", .{
        .x = 72,
        .y = 680,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawText("- XMP metadata with PDF/A identification", .{
        .x = 90,
        .y = 656,
        .font = .helvetica,
        .font_size = 11,
    });

    try page.drawText("- Embedded ICC color profile (sRGB)", .{
        .x = 90,
        .y = 638,
        .font = .helvetica,
        .font_size = 11,
    });

    try page.drawText("- No encryption", .{
        .x = 90,
        .y = 620,
        .font = .helvetica,
        .font_size = 11,
    });

    try page.drawText("- PDF version 1.4", .{
        .x = 90,
        .y = 602,
        .font = .helvetica,
        .font_size = 11,
    });

    // Save the PDF/A document
    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("pdfa_document.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created pdfa_document.pdf ({d} bytes, PDF/A-1b)\n", .{bytes.len});
}
