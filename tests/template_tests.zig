const std = @import("std");
const zpdf = @import("zpdf");
const PageTemplate = zpdf.PageTemplate;
const Margins = zpdf.Margins;
const Document = zpdf.Document;

test "create template with default margins" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    const area = tmpl.contentArea();
    // A4 is 595.28 x 841.89; with 72pt margins: content = 451.28 x 697.89
    try std.testing.expectApproxEqAbs(@as(f32, 72), area.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 72), area.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 451.28), area.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 697.89), area.height, 0.01);
}

test "template with half inch margins" {
    var tmpl = PageTemplate.init(std.testing.allocator, .letter, Margins.half_inch);
    defer tmpl.deinit();

    const area = tmpl.contentArea();
    // Letter is 612 x 792; with 36pt margins: content = 540 x 720
    try std.testing.expectApproxEqAbs(@as(f32, 540), area.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 720), area.height, 0.01);
}

test "template with symmetric margins" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.symmetric(50));
    defer tmpl.deinit();

    const area = tmpl.contentArea();
    try std.testing.expectApproxEqAbs(@as(f32, 50), area.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 50), area.y, 0.01);
}

test "add text element to template" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{ .content = "Title", .x = 72, .y = 770, .font_size = 24 });
    try std.testing.expectEqual(@as(usize, 1), tmpl.elements.items.len);
}

test "add rect element to template" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addRect(.{
        .x = 50,
        .y = 50,
        .width = 495,
        .height = 2,
        .color = zpdf.rgb(0, 0, 0),
    });
    try std.testing.expectEqual(@as(usize, 1), tmpl.elements.items.len);
}

test "add line element to template" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addLine(.{ .x1 = 50, .y1 = 800, .x2 = 545, .y2 = 800 });
    try std.testing.expectEqual(@as(usize, 1), tmpl.elements.items.len);
}

test "add multiple elements" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{ .content = "Header", .x = 72, .y = 800 });
    try tmpl.addLine(.{ .x1 = 72, .y1 = 795, .x2 = 523, .y2 = 795 });
    try tmpl.addRect(.{ .x = 72, .y = 30, .width = 451, .height = 1 });
    try tmpl.addText(.{ .content = "Footer", .x = 72, .y = 20 });

    try std.testing.expectEqual(@as(usize, 4), tmpl.elements.items.len);
}

test "apply template to page" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{ .content = "Header Text", .x = 72, .y = 800 });
    try tmpl.addLine(.{ .x1 = 72, .y1 = 795, .x2 = 523, .y2 = 795 });

    var page = zpdf.Page.init(std.testing.allocator, 595.28, 841.89);
    defer page.deinit();

    try tmpl.apply(&page, 1);
    // Content should have been drawn
    try std.testing.expect(page.content.items.len > 0);
}

test "apply template with page number substitution" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{
        .content = "Page {page}",
        .x = 500,
        .y = 30,
        .use_page_number = true,
    });

    var page = zpdf.Page.init(std.testing.allocator, 595.28, 841.89);
    defer page.deinit();

    try tmpl.apply(&page, 7);
    try std.testing.expect(page.content.items.len > 0);
}

test "document addPageFromTemplate" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{ .content = "Template Header", .x = 72, .y = 800 });
    try tmpl.addLine(.{ .x1 = 72, .y1 = 795, .x2 = 523, .y2 = 795 });

    const page = try doc.addPageFromTemplate(&tmpl, 1);
    try std.testing.expectEqual(@as(usize, 1), doc.getPageCount());
    try std.testing.expectApproxEqAbs(@as(f32, 595.28), page.getWidth(), 0.01);
    try std.testing.expect(page.content.items.len > 0);
}

test "document multiple pages from template" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var tmpl = PageTemplate.init(std.testing.allocator, .letter, Margins.half_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{
        .content = "Page {page}",
        .x = 500,
        .y = 30,
        .use_page_number = true,
    });

    _ = try doc.addPageFromTemplate(&tmpl, 1);
    _ = try doc.addPageFromTemplate(&tmpl, 2);
    _ = try doc.addPageFromTemplate(&tmpl, 3);

    try std.testing.expectEqual(@as(usize, 3), doc.getPageCount());
}
