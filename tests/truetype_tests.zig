const std = @import("std");
const zpdf = @import("zpdf");
const TrueTypeFont = zpdf.TrueTypeFont;
const truetype = zpdf.truetype;
const font_subsetter = zpdf.font_subsetter;
const font_embedder = zpdf.font_embedder;

test "parse minimal test font" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 2), font.num_glyphs);
    try std.testing.expectEqual(@as(u16, 1000), font.units_per_em);
    try std.testing.expectEqual(@as(i16, 800), font.ascent);
    try std.testing.expectEqual(@as(i16, -200), font.descent);
}

test "read big-endian u16" {
    const data = [_]u8{ 0x01, 0x00, 0xFF, 0xFF };
    try std.testing.expectEqual(@as(u16, 256), truetype.readU16(&data, 0));
    try std.testing.expectEqual(@as(u16, 65535), truetype.readU16(&data, 2));
}

test "read big-endian i16" {
    const data = [_]u8{ 0xFF, 0xFE, 0x00, 0x01 };
    try std.testing.expectEqual(@as(i16, -2), truetype.readI16(&data, 0));
    try std.testing.expectEqual(@as(i16, 1), truetype.readI16(&data, 2));
}

test "read big-endian u32" {
    const data = [_]u8{ 0x00, 0x01, 0x00, 0x00 };
    try std.testing.expectEqual(@as(u32, 0x00010000), truetype.readU32(&data, 0));
}

test "cmap format 0 parsing" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    // Our minimal font maps 'A' (0x41) -> glyph 1
    const glyph_a = font.getGlyphIndex(0x41);
    try std.testing.expect(glyph_a != null);
    try std.testing.expectEqual(@as(u16, 1), glyph_a.?);

    // Unmapped codepoint should return null
    try std.testing.expect(font.getGlyphIndex(0x42) == null);
}

test "glyph width lookup" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 500), font.getGlyphWidth(0));
    try std.testing.expectEqual(@as(u16, 600), font.getGlyphWidth(1));
    // Out-of-range glyph should return last width
    try std.testing.expectEqual(@as(u16, 600), font.getGlyphWidth(999));
}

test "text width measurement" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    // 'A' maps to glyph 1 (width 600), units_per_em = 1000
    // width = 600 * 10.0 / 1000 = 6.0
    const w = font.textWidth("A", 10.0);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), w, 0.01);
}

test "font subsetting preserves notdef" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    const glyphs = [_]u16{};
    var result = try font_subsetter.subset(std.testing.allocator, &font, &glyphs);
    defer result.deinit();

    try std.testing.expectEqual(@as(u16, 1), result.num_glyphs);
    try std.testing.expect(result.glyph_map.get(0) != null);
}

test "font subsetting with specific glyphs" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    const glyphs = [_]u16{1};
    var result = try font_subsetter.subset(std.testing.allocator, &font, &glyphs);
    defer result.deinit();

    try std.testing.expectEqual(@as(u16, 2), result.num_glyphs);
    // Verify the output is a valid TrueType file
    try std.testing.expectEqual(
        @as(u32, 0x00010000),
        std.mem.readInt(u32, result.font_data[0..4], .big),
    );
}

test "font embedding creates PDF objects" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    var store = zpdf.ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const used_chars = [_]u32{0x41};
    var result = try font_embedder.embedFont(std.testing.allocator, &store, &font, &used_chars);
    defer result.deinit();

    // Should have created: stream, descriptor, tounicode, cidfont, type0 = 5 objects
    try std.testing.expect(store.count() >= 5);
    try std.testing.expectEqualStrings("TT0", result.name);
}

test "ToUnicode CMap generation" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    var glyph_map = std.AutoHashMapUnmanaged(u16, u16){};
    defer glyph_map.deinit(std.testing.allocator);
    try glyph_map.put(std.testing.allocator, 0, 0);
    try glyph_map.put(std.testing.allocator, 1, 1);

    const used_chars = [_]u32{0x41};
    const cmap = try font_embedder.buildToUnicodeCmap(
        std.testing.allocator,
        &font,
        &used_chars,
        &glyph_map,
    );
    defer std.testing.allocator.free(cmap);

    try std.testing.expect(std.mem.indexOf(u8, cmap, "begincmap") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmap, "endcmap") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmap, "begincodespacerange") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmap, "beginbfchar") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmap, "<0001> <0041>") != null);
}

test "reject invalid font data" {
    const result = TrueTypeFont.init(std.testing.allocator, "short");
    try std.testing.expectError(error.InvalidFont, result);
}

test "reject wrong magic number" {
    const data = [16]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const result = TrueTypeFont.init(std.testing.allocator, &data);
    try std.testing.expectError(error.InvalidFont, result);
}

test "document loadTrueTypeFont" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var doc = zpdf.Document.init(std.testing.allocator);
    defer doc.deinit();

    const handle = try doc.loadTrueTypeFont(font_data);
    try std.testing.expect(handle.ref.obj_num > 0);
    try std.testing.expectEqual(@as(u16, 2), handle.font.num_glyphs);
}
