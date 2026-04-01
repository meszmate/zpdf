const std = @import("std");
const zpdf = @import("zpdf");
const Page = zpdf.Page;
const ColumnLayout = zpdf.ColumnLayout;
const ColumnContent = zpdf.ColumnContent;

fn createTestPage(allocator: std.mem.Allocator) !*Page {
    const page = try allocator.create(Page);
    page.* = Page.init(allocator, 612, 792);

    // Register a font so drawText works
    const helv_ref = zpdf.Ref{ .obj_num = 1, .gen_num = 0 };
    _ = try page.addFont(zpdf.StandardFont.helvetica.pdfName(), helv_ref);
    return page;
}

fn destroyTestPage(allocator: std.mem.Allocator, page: *Page) void {
    page.deinit();
    allocator.destroy(page);
}

test "2-column layout renders content" {
    const allocator = std.testing.allocator;
    const page = try createTestPage(allocator);
    defer destroyTestPage(allocator, page);

    const text = "The quick brown fox jumps over the lazy dog. " ++
        "This is a test of the multi-column layout system. " ++
        "It should split text across two columns evenly.";

    const height = try page.drawColumns(.{
        .num_columns = 2,
        .column_gap = 20,
        .x = 50,
        .y = 700,
        .width = 500,
        .max_height = 200,
    }, .{ .text = .{
        .text = text,
        .font = .helvetica,
        .font_size = 12,
        .line_height = 14.4,
    } });

    try std.testing.expect(height > 0);
    try std.testing.expect(page.content.items.len > 0);
}

test "3-column layout renders content" {
    const allocator = std.testing.allocator;
    const page = try createTestPage(allocator);
    defer destroyTestPage(allocator, page);

    const text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

    const height = try page.drawColumns(.{
        .num_columns = 3,
        .column_gap = 15,
        .x = 50,
        .y = 700,
        .width = 510,
        .max_height = 200,
    }, .{ .text = .{
        .text = text,
        .font = .helvetica,
        .font_size = 11,
        .line_height = 13.2,
    } });

    try std.testing.expect(height > 0);
    try std.testing.expect(page.content.items.len > 0);
}

test "column width calculation 2 columns" {
    const w = zpdf.columnWidth(.{
        .num_columns = 2,
        .column_gap = 20,
        .x = 50,
        .y = 700,
        .width = 500,
    });
    // (500 - 1*20) / 2 = 240
    try std.testing.expectApproxEqAbs(@as(f32, 240.0), w, 0.01);
}

test "column width calculation 3 columns" {
    const w = zpdf.columnWidth(.{
        .num_columns = 3,
        .column_gap = 15,
        .x = 50,
        .y = 700,
        .width = 510,
    });
    // (510 - 2*15) / 3 = 160
    try std.testing.expectApproxEqAbs(@as(f32, 160.0), w, 0.01);
}

test "column width single column equals total width" {
    const w = zpdf.columnWidth(.{
        .num_columns = 1,
        .column_gap = 20,
        .x = 0,
        .y = 0,
        .width = 400,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 400.0), w, 0.01);
}

test "text overflow between columns" {
    const allocator = std.testing.allocator;
    const page = try createTestPage(allocator);
    defer destroyTestPage(allocator, page);

    // Create text long enough that it must overflow into the second column.
    // With a very small max_height, only a few lines fit per column.
    const text = "Word one. Word two. Word three. Word four. Word five. " ++
        "Word six. Word seven. Word eight. Word nine. Word ten. " ++
        "Word eleven. Word twelve. Word thirteen. Word fourteen. Word fifteen.";

    const height = try page.drawColumns(.{
        .num_columns = 2,
        .column_gap = 20,
        .x = 50,
        .y = 700,
        .width = 500,
        .max_height = 30, // very short columns to force overflow
    }, .{ .text = .{
        .text = text,
        .font = .helvetica,
        .font_size = 12,
        .line_height = 14.4,
    } });

    try std.testing.expect(height > 0);
    try std.testing.expect(height <= 30);
}

test "balanced mode distributes lines evenly" {
    const allocator = std.testing.allocator;
    const page = try createTestPage(allocator);
    defer destroyTestPage(allocator, page);

    const text = "Line one of text. Line two of text. Line three of text. " ++
        "Line four of text. Line five of text. Line six of text.";

    const height = try page.drawColumns(.{
        .num_columns = 2,
        .column_gap = 20,
        .x = 50,
        .y = 700,
        .width = 500,
        .balanced = true,
    }, .{ .text = .{
        .text = text,
        .font = .helvetica,
        .font_size = 12,
        .line_height = 14.4,
    } });

    try std.testing.expect(height > 0);
    try std.testing.expect(page.content.items.len > 0);
}
