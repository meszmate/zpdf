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

    doc.setTitle("Named Destinations Example");
    doc.setAuthor("zpdf");
    doc.setSubject("Demonstrating internal links and table of contents");

    // Register font
    const helv = try doc.getStandardFont(.helvetica);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);

    // -- Page 0: Table of Contents --
    const toc_page = try doc.addPage(PageSize.a4);
    _ = try toc_page.addFont(helv.font.pdfName(), helv.ref);
    _ = try toc_page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try toc_page.drawText("Table of Contents", .{
        .x = 72,
        .y = 770,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = color.rgb(0, 51, 102),
    });

    // -- Page 1: Introduction --
    const page1 = try doc.addPage(PageSize.a4);
    _ = try page1.addFont(helv.font.pdfName(), helv.ref);
    _ = try page1.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try page1.drawText("1. Introduction", .{
        .x = 72,
        .y = 770,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 51, 102),
    });

    try page1.drawText("This is the introduction section of the document.", .{
        .x = 72,
        .y = 740,
        .font = .helvetica,
        .font_size = 12,
    });

    // -- Page 2: Getting Started --
    const page2 = try doc.addPage(PageSize.a4);
    _ = try page2.addFont(helv.font.pdfName(), helv.ref);
    _ = try page2.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try page2.drawText("2. Getting Started", .{
        .x = 72,
        .y = 770,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 51, 102),
    });

    try page2.drawText("This section covers the basics of getting started.", .{
        .x = 72,
        .y = 740,
        .font = .helvetica,
        .font_size = 12,
    });

    // -- Page 3: Advanced Topics --
    const page3 = try doc.addPage(PageSize.a4);
    _ = try page3.addFont(helv.font.pdfName(), helv.ref);
    _ = try page3.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try page3.drawText("3. Advanced Topics", .{
        .x = 72,
        .y = 770,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 51, 102),
    });

    try page3.drawText("This section dives into advanced features and usage patterns.", .{
        .x = 72,
        .y = 740,
        .font = .helvetica,
        .font_size = 12,
    });

    // -- Page 4: API Reference --
    const page4 = try doc.addPage(PageSize.a4);
    _ = try page4.addFont(helv.font.pdfName(), helv.ref);
    _ = try page4.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try page4.drawText("4. API Reference", .{
        .x = 72,
        .y = 770,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 51, 102),
    });

    try page4.drawText("Full API documentation for all public types and functions.", .{
        .x = 72,
        .y = 740,
        .font = .helvetica,
        .font_size = 12,
    });

    // Render table of contents on page 0 with clickable links
    const toc_entries = [_]zpdf.TocEntry{
        .{ .title = "Introduction", .page_index = 1, .level = 0 },
        .{ .title = "Getting Started", .page_index = 2, .level = 0 },
        .{ .title = "Installation", .page_index = 2, .level = 1 },
        .{ .title = "First Steps", .page_index = 2, .level = 1 },
        .{ .title = "Advanced Topics", .page_index = 3, .level = 0 },
        .{ .title = "API Reference", .page_index = 4, .level = 0 },
    };

    _ = try doc.renderToc(0, &toc_entries, .{
        .start_y = 730,
        .title_color = color.rgb(0, 0, 0),
    });

    // Also add a manual internal link on page 1 pointing back to TOC
    try doc.addNamedDestination(.{
        .name = "toc_page",
        .page_index = 0,
        .dest_type = .fit,
    });

    try doc.addInternalLink(1, .{
        .rect = .{ 72, 50, 200, 64 },
        .dest_name = "toc_page",
    });

    // Draw "Back to TOC" text on page 1
    try page1.drawText("Back to Table of Contents", .{
        .x = 72,
        .y = 52,
        .font = .helvetica,
        .font_size = 10,
        .color = color.rgb(0, 0, 200),
    });

    // Save the document
    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("named_destinations.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created named_destinations.pdf ({d} bytes, {d} pages)\n", .{ bytes.len, doc.getPageCount() });
}
