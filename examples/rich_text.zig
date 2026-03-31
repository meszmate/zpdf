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

    doc.setTitle("Rich Text Example");
    doc.setAuthor("zpdf");

    const page = try doc.addPage(PageSize.a4);

    // Register all fonts we will use
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    const times_bold = try doc.getStandardFont(.times_bold);
    _ = try page.addFont(times_bold.font.pdfName(), times_bold.ref);

    const helv_oblique = try doc.getStandardFont(.helvetica_oblique);
    _ = try page.addFont(helv_oblique.font.pdfName(), helv_oblique.ref);

    // Title
    try page.drawText("Rich Text Demo", .{
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
        .line_width = 1.5,
    });

    // Mixed fonts and colors paragraph
    const mixed_spans = [_]TextSpan{
        .{ .text = "This is ", .font = .helvetica, .font_size = 12 },
        .{ .text = "bold text", .font = .helvetica_bold, .font_size = 12 },
        .{ .text = " mixed with ", .font = .helvetica, .font_size = 12 },
        .{ .text = "large colored text", .font = .times_bold, .font_size = 18, .color = .{ .named = .red } },
        .{ .text = " in a single paragraph. ", .font = .helvetica, .font_size = 12 },
        .{ .text = "Styles can change freely within the text flow.", .font = .helvetica_oblique, .font_size = 12, .color = color.rgb(0, 100, 0) },
    };

    var y_offset = try page.drawRichText(&mixed_spans, RichTextOptions{
        .x = 72,
        .y = 720,
        .max_width = 451,
    });

    // Superscript example: E = mc^2
    const superscript_spans = [_]TextSpan{
        .{ .text = "Einstein's famous equation: E = mc", .font = .helvetica, .font_size = 14 },
        .{ .text = "2", .font = .helvetica, .font_size = 9, .rise = 5 },
        .{ .text = " demonstrates superscript support.", .font = .helvetica, .font_size = 14 },
    };

    const super_y = 720 - y_offset - 20;
    y_offset = try page.drawRichText(&superscript_spans, RichTextOptions{
        .x = 72,
        .y = super_y,
        .max_width = 451,
    });

    // Underline and strikethrough
    const deco_spans = [_]TextSpan{
        .{ .text = "This text is ", .font = .helvetica, .font_size = 12 },
        .{ .text = "underlined", .font = .helvetica, .font_size = 12, .underline = true, .color = .{ .named = .blue } },
        .{ .text = " and this is ", .font = .helvetica, .font_size = 12 },
        .{ .text = "struck through", .font = .helvetica, .font_size = 12, .strikethrough = true, .color = .{ .named = .red } },
        .{ .text = " to show text decorations.", .font = .helvetica, .font_size = 12 },
    };

    const deco_y = super_y - y_offset - 20;
    y_offset = try page.drawRichText(&deco_spans, RichTextOptions{
        .x = 72,
        .y = deco_y,
        .max_width = 451,
    });

    // Justified text with mixed styles
    const justify_spans = [_]TextSpan{
        .{ .text = "This paragraph uses justified alignment, which spreads words evenly across the full width. ", .font = .helvetica, .font_size = 12 },
        .{ .text = "Bold phrases ", .font = .helvetica_bold, .font_size = 12 },
        .{ .text = "and ", .font = .helvetica, .font_size = 12 },
        .{ .text = "italic phrases ", .font = .helvetica_oblique, .font_size = 12 },
        .{ .text = "are mixed freely within the justified block to demonstrate that alignment works correctly with mixed styling.", .font = .helvetica, .font_size = 12 },
    };

    const justify_y = deco_y - y_offset - 20;
    _ = try page.drawRichText(&justify_spans, RichTextOptions{
        .x = 72,
        .y = justify_y,
        .max_width = 451,
        .alignment = .justify,
        .first_line_indent = 24,
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("rich_text.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created rich_text.pdf ({d} bytes)\n", .{bytes.len});
}
