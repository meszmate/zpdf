const std = @import("std");
const zpdf = @import("zpdf");
const OpenTypeFont = zpdf.OpenTypeFont;
const ot = zpdf.opentype;
const font_embedder = zpdf.font_embedder;

test "isCffFont detects OTTO signature" {
    const otto = [_]u8{ 0x4F, 0x54, 0x54, 0x4F };
    try std.testing.expect(ot.isCffFont(&otto));

    const tt = [_]u8{ 0x00, 0x01, 0x00, 0x00 };
    try std.testing.expect(!ot.isCffFont(&tt));
}

test "parse minimal test OTF" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try OpenTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 2), font.num_glyphs);
    try std.testing.expectEqual(@as(u16, 1000), font.units_per_em);
    try std.testing.expectEqual(@as(i16, 800), font.ascent);
    try std.testing.expectEqual(@as(i16, -200), font.descent);
    try std.testing.expect(font.isCff());
}

test "OTF glyph index lookup" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try OpenTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    const glyph_a = font.getGlyphIndex(0x41);
    try std.testing.expect(glyph_a != null);
    try std.testing.expectEqual(@as(u16, 1), glyph_a.?);
    try std.testing.expect(font.getGlyphIndex(0x42) == null);
}

test "OTF glyph width" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try OpenTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 500), font.getGlyphWidth(0));
    try std.testing.expectEqual(@as(u16, 600), font.getGlyphWidth(1));
    try std.testing.expectEqual(@as(u16, 600), font.getGlyphWidth(999));
}

test "OTF text width measurement" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try OpenTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    const w = font.textWidth("A", 10.0);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), w, 0.01);
}

test "OTF CFF data present" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try OpenTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    try std.testing.expect(font.cff_data != null);
    try std.testing.expect(font.cff_data.?.len > 0);
}

test "embed OpenType CFF font creates PDF objects" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try OpenTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    var store = zpdf.ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const used_chars = [_]u32{0x41};
    var result = try font_embedder.embedOpenTypeFont(std.testing.allocator, &store, &font, &used_chars);
    defer result.deinit();

    try std.testing.expect(store.count() >= 5);
    try std.testing.expectEqualStrings("OT0", result.name);
    try std.testing.expect(result.ref.obj_num > 0);
}

test "document loadOpenTypeFont" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var doc = zpdf.Document.init(std.testing.allocator);
    defer doc.deinit();

    const handle = try doc.loadOpenTypeFont(font_data);
    try std.testing.expect(handle.ref.obj_num > 0);
    try std.testing.expectEqual(@as(u16, 2), handle.font.num_glyphs);
    try std.testing.expect(handle.font.isCff());
}

test "document loadFont auto-detects OTF" {
    const font_data = try ot.buildMinimalTestOtf(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var doc = zpdf.Document.init(std.testing.allocator);
    defer doc.deinit();

    const ref = try doc.loadFont(font_data);
    try std.testing.expect(ref.obj_num > 0);
    // Should have stored in ot_fonts, not tt_fonts
    try std.testing.expectEqual(@as(usize, 1), doc.ot_fonts.items.len);
    try std.testing.expectEqual(@as(usize, 0), doc.tt_fonts.items.len);
}

test "document loadFont auto-detects TTF" {
    const truetype = zpdf.truetype;
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var doc = zpdf.Document.init(std.testing.allocator);
    defer doc.deinit();

    const ref = try doc.loadFont(font_data);
    try std.testing.expect(ref.obj_num > 0);
    try std.testing.expectEqual(@as(usize, 0), doc.ot_fonts.items.len);
    try std.testing.expectEqual(@as(usize, 1), doc.tt_fonts.items.len);
}

test "reject non-OTTO data as OpenType" {
    const data = [12]u8{ 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0 };
    const result = OpenTypeFont.init(std.testing.allocator, &data);
    try std.testing.expectError(error.InvalidFont, result);
}
