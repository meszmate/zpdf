const std = @import("std");
const zpdf = @import("zpdf");
const Page = zpdf.Page;
const TextSpan = zpdf.TextSpan;
const RichTextOptions = zpdf.RichTextOptions;
const RichTextAlignment = zpdf.RichTextAlignment;
const color = zpdf.color;

fn createTestPage() Page {
    var page = Page.init(std.testing.allocator, 612, 792);
    // Register a font so drawRichText can resolve font resource names
    page.resources.font_count = 1;
    return page;
}

test "single span renders correctly" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "Hello World" },
    };

    const height = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    try std.testing.expect(height > 0);
    // Should contain BT/ET markers and the text
    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "BT") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "ET") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "World") != null);
}

test "multiple spans with different fonts" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "Normal ", .font = .helvetica },
        .{ .text = "Bold", .font = .helvetica_bold },
    };

    const height = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    try std.testing.expect(height > 0);
    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "Normal") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "Bold") != null);
    // Should have Tf operators for font switching
    try std.testing.expect(std.mem.indexOf(u8, content, "Tf") != null);
}

test "line wrapping with mixed font sizes" {
    var page = createTestPage();
    defer page.deinit();

    // Create spans that should wrap to multiple lines at narrow width
    const spans = [_]TextSpan{
        .{ .text = "This is a long text that should wrap to the next line when rendered", .font_size = 12 },
    };

    const height = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 150, // narrow width forces wrapping
    });

    // Multiple lines means more height consumed
    try std.testing.expect(height > 12 * 1.2);

    // Should have multiple BT/ET pairs (one per line)
    const content = page.content.items;
    var bt_count: usize = 0;
    var idx: usize = 0;
    while (idx < content.len - 1) : (idx += 1) {
        if (content[idx] == 'B' and content[idx + 1] == 'T') {
            bt_count += 1;
        }
    }
    try std.testing.expect(bt_count > 1);
}

test "superscript with positive rise" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "E = mc" },
        .{ .text = "2", .rise = 4, .font_size = 8 },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    const content = page.content.items;
    // Should contain a non-zero Ts (text rise) operator
    try std.testing.expect(std.mem.indexOf(u8, content, "4.00 Ts") != null);
}

test "underline generates line drawing operators" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "underlined", .underline = true },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    const content = page.content.items;
    // Underline is drawn as a stroke line (S operator) outside the text object
    // Look for the stroke pattern: m ... l ... S
    try std.testing.expect(std.mem.indexOf(u8, content, " m\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, " l\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "S\n") != null);
}

test "strikethrough generates line drawing operators" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "struck", .strikethrough = true },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "S\n") != null);
}

test "text alignment left" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "Left aligned" },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
        .alignment = .left,
    });

    const content = page.content.items;
    // Left alignment: first fragment should start at x=50
    try std.testing.expect(std.mem.indexOf(u8, content, "50.00") != null);
}

test "text alignment center" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "Centered" },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
        .alignment = .center,
    });

    // Content should exist and have text
    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "Centered") != null);
    // The x position should not be 50.00 (it should be offset for centering)
    try std.testing.expect(std.mem.indexOf(u8, content, "50.00 700.00 Td") == null);
}

test "text alignment right" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "Right" },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
        .alignment = .right,
    });

    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "Right") != null);
    // X should be shifted right, not at 50
    try std.testing.expect(std.mem.indexOf(u8, content, "50.00 700.00 Td") == null);
}

test "text alignment justify" {
    var page = createTestPage();
    defer page.deinit();

    // Use enough words to make at least 2 lines
    const spans = [_]TextSpan{
        .{ .text = "This is some text that should be justified across the available width on every line except the last" },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 200,
        .alignment = .justify,
    });

    const content = page.content.items;
    try std.testing.expect(content.len > 0);
}

test "first line indent" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "Indented first line text that wraps to a second line here" },
    };

    _ = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 200,
        .first_line_indent = 30,
    });

    const content = page.content.items;
    // First fragment x should be at 50 + 30 = 80
    try std.testing.expect(std.mem.indexOf(u8, content, "80.00") != null);
}

test "empty spans handled gracefully" {
    var page = createTestPage();
    defer page.deinit();

    const spans = [_]TextSpan{
        .{ .text = "" },
        .{ .text = "" },
    };

    const height = try page.drawRichText(&spans, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    try std.testing.expectEqual(@as(f32, 0), height);
}

test "empty spans slice handled gracefully" {
    var page = createTestPage();
    defer page.deinit();

    const height = try page.drawRichText(&[_]TextSpan{}, .{
        .x = 50,
        .y = 700,
        .max_width = 500,
    });

    try std.testing.expectEqual(@as(f32, 0), height);
}
