const std = @import("std");
const zpdf = @import("zpdf");

const Page = zpdf.Page;
const ListItem = zpdf.ListItem;
const ListOptions = zpdf.ListOptions;
const ListStyle = zpdf.ListStyle;

fn createTestPage() Page {
    var page = Page.init(std.testing.allocator, 612, 792);
    // Register a font so drawText works
    page.resources.font_count = 1;
    return page;
}

test "bullet list rendering" {
    var page = createTestPage();
    defer page.deinit();

    const items = [_]ListItem{
        .{ .text = "First item" },
        .{ .text = "Second item" },
        .{ .text = "Third item" },
    };

    const height = try page.drawList(&items, .{
        .x = 50,
        .y = 700,
        .max_width = 400,
        .style = .bullet,
    });

    try std.testing.expect(height > 0);
    try std.testing.expect(page.content.items.len > 0);
}

test "numbered list rendering" {
    var page = createTestPage();
    defer page.deinit();

    const items = [_]ListItem{
        .{ .text = "First" },
        .{ .text = "Second" },
        .{ .text = "Third" },
    };

    const height = try page.drawList(&items, .{
        .x = 50,
        .y = 700,
        .max_width = 400,
        .style = .numbered,
    });

    try std.testing.expect(height > 0);
    // Check that numbered markers produced text content
    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "Tj") != null);
}

test "nested lists two levels" {
    var page = createTestPage();
    defer page.deinit();

    const children = [_]ListItem{
        .{ .text = "Sub-item A" },
        .{ .text = "Sub-item B" },
    };

    const items = [_]ListItem{
        .{ .text = "Parent item", .children = &children },
        .{ .text = "Another parent" },
    };

    const height = try page.drawList(&items, .{
        .x = 50,
        .y = 700,
        .max_width = 400,
        .style = .numbered,
    });

    // Nested list should consume more height than a flat one
    try std.testing.expect(height > 60);
}

test "roman numeral conversion" {
    const formatRoman = zpdf.layout.lists.formatRoman;
    var buf: [32]u8 = undefined;

    try std.testing.expectEqualStrings("i.", formatRoman(1, &buf, false));
    try std.testing.expectEqualStrings("ii.", formatRoman(2, &buf, false));
    try std.testing.expectEqualStrings("iii.", formatRoman(3, &buf, false));
    try std.testing.expectEqualStrings("iv.", formatRoman(4, &buf, false));
    try std.testing.expectEqualStrings("v.", formatRoman(5, &buf, false));
    try std.testing.expectEqualStrings("ix.", formatRoman(9, &buf, false));
    try std.testing.expectEqualStrings("x.", formatRoman(10, &buf, false));
    try std.testing.expectEqualStrings("xiv.", formatRoman(14, &buf, false));
    try std.testing.expectEqualStrings("xlii.", formatRoman(42, &buf, false));
    try std.testing.expectEqualStrings("xcix.", formatRoman(99, &buf, false));

    // Upper case
    try std.testing.expectEqualStrings("I.", formatRoman(1, &buf, true));
    try std.testing.expectEqualStrings("IV.", formatRoman(4, &buf, true));
    try std.testing.expectEqualStrings("MCMXCIX.", formatRoman(1999, &buf, true));
}

test "letter conversion" {
    const formatLetter = zpdf.layout.lists.formatLetter;
    var buf: [8]u8 = undefined;

    try std.testing.expectEqualStrings("a.", formatLetter(1, &buf, false));
    try std.testing.expectEqualStrings("b.", formatLetter(2, &buf, false));
    try std.testing.expectEqualStrings("z.", formatLetter(26, &buf, false));
    try std.testing.expectEqualStrings("A.", formatLetter(1, &buf, true));
    try std.testing.expectEqualStrings("C.", formatLetter(3, &buf, true));

    // Out of range
    try std.testing.expectEqualStrings("?.", formatLetter(0, &buf, false));
    try std.testing.expectEqualStrings("?.", formatLetter(27, &buf, false));
}

test "various styles produce content" {
    const styles = [_]ListStyle{
        .bullet,
        .dash,
        .disc,
        .circle,
        .square,
        .numbered,
        .lettered,
        .lettered_upper,
        .roman,
        .roman_upper,
    };

    for (styles) |style| {
        var page = createTestPage();
        defer page.deinit();

        const items = [_]ListItem{
            .{ .text = "Item one" },
            .{ .text = "Item two" },
        };

        const height = try page.drawList(&items, .{
            .x = 50,
            .y = 700,
            .max_width = 400,
            .style = style,
        });

        try std.testing.expect(height > 0);
        try std.testing.expect(page.content.items.len > 0);
    }
}
