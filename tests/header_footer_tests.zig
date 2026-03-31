const std = @import("std");
const zpdf = @import("zpdf");

const HeaderFooter = zpdf.HeaderFooter;
const HFElement = zpdf.HFElement;
const HFContent = zpdf.HFContent;
const HFPosition = zpdf.HFPosition;
const Page = zpdf.Page;

fn createTestPages(allocator: std.mem.Allocator, count: usize) ![]*Page {
    const pages = try allocator.alloc(*Page, count);
    for (pages) |*p| {
        const page = try allocator.create(Page);
        page.* = Page.init(allocator, 612, 792);
        p.* = page;
    }
    return pages;
}

fn destroyTestPages(allocator: std.mem.Allocator, pages: []*Page) void {
    for (pages) |page| {
        page.deinit();
        allocator.destroy(page);
    }
    allocator.free(pages);
}

test "apply simple text header" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 3);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .{ .text = "My Document" } },
    };

    const header = HeaderFooter{
        .elements = &elements,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, header, null, 1);

    // Each page should have content written
    for (pages) |page| {
        try std.testing.expect(page.content.items.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, page.content.items, "My Document") != null);
    }
}

test "page number formatting" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 3);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .page_number },
    };

    const footer = HeaderFooter{
        .elements = &elements,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, null, footer, 1);

    // Page 1 should contain "1", page 2 "2", page 3 "3"
    try std.testing.expect(std.mem.indexOf(u8, pages[0].content.items, "(1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, pages[1].content.items, "(2)") != null);
    try std.testing.expect(std.mem.indexOf(u8, pages[2].content.items, "(3)") != null);
}

test "page X of Y format" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 2);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .page_x_of_y },
    };

    const footer = HeaderFooter{
        .elements = &elements,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, null, footer, 1);

    try std.testing.expect(std.mem.indexOf(u8, pages[0].content.items, "Page 1 of 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, pages[1].content.items, "Page 2 of 2") != null);
}

test "skip first page option" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 3);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .{ .text = "Header Text" } },
    };

    const header = HeaderFooter{
        .elements = &elements,
        .skip_first_page = true,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, header, null, 1);

    // First page should have no content
    try std.testing.expectEqual(@as(usize, 0), pages[0].content.items.len);
    // Other pages should have content
    try std.testing.expect(pages[1].content.items.len > 0);
    try std.testing.expect(pages[2].content.items.len > 0);
}

test "separator line generation" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 1);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .{ .text = "Title" } },
    };

    const header = HeaderFooter{
        .elements = &elements,
        .separator_line = true,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, header, null, 1);

    const content = pages[0].content.items;
    // Separator line uses drawLine which produces " m\n" and " l\n" and "S\n"
    try std.testing.expect(std.mem.indexOf(u8, content, " m\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, " l\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "S\n") != null);
}

test "left center right positioning" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 1);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .left, .content = .{ .text = "Left" } },
        .{ .position = .center, .content = .{ .text = "Center" } },
        .{ .position = .right, .content = .{ .text = "Right" } },
    };

    const header = HeaderFooter{
        .elements = &elements,
        .left_margin = 50,
        .right_margin = 50,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, header, null, 1);

    const content = pages[0].content.items;
    // All three texts should appear
    try std.testing.expect(std.mem.indexOf(u8, content, "Left") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "Center") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "Right") != null);

    // Left position should use left_margin (50.00)
    try std.testing.expect(std.mem.indexOf(u8, content, "50.00") != null);
    // Right position should use page.width - right_margin (612 - 50 = 562.00)
    try std.testing.expect(std.mem.indexOf(u8, content, "562.00") != null);
    // Center position should use page.width / 2 (306.00)
    try std.testing.expect(std.mem.indexOf(u8, content, "306.00") != null);
}

test "custom format strings with page and total" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 2);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .{ .formatted = "Sheet {page}/{total}" } },
    };

    const footer = HeaderFooter{
        .elements = &elements,
    };

    try zpdf.layout.header_footer.applyHeadersFooters(pages, null, footer, 1);

    try std.testing.expect(std.mem.indexOf(u8, pages[0].content.items, "Sheet 1/2") != null);
    try std.testing.expect(std.mem.indexOf(u8, pages[1].content.items, "Sheet 2/2") != null);
}

test "page number offset" {
    const allocator = std.testing.allocator;
    const pages = try createTestPages(allocator, 2);
    defer destroyTestPages(allocator, pages);

    const elements = [_]HFElement{
        .{ .position = .center, .content = .page_number },
    };

    const footer = HeaderFooter{
        .elements = &elements,
    };

    // Start numbering from 5
    try zpdf.layout.header_footer.applyHeadersFooters(pages, null, footer, 5);

    try std.testing.expect(std.mem.indexOf(u8, pages[0].content.items, "(5)") != null);
    try std.testing.expect(std.mem.indexOf(u8, pages[1].content.items, "(6)") != null);
}
