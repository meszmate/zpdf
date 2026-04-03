const std = @import("std");
const zpdf = @import("zpdf");

test "text_extractor: extract from created PDF" {
    const allocator = std.testing.allocator;

    // Create a PDF with known text
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    var page = try doc.addPage(.a4);
    try page.drawText("Hello World", .{ .x = 72, .y = 720, .font = .helvetica, .font_size = 12 });
    try page.drawText("Second Line", .{ .x = 72, .y = 700, .font = .helvetica, .font_size = 12 });

    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    // Parse it back
    var parsed = try zpdf.parsePdf(allocator, pdf_bytes);
    defer parsed.deinit();

    try std.testing.expect(parsed.pages.items.len >= 1);
}

test "text_extractor: ExtractionOptions defaults" {
    const opts = zpdf.parser.text_extractor.ExtractionOptions{};
    try std.testing.expect(opts.line_tolerance == 2.0);
    try std.testing.expect(opts.paragraph_gap_factor == 1.5);
    try std.testing.expect(opts.sort_by_position == true);
    try std.testing.expect(opts.avg_char_width_factor == 0.5);
}

test "text_extractor: TextFragment struct" {
    const frag = zpdf.parser.text_extractor.TextFragment{
        .text = "Hello",
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
        .width = 30,
    };
    try std.testing.expectEqualStrings("Hello", frag.text);
    try std.testing.expect(frag.x == 72.0);
}

test "text_extractor: TextLine getText" {
    const allocator = std.testing.allocator;
    const frags = [_]zpdf.parser.text_extractor.TextFragment{
        .{ .text = "Hello", .x = 0, .y = 0, .font_name = "F1", .font_size = 12, .width = 30 },
        .{ .text = "World", .x = 40, .y = 0, .font_name = "F1", .font_size = 12, .width = 30 },
    };
    const line = zpdf.parser.text_extractor.TextLine{
        .fragments = &frags,
        .y = 0,
        .min_x = 0,
        .max_x = 70,
    };

    const text = try line.getText(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Hello World", text);
}
