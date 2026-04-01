const std = @import("std");
const Allocator = std.mem.Allocator;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const types = @import("../core/types.zig");
const Ref = types.Ref;
const TrueTypeFont = @import("truetype.zig").TrueTypeFont;
const font_subsetter = @import("font_subsetter.zig");
const SubsetResult = font_subsetter.SubsetResult;

/// A TrueType font that has been embedded in the PDF.
pub const EmbeddedFont = struct {
    ref: Ref,
    font: *const TrueTypeFont,
    name: []const u8,
    /// Allocated data that must be freed when the font is no longer needed.
    /// These are stream data buffers stored in the ObjectStore.
    allocated_data: [3]?[]const u8,
    allocator: Allocator,

    pub fn deinit(self: *EmbeddedFont) void {
        for (&self.allocated_data) |*data| {
            if (data.*) |d| {
                self.allocator.free(d);
                data.* = null;
            }
        }
    }
};

/// Embed a TrueType font in the PDF.
/// Creates the necessary PDF objects: Type 0 font, CIDFont, font descriptor,
/// font stream, ToUnicode CMap, and widths array.
pub fn embedFont(
    allocator: Allocator,
    store: *ObjectStore,
    font: *const TrueTypeFont,
    used_chars: []const u32,
) !EmbeddedFont {
    // Collect glyph indices for used characters
    var used_glyphs_list: std.ArrayListUnmanaged(u16) = .{};
    defer used_glyphs_list.deinit(allocator);

    for (used_chars) |cp| {
        if (font.getGlyphIndex(cp)) |gid| {
            try used_glyphs_list.append(allocator, gid);
        }
    }

    // Subset the font
    var subset_result = try font_subsetter.subset(allocator, font, used_glyphs_list.items);
    defer subset_result.deinit();

    // Generate a 6-letter tag for the font subset (e.g., "ABCDEF+FontName")
    const tag = "ZPDFAA";
    const base_font_name = try std.fmt.allocPrint(allocator, "{s}+{s}", .{ tag, font.postscript_name });
    defer allocator.free(base_font_name);

    // 1. Font stream (embedded TrueType data)
    const stream_ref = try store.allocate();
    // We need to dupe the data since SubsetResult will free it
    const stream_data = try allocator.dupe(u8, subset_result.font_data);
    {
        var stream_dict: std.StringHashMapUnmanaged(types.PdfObject) = .{};
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(subset_result.font_data.len)));
        try stream_dict.put(allocator, "Length1", types.pdfInt(@intCast(subset_result.font_data.len)));

        store.put(stream_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = stream_data,
        } });
    }

    // 2. Font descriptor
    const desc_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("FontDescriptor"));
        try dict.dict_obj.put(allocator, "FontName", types.pdfName(base_font_name));

        // Flags: bit 6 = Nonsymbolic (32), bit 3 = Symbolic would be 4
        // For a standard text font: Nonsymbolic (32)
        var flags: i64 = 32; // Nonsymbolic
        if (font.is_fixed_pitch) flags |= 1; // FixedPitch
        if (font.italic_angle != 0) flags |= 64; // Italic
        try dict.dict_obj.put(allocator, "Flags", types.pdfInt(flags));

        // Font bounding box (scaled to 1000 units)
        const scale: f64 = 1000.0 / @as(f64, @floatFromInt(font.units_per_em));
        var bbox = types.pdfArray(allocator);
        try bbox.array_obj.append(types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(font.x_min)) * scale)));
        try bbox.array_obj.append(types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(font.y_min)) * scale)));
        try bbox.array_obj.append(types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(font.x_max)) * scale)));
        try bbox.array_obj.append(types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(font.y_max)) * scale)));
        try dict.dict_obj.put(allocator, "FontBBox", bbox);

        try dict.dict_obj.put(allocator, "ItalicAngle", types.pdfReal(font.italic_angle));
        try dict.dict_obj.put(allocator, "Ascent", types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(font.ascent)) * scale)));
        try dict.dict_obj.put(allocator, "Descent", types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(font.descent)) * scale)));

        const cap_h = font.cap_height orelse font.ascent;
        try dict.dict_obj.put(allocator, "CapHeight", types.pdfInt(@intFromFloat(@as(f64, @floatFromInt(cap_h)) * scale)));

        // StemV: estimate from weight class
        const stem_v: i64 = @intCast(@as(u32, font.weight_class) / 5 + 50);
        try dict.dict_obj.put(allocator, "StemV", types.pdfInt(stem_v));

        try dict.dict_obj.put(allocator, "FontFile2", types.pdfRef(stream_ref.obj_num, stream_ref.gen_num));

        store.put(desc_ref, dict);
    }

    // 3. Build widths array: [cid [w1 w2 ...]]
    // For CIDFontType2 with Identity mapping, CID = GID
    const widths_data = try buildWidthsArray(allocator, font, used_chars, &subset_result.glyph_map);

    // 4. ToUnicode CMap
    const tounicode_ref = try store.allocate();
    const cmap_data = try buildToUnicodeCmap(allocator, font, used_chars, &subset_result.glyph_map);
    {
        var stream_dict: std.StringHashMapUnmanaged(types.PdfObject) = .{};
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(cmap_data.len)));

        store.put(tounicode_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = cmap_data,
        } });
    }

    // 5. CIDFont dictionary
    const cidfont_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("Font"));
        try dict.dict_obj.put(allocator, "Subtype", types.pdfName("CIDFontType2"));
        try dict.dict_obj.put(allocator, "BaseFont", types.pdfName(base_font_name));

        // CIDSystemInfo
        var sys_info = types.pdfDict(allocator);
        try sys_info.dict_obj.put(allocator, "Registry", types.pdfString("Adobe"));
        try sys_info.dict_obj.put(allocator, "Ordering", types.pdfString("Identity"));
        try sys_info.dict_obj.put(allocator, "Supplement", types.pdfInt(0));
        try dict.dict_obj.put(allocator, "CIDSystemInfo", sys_info);

        try dict.dict_obj.put(allocator, "FontDescriptor", types.pdfRef(desc_ref.obj_num, desc_ref.gen_num));

        // W array (widths)
        try dict.dict_obj.put(allocator, "W", types.pdfString(widths_data));

        try dict.dict_obj.put(allocator, "CIDToGIDMap", types.pdfName("Identity"));

        store.put(cidfont_ref, dict);
    }

    // 6. Type 0 font dictionary
    const font_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("Font"));
        try dict.dict_obj.put(allocator, "Subtype", types.pdfName("Type0"));
        try dict.dict_obj.put(allocator, "BaseFont", types.pdfName(base_font_name));
        try dict.dict_obj.put(allocator, "Encoding", types.pdfName("Identity-H"));

        var descendants = types.pdfArray(allocator);
        try descendants.array_obj.append(types.pdfRef(cidfont_ref.obj_num, cidfont_ref.gen_num));
        try dict.dict_obj.put(allocator, "DescendantFonts", descendants);

        try dict.dict_obj.put(allocator, "ToUnicode", types.pdfRef(tounicode_ref.obj_num, tounicode_ref.gen_num));

        store.put(font_ref, dict);
    }

    return EmbeddedFont{
        .ref = font_ref,
        .font = font,
        .name = "TT0",
        .allocated_data = .{ stream_data, cmap_data, widths_data },
        .allocator = allocator,
    };
}

fn buildWidthsArray(
    allocator: Allocator,
    font: *const TrueTypeFont,
    used_chars: []const u32,
    glyph_map: *const std.AutoHashMapUnmanaged(u16, u16),
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    const scale: f64 = 1000.0 / @as(f64, @floatFromInt(font.units_per_em));

    try writer.writeAll("[");

    for (used_chars) |cp| {
        if (font.getGlyphIndex(cp)) |old_gid| {
            if (glyph_map.get(old_gid)) |new_gid| {
                const width = font.getGlyphWidth(old_gid);
                const scaled_width: i64 = @intFromFloat(@as(f64, @floatFromInt(width)) * scale);
                try writer.print("{d} [{d}] ", .{ new_gid, scaled_width });
            }
        }
    }

    try writer.writeAll("]");

    return try buf.toOwnedSlice(allocator);
}

/// Build a ToUnicode CMap stream that maps glyph IDs to Unicode codepoints.
pub fn buildToUnicodeCmap(
    allocator: Allocator,
    font: *const TrueTypeFont,
    used_chars: []const u32,
    glyph_map: *const std.AutoHashMapUnmanaged(u16, u16),
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll(
        \\/CIDInit /ProcSet findresource begin
        \\12 dict begin
        \\begincmap
        \\/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        \\/CMapName /Adobe-Identity-UCS def
        \\/CMapType 2 def
        \\1 begincodespacerange
        \\<0000> <FFFF>
        \\endcodespacerange
        \\
    );

    // Count valid mappings
    var count: usize = 0;
    for (used_chars) |cp| {
        if (font.getGlyphIndex(cp)) |old_gid| {
            if (glyph_map.get(old_gid) != null) {
                count += 1;
            }
        }
    }

    if (count > 0) {
        // bfchar entries (max 100 per block per CMap spec)
        var remaining = count;
        var char_idx: usize = 0;

        while (remaining > 0) {
            const block_size = @min(remaining, 100);
            try writer.print("{d} beginbfchar\n", .{block_size});

            var written: usize = 0;
            while (written < block_size and char_idx < used_chars.len) {
                const cp = used_chars[char_idx];
                char_idx += 1;

                if (font.getGlyphIndex(cp)) |old_gid| {
                    if (glyph_map.get(old_gid)) |new_gid| {
                        try writer.print("<{X:0>4}> <{X:0>4}>\n", .{ new_gid, cp });
                        written += 1;
                    }
                }
            }

            try writer.writeAll("endbfchar\n");
            remaining -= block_size;
        }
    }

    try writer.writeAll(
        \\endcmap
        \\CMapName currentdict /CMap defineresource pop
        \\end
        \\end
        \\
    );

    return try buf.toOwnedSlice(allocator);
}

// ── Tests ───────────────────────────────────────────────────────────

test "build ToUnicode CMap" {
    const truetype_mod = @import("truetype.zig");
    const font_data = try truetype_mod.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    // Build a glyph map: old gid 1 -> new gid 1
    var glyph_map = std.AutoHashMapUnmanaged(u16, u16){};
    defer glyph_map.deinit(std.testing.allocator);
    try glyph_map.put(std.testing.allocator, 0, 0);
    try glyph_map.put(std.testing.allocator, 1, 1);

    const used_chars = [_]u32{0x41}; // 'A'
    const cmap_data = try buildToUnicodeCmap(std.testing.allocator, &font, &used_chars, &glyph_map);
    defer std.testing.allocator.free(cmap_data);

    // Verify CMap structure
    try std.testing.expect(std.mem.indexOf(u8, cmap_data, "beginbfchar") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmap_data, "endcmap") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmap_data, "<0001> <0041>") != null);
}

test "embed font creates PDF objects" {
    const truetype_mod = @import("truetype.zig");
    const font_data = try truetype_mod.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const used_chars = [_]u32{0x41};
    var result = try embedFont(std.testing.allocator, &store, &font, &used_chars);
    defer result.deinit();

    // Should have created multiple objects
    try std.testing.expect(store.count() >= 5);
    try std.testing.expectEqualStrings("TT0", result.name);
    try std.testing.expect(result.ref.obj_num > 0);
}
