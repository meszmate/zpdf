const std = @import("std");
const zpdf = @import("zpdf");

test "BlendMode pdfName returns correct PDF names" {
    try std.testing.expectEqualStrings("Normal", zpdf.BlendMode.normal.pdfName());
    try std.testing.expectEqualStrings("Multiply", zpdf.BlendMode.multiply.pdfName());
    try std.testing.expectEqualStrings("Screen", zpdf.BlendMode.screen.pdfName());
    try std.testing.expectEqualStrings("Overlay", zpdf.BlendMode.overlay.pdfName());
    try std.testing.expectEqualStrings("Darken", zpdf.BlendMode.darken.pdfName());
    try std.testing.expectEqualStrings("Lighten", zpdf.BlendMode.lighten.pdfName());
    try std.testing.expectEqualStrings("ColorDodge", zpdf.BlendMode.color_dodge.pdfName());
    try std.testing.expectEqualStrings("ColorBurn", zpdf.BlendMode.color_burn.pdfName());
    try std.testing.expectEqualStrings("HardLight", zpdf.BlendMode.hard_light.pdfName());
    try std.testing.expectEqualStrings("SoftLight", zpdf.BlendMode.soft_light.pdfName());
    try std.testing.expectEqualStrings("Difference", zpdf.BlendMode.difference.pdfName());
    try std.testing.expectEqualStrings("Exclusion", zpdf.BlendMode.exclusion.pdfName());
}

test "TransparencyOptions default values are null" {
    const opts = zpdf.TransparencyOptions{};
    try std.testing.expect(opts.fill_opacity == null);
    try std.testing.expect(opts.stroke_opacity == null);
    try std.testing.expect(opts.blend_mode == null);
}

test "build transparency ExtGState with fill opacity only" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try zpdf.transparency.buildTransparencyExtGState(allocator, &store, .{
        .fill_opacity = 0.5,
    });

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "build transparency ExtGState with blend mode only" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try zpdf.transparency.buildTransparencyExtGState(allocator, &store, .{
        .blend_mode = .screen,
    });

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "build transparency ExtGState with all options" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try zpdf.transparency.buildTransparencyExtGState(allocator, &store, .{
        .fill_opacity = 0.3,
        .stroke_opacity = 0.8,
        .blend_mode = .overlay,
    });

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "page setTransparency writes gs operator to content stream" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    const page = try doc.addPage(.a4);

    const gs_ref = try zpdf.transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.5,
        .blend_mode = .multiply,
    });

    try page.setTransparency(gs_ref);

    // Content stream should contain the gs operator
    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "/GS1 gs\n") != null);

    // The ExtGState resource should be registered
    try std.testing.expectEqual(@as(usize, 1), page.resources.ext_g_states.items.len);
    try std.testing.expectEqualStrings("GS1", page.resources.ext_g_states.items[0].name);
}

test "full document with transparency produces valid PDF" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    const page = try doc.addPage(.a4);

    const gs_ref = try zpdf.transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.5,
    });

    try page.setTransparency(gs_ref);
    try page.drawRect(.{
        .x = 100,
        .y = 500,
        .width = 200,
        .height = 100,
        .color = zpdf.rgb(255, 0, 0),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    // Basic PDF structure validation
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-1.7"));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "%%EOF") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/ExtGState") != null);
}

test "multiple transparency states on same page" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    const page = try doc.addPage(.a4);

    const gs1 = try zpdf.transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.3,
    });
    const gs2 = try zpdf.transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.7,
        .blend_mode = .screen,
    });

    try page.setTransparency(gs1);
    try page.drawRect(.{
        .x = 50, .y = 500, .width = 200, .height = 100,
        .color = zpdf.rgb(255, 0, 0),
    });

    try page.setTransparency(gs2);
    try page.drawRect(.{
        .x = 150, .y = 450, .width = 200, .height = 100,
        .color = zpdf.rgb(0, 0, 255),
    });

    // Should have two ExtGState resources
    try std.testing.expectEqual(@as(usize, 2), page.resources.ext_g_states.items.len);
    try std.testing.expectEqualStrings("GS1", page.resources.ext_g_states.items[0].name);
    try std.testing.expectEqualStrings("GS2", page.resources.ext_g_states.items[1].name);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "/ExtGState") != null);
}
