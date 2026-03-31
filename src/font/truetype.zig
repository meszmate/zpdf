const std = @import("std");
const Allocator = std.mem.Allocator;

/// An entry in the TrueType table directory.
pub const TableEntry = struct {
    offset: u32,
    length: u32,
    checksum: u32,
};

/// A parsed TrueType font file.
pub const TrueTypeFont = struct {
    allocator: Allocator,
    data: []const u8,

    // Parsed header info
    num_glyphs: u16,
    units_per_em: u16,
    ascent: i16,
    descent: i16,
    line_gap: i16,

    // Table directory
    tables: std.StringHashMapUnmanaged(TableEntry),

    // cmap: character to glyph mapping
    cmap_format: u16,
    char_to_glyph: std.AutoHashMapUnmanaged(u32, u16),

    // hmtx: horizontal metrics
    advance_widths: []const u16,
    left_side_bearings: []const i16,

    // name table
    font_family: []const u8,
    font_subfamily: []const u8,
    postscript_name: []const u8,

    // head table
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    mac_style: u16,
    index_to_loc_format: i16,

    // post table
    italic_angle: f64,
    is_fixed_pitch: bool,

    // OS/2 table
    weight_class: u16,
    width_class: u16,
    fs_type: u16,
    cap_height: ?i16,
    x_height: ?i16,

    pub fn init(allocator: Allocator, data: []const u8) !TrueTypeFont {
        if (data.len < 12) return error.InvalidFont;

        var font = TrueTypeFont{
            .allocator = allocator,
            .data = data,
            .num_glyphs = 0,
            .units_per_em = 1000,
            .ascent = 0,
            .descent = 0,
            .line_gap = 0,
            .tables = .{},
            .cmap_format = 0,
            .char_to_glyph = .{},
            .advance_widths = &[_]u16{},
            .left_side_bearings = &[_]i16{},
            .font_family = "Unknown",
            .font_subfamily = "Regular",
            .postscript_name = "Unknown",
            .x_min = 0,
            .y_min = 0,
            .x_max = 0,
            .y_max = 0,
            .mac_style = 0,
            .index_to_loc_format = 0,
            .italic_angle = 0,
            .is_fixed_pitch = false,
            .weight_class = 400,
            .width_class = 5,
            .fs_type = 0,
            .cap_height = null,
            .x_height = null,
        };

        errdefer font.deinit();

        // Validate sfVersion
        const sf_version = readU32(data, 0);
        if (sf_version != 0x00010000 and sf_version != 0x74727565) {
            // 0x00010000 = TrueType, 0x74727565 = 'true' (Apple variant)
            return error.InvalidFont;
        }

        const num_tables = readU16(data, 4);
        if (data.len < 12 + @as(usize, num_tables) * 16) return error.InvalidFont;

        // Parse table directory
        var i: usize = 0;
        while (i < num_tables) : (i += 1) {
            const entry_offset = 12 + i * 16;
            if (entry_offset + 16 > data.len) return error.InvalidFont;

            const tag = data[entry_offset..][0..4];
            const entry = TableEntry{
                .checksum = readU32(data, entry_offset + 4),
                .offset = readU32(data, entry_offset + 8),
                .length = readU32(data, entry_offset + 12),
            };

            // Validate table bounds
            if (@as(u64, entry.offset) + @as(u64, entry.length) > data.len) {
                return error.InvalidFont;
            }

            try font.tables.put(allocator, tag, entry);
        }

        // Parse required tables
        try font.parseHead();
        try font.parseMaxp();
        try font.parseHhea();
        try font.parseHmtx();
        try font.parseCmap();
        font.parseName() catch {};
        font.parsePost() catch {};
        font.parseOs2() catch {};

        return font;
    }

    pub fn deinit(self: *TrueTypeFont) void {
        self.tables.deinit(self.allocator);
        self.char_to_glyph.deinit(self.allocator);
        if (self.advance_widths.len > 0) {
            self.allocator.free(self.advance_widths);
        }
        if (self.left_side_bearings.len > 0) {
            self.allocator.free(self.left_side_bearings);
        }
    }

    /// Get glyph index for a Unicode codepoint.
    pub fn getGlyphIndex(self: *const TrueTypeFont, codepoint: u32) ?u16 {
        return self.char_to_glyph.get(codepoint);
    }

    /// Get advance width for a glyph index (in font units).
    pub fn getGlyphWidth(self: *const TrueTypeFont, glyph_index: u16) u16 {
        if (glyph_index < self.advance_widths.len) {
            return self.advance_widths[glyph_index];
        }
        // For glyphs beyond numberOfHMetrics, use the last width
        if (self.advance_widths.len > 0) {
            return self.advance_widths[self.advance_widths.len - 1];
        }
        return 0;
    }

    /// Measure text width in points for a given font size.
    pub fn textWidth(self: *const TrueTypeFont, text_bytes: []const u8, font_size: f32) f32 {
        var total_width: u32 = 0;
        for (text_bytes) |byte| {
            if (self.getGlyphIndex(@as(u32, byte))) |glyph_idx| {
                total_width += self.getGlyphWidth(glyph_idx);
            }
        }
        const scale = font_size / @as(f32, @floatFromInt(self.units_per_em));
        return @as(f32, @floatFromInt(total_width)) * scale;
    }

    // ── Table parsers ───────────────────────────────────────────────

    fn parseHead(self: *TrueTypeFont) !void {
        const entry = self.tables.get("head") orelse return error.MissingTable;
        const d = self.data;
        const off = entry.offset;
        if (entry.length < 54) return error.InvalidFont;

        self.units_per_em = readU16(d, off + 18);
        if (self.units_per_em == 0) return error.InvalidFont;

        self.x_min = readI16(d, off + 36);
        self.y_min = readI16(d, off + 38);
        self.x_max = readI16(d, off + 40);
        self.y_max = readI16(d, off + 42);
        self.mac_style = readU16(d, off + 44);
        self.index_to_loc_format = readI16(d, off + 50);
    }

    fn parseMaxp(self: *TrueTypeFont) !void {
        const entry = self.tables.get("maxp") orelse return error.MissingTable;
        if (entry.length < 6) return error.InvalidFont;
        self.num_glyphs = readU16(self.data, entry.offset + 4);
    }

    fn parseHhea(self: *TrueTypeFont) !void {
        const entry = self.tables.get("hhea") orelse return error.MissingTable;
        if (entry.length < 36) return error.InvalidFont;
        const off = entry.offset;
        self.ascent = readI16(self.data, off + 4);
        self.descent = readI16(self.data, off + 6);
        self.line_gap = readI16(self.data, off + 8);
    }

    fn parseHmtx(self: *TrueTypeFont) !void {
        const hmtx_entry = self.tables.get("hmtx") orelse return error.MissingTable;
        const hhea_entry = self.tables.get("hhea") orelse return error.MissingTable;
        if (hhea_entry.length < 36) return error.InvalidFont;

        const num_h_metrics = readU16(self.data, hhea_entry.offset + 34);
        if (num_h_metrics == 0) return error.InvalidFont;

        const num_glyphs = self.num_glyphs;
        const widths = try self.allocator.alloc(u16, num_glyphs);
        errdefer self.allocator.free(widths);
        const lsbs = try self.allocator.alloc(i16, num_glyphs);
        errdefer self.allocator.free(lsbs);

        const off = hmtx_entry.offset;
        var i: u16 = 0;

        // Long horizontal metrics
        while (i < num_h_metrics and i < num_glyphs) : (i += 1) {
            const rec_off = off + @as(u32, i) * 4;
            if (rec_off + 4 > self.data.len) break;
            widths[i] = readU16(self.data, rec_off);
            lsbs[i] = readI16(self.data, rec_off + 2);
        }

        // Remaining glyphs share the last advance width
        const last_width = if (num_h_metrics > 0) widths[num_h_metrics - 1] else 0;
        const lsb_off = off + @as(u32, num_h_metrics) * 4;
        while (i < num_glyphs) : (i += 1) {
            widths[i] = last_width;
            const lsb_rec = lsb_off + @as(u32, i - num_h_metrics) * 2;
            if (lsb_rec + 2 <= self.data.len) {
                lsbs[i] = readI16(self.data, lsb_rec);
            } else {
                lsbs[i] = 0;
            }
        }

        self.advance_widths = widths;
        self.left_side_bearings = lsbs;
    }

    fn parseCmap(self: *TrueTypeFont) !void {
        const entry = self.tables.get("cmap") orelse return error.MissingTable;
        const d = self.data;
        const off = entry.offset;
        if (entry.length < 4) return error.InvalidFont;

        const num_subtables = readU16(d, off + 2);

        // Find a Unicode subtable (platform 3, encoding 1 = Windows Unicode BMP
        // or platform 0 = Unicode)
        var subtable_offset: ?u32 = null;
        var i: u16 = 0;
        while (i < num_subtables) : (i += 1) {
            const rec = off + 4 + @as(u32, i) * 8;
            if (rec + 8 > d.len) break;

            const platform_id = readU16(d, rec);
            const encoding_id = readU16(d, rec + 2);
            const sub_off = readU32(d, rec + 4);

            // Prefer Windows Unicode BMP (3,1), also accept Unicode (0,*) and Macintosh (1,0)
            if ((platform_id == 3 and encoding_id == 1) or
                (platform_id == 0) or
                (platform_id == 1 and encoding_id == 0))
            {
                subtable_offset = off + sub_off;
                if (platform_id == 3 and encoding_id == 1) break; // preferred
            }
        }

        const sub_off = subtable_offset orelse return error.NoCmapSubtable;
        if (sub_off + 2 > d.len) return error.InvalidFont;

        const format = readU16(d, sub_off);
        self.cmap_format = format;

        if (format == 4) {
            try self.parseCmapFormat4(sub_off);
        } else if (format == 0) {
            try self.parseCmapFormat0(sub_off);
        } else {
            return error.UnsupportedCmapFormat;
        }
    }

    fn parseCmapFormat4(self: *TrueTypeFont, sub_off: u32) !void {
        const d = self.data;
        if (sub_off + 14 > d.len) return error.InvalidFont;

        const seg_count_x2 = readU16(d, sub_off + 6);
        const seg_count = seg_count_x2 / 2;
        if (seg_count == 0) return;

        // Array offsets within the subtable
        const end_code_off = sub_off + 14;
        const start_code_off = end_code_off + @as(u32, seg_count) * 2 + 2; // +2 for reservedPad
        const id_delta_off = start_code_off + @as(u32, seg_count) * 2;
        const id_range_off = id_delta_off + @as(u32, seg_count) * 2;

        // Validate bounds
        if (id_range_off + @as(u32, seg_count) * 2 > d.len) return error.InvalidFont;

        var seg: u16 = 0;
        while (seg < seg_count) : (seg += 1) {
            const end_code = readU16(d, end_code_off + @as(u32, seg) * 2);
            const start_code = readU16(d, start_code_off + @as(u32, seg) * 2);
            const id_delta = readI16(d, id_delta_off + @as(u32, seg) * 2);
            const id_range_offset = readU16(d, id_range_off + @as(u32, seg) * 2);

            if (start_code == 0xFFFF) break;

            var c: u32 = start_code;
            while (c <= end_code) : (c += 1) {
                var glyph_index: u16 = 0;

                if (id_range_offset == 0) {
                    // glyph index = (c + idDelta) mod 65536
                    const raw = @as(i32, @intCast(c)) + @as(i32, id_delta);
                    glyph_index = @truncate(@as(u32, @bitCast(raw)));
                } else {
                    // glyph index from glyphIndexArray
                    const range_off_pos = id_range_off + @as(u32, seg) * 2;
                    const glyph_array_off = range_off_pos + id_range_offset + (c - start_code) * 2;
                    if (glyph_array_off + 2 <= d.len) {
                        glyph_index = readU16(d, glyph_array_off);
                        if (glyph_index != 0) {
                            const raw = @as(i32, @intCast(glyph_index)) + @as(i32, id_delta);
                            glyph_index = @as(u16, @truncate(@as(u32, @bitCast(raw))));
                        }
                    }
                }

                if (glyph_index != 0) {
                    try self.char_to_glyph.put(self.allocator, c, glyph_index);
                }
            }
        }
    }

    fn parseCmapFormat0(self: *TrueTypeFont, sub_off: u32) !void {
        const d = self.data;
        if (sub_off + 6 + 256 > d.len) return error.InvalidFont;

        var i: u32 = 0;
        while (i < 256) : (i += 1) {
            const glyph_index = d[sub_off + 6 + i];
            if (glyph_index != 0) {
                try self.char_to_glyph.put(self.allocator, i, @as(u16, glyph_index));
            }
        }
    }

    fn parseName(self: *TrueTypeFont) !void {
        const entry = self.tables.get("name") orelse return;
        const d = self.data;
        const off = entry.offset;
        if (entry.length < 6) return;

        const count = readU16(d, off + 2);
        const string_offset = off + readU16(d, off + 4);

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const rec = off + 6 + @as(u32, i) * 12;
            if (rec + 12 > d.len) break;

            const platform_id = readU16(d, rec);
            const name_id = readU16(d, rec + 6);
            const str_length = readU16(d, rec + 8);
            const str_off = string_offset + readU16(d, rec + 10);

            if (str_off + str_length > d.len) continue;

            // Prefer platform 1 (Macintosh) for simple ASCII names
            if (platform_id == 1) {
                const name_str = d[str_off..][0..str_length];
                switch (name_id) {
                    1 => self.font_family = name_str,
                    2 => self.font_subfamily = name_str,
                    6 => self.postscript_name = name_str,
                    else => {},
                }
            } else if (platform_id == 3) {
                // Windows platform: UTF-16BE - just use the ASCII chars
                // We store the raw bytes; the embedder can handle encoding
                const name_str = d[str_off..][0..str_length];
                switch (name_id) {
                    1 => if (std.mem.eql(u8, self.font_family, "Unknown")) {
                        self.font_family = name_str;
                    },
                    2 => if (std.mem.eql(u8, self.font_subfamily, "Regular")) {
                        self.font_subfamily = name_str;
                    },
                    6 => if (std.mem.eql(u8, self.postscript_name, "Unknown")) {
                        self.postscript_name = name_str;
                    },
                    else => {},
                }
            }
        }
    }

    fn parsePost(self: *TrueTypeFont) !void {
        const entry = self.tables.get("post") orelse return;
        if (entry.length < 32) return;
        const off = entry.offset;

        // italic angle is a 16.16 fixed-point
        const int_part = readI16(self.data, off + 4);
        const frac_part = readU16(self.data, off + 6);
        self.italic_angle = @as(f64, @floatFromInt(int_part)) +
            @as(f64, @floatFromInt(frac_part)) / 65536.0;

        self.is_fixed_pitch = readU32(self.data, off + 12) != 0;
    }

    fn parseOs2(self: *TrueTypeFont) !void {
        const entry = self.tables.get("OS/2") orelse return;
        if (entry.length < 78) return;
        const off = entry.offset;

        const version = readU16(self.data, off);
        self.weight_class = readU16(self.data, off + 4);
        self.width_class = readU16(self.data, off + 6);
        self.fs_type = readU16(self.data, off + 8);

        // capHeight and xHeight are only in version >= 2
        if (version >= 2 and entry.length >= 96) {
            self.cap_height = readI16(self.data, off + 88);
            self.x_height = readI16(self.data, off + 86);
        }
    }

    /// Get the raw table data for a given table tag.
    pub fn getTableData(self: *const TrueTypeFont, tag: []const u8) ?[]const u8 {
        const entry = self.tables.get(tag) orelse return null;
        return self.data[entry.offset..][0..entry.length];
    }
};

// ── Helper functions for reading big-endian values ──────────────────

pub fn readU16(data: []const u8, offset: anytype) u16 {
    const off: usize = @intCast(offset);
    if (off + 2 > data.len) return 0;
    return std.mem.readInt(u16, data[off..][0..2], .big);
}

pub fn readI16(data: []const u8, offset: anytype) i16 {
    const off: usize = @intCast(offset);
    if (off + 2 > data.len) return 0;
    return std.mem.readInt(i16, data[off..][0..2], .big);
}

pub fn readU32(data: []const u8, offset: anytype) u32 {
    const off: usize = @intCast(offset);
    if (off + 4 > data.len) return 0;
    return std.mem.readInt(u32, data[off..][0..4], .big);
}

pub fn readI32(data: []const u8, offset: anytype) i32 {
    const off: usize = @intCast(offset);
    if (off + 4 > data.len) return 0;
    return std.mem.readInt(i32, data[off..][0..4], .big);
}

// ── Tests ───────────────────────────────────────────────────────────

test "readU16 big endian" {
    const data = [_]u8{ 0x01, 0x00 };
    try std.testing.expectEqual(@as(u16, 256), readU16(&data, 0));
}

test "readI16 big endian negative" {
    const data = [_]u8{ 0xFF, 0xFE };
    try std.testing.expectEqual(@as(i16, -2), readI16(&data, 0));
}

test "readU32 big endian" {
    const data = [_]u8{ 0x00, 0x01, 0x00, 0x00 };
    try std.testing.expectEqual(@as(u32, 0x00010000), readU32(&data, 0));
}

test "readU16 out of bounds returns zero" {
    const data = [_]u8{0x01};
    try std.testing.expectEqual(@as(u16, 0), readU16(&data, 0));
}

test "reject too-short data" {
    const data = [_]u8{ 0, 0, 0, 0, 0, 0 };
    const result = TrueTypeFont.init(std.testing.allocator, &data);
    try std.testing.expectError(error.InvalidFont, result);
}

test "reject invalid sfVersion" {
    // 12 bytes with invalid sfVersion
    const data = [12]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0, 0, 0, 0, 0, 0, 0, 0 };
    const result = TrueTypeFont.init(std.testing.allocator, &data);
    try std.testing.expectError(error.InvalidFont, result);
}

test "parse minimal valid TTF structure" {
    // Build a minimal TTF with head, maxp, hhea, hmtx, cmap tables
    const font_data = try buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 2), font.num_glyphs);
    try std.testing.expectEqual(@as(u16, 1000), font.units_per_em);
    try std.testing.expectEqual(@as(i16, 800), font.ascent);
    try std.testing.expectEqual(@as(i16, -200), font.descent);
}

test "glyph width lookup" {
    const font_data = try buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    // Glyph 0 (.notdef) should have width 500
    try std.testing.expectEqual(@as(u16, 500), font.getGlyphWidth(0));
    // Glyph 1 should have width 600
    try std.testing.expectEqual(@as(u16, 600), font.getGlyphWidth(1));
}

test "text width measurement" {
    const font_data = try buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    // 'A' (0x41) maps to glyph 1 with width 600
    // At 1000 units_per_em and font_size 10: width = 600 * 10 / 1000 = 6.0
    const w = font.textWidth("A", 10.0);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), w, 0.01);
}

test "getGlyphIndex returns null for unmapped codepoint" {
    const font_data = try buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    // Codepoint 0x1234 is not in our minimal cmap
    try std.testing.expect(font.getGlyphIndex(0x1234) == null);
}

/// Builds a minimal valid TrueType font for testing.
/// Contains: head, maxp, hhea, hmtx, cmap tables.
/// Maps codepoint 0x41 ('A') to glyph index 1.
pub fn buildMinimalTestFont(allocator: Allocator) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    const num_tables: u16 = 5; // head, maxp, hhea, hmtx, cmap

    // ── Offset table (12 bytes) ──
    try writer.writeInt(u32, 0x00010000, .big); // sfVersion
    try writer.writeInt(u16, num_tables, .big);
    try writer.writeInt(u16, 0, .big); // searchRange (not validated)
    try writer.writeInt(u16, 0, .big); // entrySelector
    try writer.writeInt(u16, 0, .big); // rangeShift

    // Table directory starts at offset 12, each entry is 16 bytes
    // Table data starts after directory: 12 + 5*16 = 92
    const dir_end: u32 = 12 + num_tables * 16;

    // Table sizes
    const head_size: u32 = 54;
    const maxp_size: u32 = 6;
    const hhea_size: u32 = 36;
    const hmtx_size: u32 = 8; // 2 glyphs * 4 bytes each
    const cmap_size: u32 = 4 + 8 + 262; // header + 1 subtable record + format 0 subtable

    const head_off = dir_end;
    const maxp_off = head_off + head_size;
    const hhea_off = maxp_off + maxp_size;
    const hmtx_off = hhea_off + hhea_size;
    const cmap_off = hmtx_off + hmtx_size;

    // ── Table directory entries ──

    // head
    try writer.writeAll("head");
    try writer.writeInt(u32, 0, .big); // checksum
    try writer.writeInt(u32, head_off, .big);
    try writer.writeInt(u32, head_size, .big);

    // maxp
    try writer.writeAll("maxp");
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(u32, maxp_off, .big);
    try writer.writeInt(u32, maxp_size, .big);

    // hhea
    try writer.writeAll("hhea");
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(u32, hhea_off, .big);
    try writer.writeInt(u32, hhea_size, .big);

    // hmtx
    try writer.writeAll("hmtx");
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(u32, hmtx_off, .big);
    try writer.writeInt(u32, hmtx_size, .big);

    // cmap
    try writer.writeAll("cmap");
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(u32, cmap_off, .big);
    try writer.writeInt(u32, cmap_size, .big);

    // ── head table (54 bytes) ──
    try writer.writeInt(u32, 0x00010000, .big); // version
    try writer.writeInt(u32, 0x00010000, .big); // fontRevision
    try writer.writeInt(u32, 0, .big); // checksumAdjustment
    try writer.writeInt(u32, 0x5F0F3CF5, .big); // magicNumber
    try writer.writeInt(u16, 0x000B, .big); // flags
    try writer.writeInt(u16, 1000, .big); // unitsPerEm
    try writer.writeInt(u64, 0, .big); // created
    try writer.writeInt(u64, 0, .big); // modified
    try writer.writeInt(i16, 0, .big); // xMin
    try writer.writeInt(i16, -200, .big); // yMin
    try writer.writeInt(i16, 1000, .big); // xMax
    try writer.writeInt(i16, 800, .big); // yMax
    try writer.writeInt(u16, 0, .big); // macStyle
    try writer.writeInt(u16, 8, .big); // lowestRecPPEM
    try writer.writeInt(i16, 2, .big); // fontDirectionHint
    try writer.writeInt(i16, 1, .big); // indexToLocFormat
    try writer.writeInt(i16, 0, .big); // glyphDataFormat

    // ── maxp table (6 bytes) ──
    try writer.writeInt(u32, 0x00010000, .big); // version
    try writer.writeInt(u16, 2, .big); // numGlyphs

    // ── hhea table (36 bytes) ──
    try writer.writeInt(u32, 0x00010000, .big); // version
    try writer.writeInt(i16, 800, .big); // ascent
    try writer.writeInt(i16, -200, .big); // descent
    try writer.writeInt(i16, 0, .big); // lineGap
    try writer.writeInt(u16, 1000, .big); // advanceWidthMax
    try writer.writeInt(i16, 0, .big); // minLeftSideBearing
    try writer.writeInt(i16, 0, .big); // minRightSideBearing
    try writer.writeInt(i16, 1000, .big); // xMaxExtent
    try writer.writeInt(i16, 1, .big); // caretSlopeRise
    try writer.writeInt(i16, 0, .big); // caretSlopeRun
    try writer.writeInt(i16, 0, .big); // caretOffset
    try writer.writeInt(i16, 0, .big); // reserved
    try writer.writeInt(i16, 0, .big); // reserved
    try writer.writeInt(i16, 0, .big); // reserved
    try writer.writeInt(i16, 0, .big); // reserved
    try writer.writeInt(i16, 0, .big); // metricDataFormat
    try writer.writeInt(u16, 2, .big); // numberOfHMetrics

    // ── hmtx table (8 bytes = 2 long metrics) ──
    try writer.writeInt(u16, 500, .big); // advanceWidth[0] (.notdef)
    try writer.writeInt(i16, 0, .big); // lsb[0]
    try writer.writeInt(u16, 600, .big); // advanceWidth[1] (glyph for 'A')
    try writer.writeInt(i16, 0, .big); // lsb[1]

    // ── cmap table ──
    // Header
    try writer.writeInt(u16, 0, .big); // version
    try writer.writeInt(u16, 1, .big); // numSubtables

    // Subtable record (platform 1 = Macintosh, encoding 0 = Roman)
    try writer.writeInt(u16, 1, .big); // platformID
    try writer.writeInt(u16, 0, .big); // encodingID
    try writer.writeInt(u32, 4 + 8, .big); // offset (after header + 1 record)

    // Format 0 subtable (262 bytes)
    try writer.writeInt(u16, 0, .big); // format
    try writer.writeInt(u16, 262, .big); // length
    try writer.writeInt(u16, 0, .big); // language

    // 256-byte glyph index array
    // Map 0x41 ('A') -> glyph 1, everything else -> 0
    var glyph_array: [256]u8 = [_]u8{0} ** 256;
    glyph_array[0x41] = 1;
    try writer.writeAll(&glyph_array);

    return try buf.toOwnedSlice(allocator);
}
