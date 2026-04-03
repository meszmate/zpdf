const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a PDF with some text
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Text Extraction Example");

    var page = try doc.addPage(.a4);
    try page.drawText("Title: Text Extraction Demo", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 18,
    });

    try page.drawText("This is the first paragraph of the document.", .{
        .x = 72,
        .y = 700,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawText("It contains multiple lines of text.", .{
        .x = 72,
        .y = 686,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawText("This is a second paragraph with a gap above.", .{
        .x = 72,
        .y = 650,
        .font = .helvetica,
        .font_size = 12,
    });

    // Save the PDF
    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    const file = try std.fs.cwd().createFile("text_extraction.pdf", .{});
    defer file.close();
    try file.writeAll(pdf_bytes);

    // Parse it back and extract text
    var parsed = try zpdf.parsePdf(allocator, pdf_bytes);
    defer parsed.deinit();

    std.debug.print("Parsed {d} page(s)\n", .{parsed.pages.items.len});

    for (parsed.pages.items, 0..) |*parsed_page, i| {
        std.debug.print("\n--- Page {d} ---\n", .{i + 1});

        var result = try zpdf.parser.text_extractor.extractText(allocator, parsed_page, .{});
        defer result.deinit();

        std.debug.print("Fragments: {d}\n", .{result.fragments.len});
        std.debug.print("Lines: {d}\n", .{result.lines.len});
        std.debug.print("\nExtracted text:\n{s}\n", .{result.plain_text});
    }
}
