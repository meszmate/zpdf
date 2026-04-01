const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const Document = zpdf.Document;
const Destination = zpdf.Destination;
const InternalLink = zpdf.InternalLink;
const TocEntry = zpdf.TocEntry;
const TocOptions = zpdf.TocOptions;
const PageSize = zpdf.PageSize;

test "add named destination" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.a4);

    try doc.addNamedDestination(.{
        .name = "chapter1",
        .page_index = 0,
        .dest_type = .xyz,
        .left = 0,
        .top = 841,
        .zoom = 1.0,
    });

    try doc.addNamedDestination(.{
        .name = "chapter2",
        .page_index = 1,
        .dest_type = .fit,
    });

    try testing.expectEqual(@as(usize, 2), doc.named_destinations.items.len);
    try testing.expectEqualStrings("chapter1", doc.named_destinations.items[0].name);
    try testing.expectEqualStrings("chapter2", doc.named_destinations.items[1].name);
    try testing.expectEqual(@as(usize, 1), doc.named_destinations.items[1].page_index);
}

test "add internal link" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.a4);

    try doc.addNamedDestination(.{
        .name = "target",
        .page_index = 1,
        .dest_type = .fit,
    });

    try doc.addInternalLink(0, .{
        .rect = .{ 72, 700, 300, 714 },
        .dest_name = "target",
    });

    try testing.expectEqual(@as(usize, 1), doc.internal_links.items.len);
    try testing.expectEqual(@as(usize, 0), doc.internal_links.items[0].page_index);
    try testing.expectEqualStrings("target", doc.internal_links.items[0].link.dest_name);
}

test "destination types" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);

    // Test all destination types
    try doc.addNamedDestination(.{ .name = "d_xyz", .page_index = 0, .dest_type = .xyz, .left = 10, .top = 20, .zoom = 1.5 });
    try doc.addNamedDestination(.{ .name = "d_fit", .page_index = 0, .dest_type = .fit });
    try doc.addNamedDestination(.{ .name = "d_fith", .page_index = 0, .dest_type = .fit_h, .top = 500 });
    try doc.addNamedDestination(.{ .name = "d_fitv", .page_index = 0, .dest_type = .fit_v, .left = 100 });
    try doc.addNamedDestination(.{ .name = "d_fitr", .page_index = 0, .dest_type = .fit_r, .left = 0, .bottom = 0, .right = 300, .top = 400 });

    try testing.expectEqual(@as(usize, 5), doc.named_destinations.items.len);
}

test "save document with named destinations produces valid PDF" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    const helv = try doc.getStandardFont(.helvetica);

    const page0 = try doc.addPage(.a4);
    _ = try page0.addFont(helv.font.pdfName(), helv.ref);
    try page0.drawText("Go to Chapter 1", .{ .x = 72, .y = 750, .font = .helvetica, .font_size = 12 });

    const page1 = try doc.addPage(.a4);
    _ = try page1.addFont(helv.font.pdfName(), helv.ref);
    try page1.drawText("Chapter 1 Content", .{ .x = 72, .y = 750, .font = .helvetica, .font_size = 12 });

    try doc.addNamedDestination(.{
        .name = "chapter1",
        .page_index = 1,
        .dest_type = .fit,
    });

    try doc.addInternalLink(0, .{
        .rect = .{ 72, 740, 200, 755 },
        .dest_name = "chapter1",
    });

    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    // Verify basic PDF structure
    try testing.expect(std.mem.startsWith(u8, pdf, "%PDF-1.7\n"));
    try testing.expect(std.mem.indexOf(u8, pdf, "%%EOF") != null);

    // Verify named destination appears in output
    try testing.expect(std.mem.indexOf(u8, pdf, "(chapter1)") != null);

    // Verify link annotation
    try testing.expect(std.mem.indexOf(u8, pdf, "/Link") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "/Annot") != null);

    // Verify /Names /Dests structure
    try testing.expect(std.mem.indexOf(u8, pdf, "/Dests") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "/Fit") != null);
}

test "save document with XYZ destination" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);

    try doc.addNamedDestination(.{
        .name = "pos1",
        .page_index = 0,
        .dest_type = .xyz,
        .left = 72,
        .top = 500,
        .zoom = 2.0,
    });

    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    try testing.expect(std.mem.indexOf(u8, pdf, "/XYZ") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "(pos1)") != null);
}

test "render TOC creates destinations and links" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    const helv = try doc.getStandardFont(.helvetica);

    // Create TOC page and content pages
    const toc_page = try doc.addPage(.a4);
    _ = try toc_page.addFont(helv.font.pdfName(), helv.ref);

    _ = try doc.addPage(.a4); // page 1
    _ = try doc.addPage(.a4); // page 2

    const entries = [_]TocEntry{
        .{ .title = "Introduction", .page_index = 1, .level = 0 },
        .{ .title = "Getting Started", .page_index = 1, .level = 1 },
        .{ .title = "Advanced Topics", .page_index = 2, .level = 0 },
    };

    const height = try doc.renderToc(0, &entries, .{});
    try testing.expect(height > 0);

    // Should have created 3 named destinations
    try testing.expectEqual(@as(usize, 3), doc.named_destinations.items.len);

    // Should have created 3 internal links
    try testing.expectEqual(@as(usize, 3), doc.internal_links.items.len);

    // All links should be on page 0 (the TOC page)
    for (doc.internal_links.items) |il| {
        try testing.expectEqual(@as(usize, 0), il.page_index);
    }

    // Generate PDF and verify
    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    try testing.expect(std.mem.startsWith(u8, pdf, "%PDF-1.7\n"));
    try testing.expect(std.mem.indexOf(u8, pdf, "/Dests") != null);
}

test "internal link with color" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.a4);

    try doc.addNamedDestination(.{
        .name = "colored_target",
        .page_index = 1,
        .dest_type = .fit,
    });

    try doc.addInternalLink(0, .{
        .rect = .{ 72, 700, 300, 714 },
        .dest_name = "colored_target",
        .border_width = 1,
        .color = zpdf.rgb(0, 0, 255),
    });

    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    try testing.expect(std.mem.indexOf(u8, pdf, "/Link") != null);
}
