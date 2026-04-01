const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const TextSpan = zpdf.TextSpan;
    const RichTextOptions = zpdf.RichTextOptions;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Hyphenation Example");
    doc.setAuthor("zpdf");

    const page = try doc.addPage(PageSize.a4);

    // Register fonts
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    // Title
    try page.drawText("Hyphenation Demo", .{
        .x = 72,
        .y = 760,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = color.rgb(0, 51, 102),
    });

    try page.drawLine(.{
        .x1 = 72,
        .y1 = 750,
        .x2 = 523,
        .y2 = 750,
        .color = color.rgb(0, 51, 102),
        .line_width = 1.0,
    });

    const sample_text = "The internationalization of communication technology represents an extraordinary development in modern civilization. Professional organizations increasingly recognize the importance of standardization and interoperability across different technological platforms and geographical boundaries.";

    // Column width for side-by-side comparison
    const col_width: f32 = 210;

    // Left column label: Without Hyphenation
    try page.drawText("Without Hyphenation", .{
        .x = 72,
        .y = 720,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(102, 0, 0),
    });

    // Left column: no hyphenation, justified
    const spans_left = [_]TextSpan{
        .{ .text = sample_text, .font = .helvetica, .font_size = 11 },
    };
    _ = try page.drawRichText(&spans_left, RichTextOptions{
        .x = 72,
        .y = 700,
        .max_width = col_width,
        .alignment = .justify,
        .hyphenate = false,
    });

    // Right column label: With Hyphenation
    try page.drawText("With Hyphenation", .{
        .x = 306,
        .y = 720,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(0, 102, 0),
    });

    // Right column: with hyphenation, justified
    const spans_right = [_]TextSpan{
        .{ .text = sample_text, .font = .helvetica, .font_size = 11 },
    };
    _ = try page.drawRichText(&spans_right, RichTextOptions{
        .x = 306,
        .y = 700,
        .max_width = col_width,
        .alignment = .justify,
        .hyphenate = true,
    });

    // Separator line
    try page.drawLine(.{
        .x1 = 290,
        .y1 = 730,
        .x2 = 290,
        .y2 = 550,
        .color = color.rgb(180, 180, 180),
        .line_width = 0.5,
    });

    // Save
    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("hyphenation.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);
}
