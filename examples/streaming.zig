const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const clr = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Streaming Example");
    doc.setAuthor("zpdf");
    doc.setSubject("Demonstrating streaming PDF output");

    // Create several pages
    {
        const page = try doc.addPage(PageSize.a4);
        const helv = try doc.getStandardFont(.helvetica_bold);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);

        try page.drawText("Page 1 - Streaming PDF Output", .{
            .x = 72,
            .y = 750,
            .font = .helvetica_bold,
            .font_size = 24,
            .color = clr.rgb(0, 51, 102),
        });

        try page.drawText("This PDF was written directly to a file using streamPdf.", .{
            .x = 72,
            .y = 700,
            .font = .helvetica_bold,
            .font_size = 12,
            .color = clr.rgb(80, 80, 80),
        });
    }

    {
        const page = try doc.addPage(PageSize.a4);
        const helv = try doc.getStandardFont(.helvetica);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);

        try page.drawText("Page 2 - No intermediate buffer needed", .{
            .x = 72,
            .y = 750,
            .font = .helvetica,
            .font_size = 18,
            .color = clr.rgb(0, 0, 0),
        });
    }

    {
        const page = try doc.addPage(PageSize.letter);
        try page.drawText("Page 3 - Letter size page", .{
            .x = 72,
            .y = 700,
            .font_size = 14,
        });
    }

    // Stream to an in-memory buffer using the unmanaged ArrayList writer
    var list_buf: std.ArrayListUnmanaged(u8) = .{};
    defer list_buf.deinit(allocator);
    try doc.saveTo(allocator, list_buf.writer(allocator));

    // Write the result to a file
    const file = try std.fs.cwd().createFile("streaming.pdf", .{});
    defer file.close();
    try file.writeAll(list_buf.items);

    std.debug.print("Created streaming.pdf ({d} bytes)\n", .{list_buf.items.len});
}
