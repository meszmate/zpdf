const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const parsePdf = zpdf.parsePdf;
    const color = zpdf.color;

    // Step 1: Create a PDF to parse
    std.debug.print("=== Creating a test PDF ===\n", .{});

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Parseable Document");
    doc.setAuthor("zpdf test suite");
    doc.setSubject("Testing the parser");

    const page1 = try doc.addPage(PageSize.a4);
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page1.addFont(helv.font.pdfName(), helv.ref);

    try page1.drawText("Hello from zpdf!", .{
        .x = 72,
        .y = 750,
        .font = .helvetica,
        .font_size = 18,
        .color = color.rgb(0, 0, 0),
    });
    try page1.drawText("This document will be parsed back.", .{
        .x = 72,
        .y = 720,
        .font = .helvetica,
        .font_size = 12,
    });

    const page2 = try doc.addPage(PageSize.letter);
    const helv2 = try doc.getStandardFont(.helvetica_bold);
    _ = try page2.addFont(helv2.font.pdfName(), helv2.ref);

    try page2.drawText("Second page content", .{
        .x = 72,
        .y = 700,
        .font = .helvetica_bold,
        .font_size = 16,
    });

    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    std.debug.print("Generated PDF: {d} bytes, {d} pages\n\n", .{ pdf_bytes.len, doc.getPageCount() });

    // Step 2: Parse the generated PDF
    std.debug.print("=== Parsing the PDF ===\n", .{});

    var parsed = try parsePdf(allocator, pdf_bytes);
    defer parsed.deinit();

    std.debug.print("PDF Version: {s}\n", .{parsed.version});
    std.debug.print("Pages found: {d}\n", .{parsed.pages.items.len});

    // Print page dimensions
    for (parsed.pages.items, 0..) |parsed_page, i| {
        std.debug.print("\nPage {d}:\n", .{i + 1});
        std.debug.print("  Dimensions: {d:.0} x {d:.0} points\n", .{ parsed_page.width, parsed_page.height });
        std.debug.print("  Content stream length: {d} bytes\n", .{parsed_page.content_data.len});

        // Try to extract text from the page
        const text_items = try parsed_page.extractText(allocator);
        defer allocator.free(text_items);

        if (text_items.len > 0) {
            std.debug.print("  Text items found: {d}\n", .{text_items.len});
            for (text_items) |item| {
                std.debug.print("    - \"{s}\" at ({d:.0}, {d:.0}) font={s} size={d:.0}\n", .{
                    item.text, item.x, item.y, item.font_name, item.font_size,
                });
            }
        } else {
            std.debug.print("  No text items extracted (content may be compressed)\n", .{});
        }
    }

    // Print metadata if available
    if (parsed.info) |info| {
        std.debug.print("\nMetadata:\n", .{});
        if (info.title) |t| std.debug.print("  Title: {s}\n", .{t});
        if (info.author) |a| std.debug.print("  Author: {s}\n", .{a});
        if (info.subject) |s| std.debug.print("  Subject: {s}\n", .{s});
        if (info.producer) |p| std.debug.print("  Producer: {s}\n", .{p});
    }

    std.debug.print("\nParsing complete.\n", .{});
}
