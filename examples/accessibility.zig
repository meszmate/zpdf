const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const StructureTree = zpdf.StructureTree;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Accessible PDF");
    doc.setAuthor("zpdf");
    doc.setSubject("Tagged PDF with structure tree for accessibility");

    const page = try doc.addPage(PageSize.a4);
    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);
    const times = try doc.getStandardFont(.times_roman);
    _ = try page.addFont(times.font.pdfName(), times.ref);

    // Build a structure tree for accessibility
    var tree = StructureTree.init(allocator);
    defer tree.deinit();

    // Document root
    try tree.beginElement(.document);

    // Section 1: Header
    try tree.beginElement(.section);

    try tree.beginElement(.h1);
    try page.drawText("Accessible PDF Document", .{
        .x = 72,
        .y = 760,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = color.rgb(0, 51, 102),
    });
    try tree.endElement(); // /H1

    try tree.beginElement(.p);
    try page.drawText("This document uses a structure tree for PDF/UA compliance.", .{
        .x = 72,
        .y = 730,
        .font = .helvetica,
        .font_size = 12,
        .color = color.rgb(60, 60, 60),
    });
    try tree.endElement(); // /P

    try tree.endElement(); // /Section 1

    // Section 2: Content
    try tree.beginElement(.section);

    try tree.beginElement(.h2);
    try page.drawText("Introduction", .{
        .x = 72,
        .y = 690,
        .font = .helvetica_bold,
        .font_size = 18,
        .color = color.rgb(0, 51, 102),
    });
    try tree.endElement(); // /H2

    try tree.beginElement(.p);
    try page.drawText("Tagged PDFs provide a logical structure that assistive technologies", .{
        .x = 72,
        .y = 665,
        .font = .times_roman,
        .font_size = 12,
    });
    try tree.endElement(); // /P

    try tree.beginElement(.p);
    try page.drawText("can use to present content in a meaningful order to users.", .{
        .x = 72,
        .y = 645,
        .font = .times_roman,
        .font_size = 12,
    });
    try tree.endElement(); // /P

    // A list
    try tree.beginElement(.list);

    try tree.beginElement(.list_item);
    try page.drawText("  - Screen readers can navigate headings", .{
        .x = 72,
        .y = 615,
        .font = .helvetica,
        .font_size = 11,
    });
    try tree.endElement(); // /LI

    try tree.beginElement(.list_item);
    try page.drawText("  - Tables are read cell by cell", .{
        .x = 72,
        .y = 597,
        .font = .helvetica,
        .font_size = 11,
    });
    try tree.endElement(); // /LI

    try tree.beginElement(.list_item);
    try page.drawText("  - Images have alt text via Figure tags", .{
        .x = 72,
        .y = 579,
        .font = .helvetica,
        .font_size = 11,
    });
    try tree.endElement(); // /LI

    try tree.endElement(); // /List

    // A figure element
    try tree.beginElement(.figure);
    try page.drawRect(.{
        .x = 72,
        .y = 480,
        .width = 200,
        .height = 80,
        .color = color.rgb(230, 240, 250),
        .border_color = color.rgb(100, 149, 237),
        .border_width = 1.0,
    });
    try page.drawText("[Figure: Decorative chart]", .{
        .x = 105,
        .y = 515,
        .font = .helvetica,
        .font_size = 10,
        .color = color.rgb(100, 100, 100),
    });
    try tree.endElement(); // /Figure

    try tree.endElement(); // /Section 2

    try tree.endElement(); // /Document

    // Report structure tree stats
    std.debug.print("Structure tree: {d} nodes, depth now {d}\n", .{
        tree.nodeCount(),
        tree.depth(),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("accessible.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created accessible.pdf ({d} bytes)\n", .{bytes.len});
}
