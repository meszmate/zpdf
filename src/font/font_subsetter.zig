const std = @import("std");
const Allocator = std.mem.Allocator;
const truetype = @import("truetype.zig");
const TrueTypeFont = truetype.TrueTypeFont;
const readU16 = truetype.readU16;
const readU32 = truetype.readU32;
const readI16 = truetype.readI16;

/// Result of a font subsetting operation.
pub const SubsetResult = struct {
    /// The subsetted font data (valid TrueType file).
    font_data: []u8,
    /// Mapping from original glyph indices to new subset indices.
    glyph_map: std.AutoHashMapUnmanaged(u16, u16),
    /// Number of glyphs in the subset.
    num_glyphs: u16,
    allocator: Allocator,

    pub fn deinit(self: *SubsetResult) void {
        self.allocator.free(self.font_data);
        self.glyph_map.deinit(self.allocator);
    }
};

/// Create a subset of a TrueType font containing only the specified glyphs.
/// Always includes glyph 0 (.notdef).
pub fn subset(
    allocator: Allocator,
    font: *const TrueTypeFont,
    used_glyphs: []const u16,
) !SubsetResult {
    // Collect unique glyph indices, always include 0
    var glyph_set = std.AutoHashMapUnmanaged(u16, void){};
    defer glyph_set.deinit(allocator);
    try glyph_set.put(allocator, 0, {});
    for (used_glyphs) |gid| {
        if (gid < font.num_glyphs) {
            try glyph_set.put(allocator, gid, {});
        }
    }

    // Collect composite glyph components if glyf table exists
    if (font.getTableData("glyf")) |glyf_data| {
        if (font.getTableData("loca")) |loca_data| {
            try collectCompositeComponents(allocator, font, glyf_data, loca_data, &glyph_set);
        }
    }

    // Sort glyph indices and build old->new mapping
    var sorted_glyphs: std.ArrayListUnmanaged(u16) = .{};
    defer sorted_glyphs.deinit(allocator);
    var set_iter = glyph_set.keyIterator();
    while (set_iter.next()) |key| {
        try sorted_glyphs.append(allocator, key.*);
    }
    std.mem.sort(u16, sorted_glyphs.items, {}, std.sort.asc(u16));

    var glyph_map = std.AutoHashMapUnmanaged(u16, u16){};
    for (sorted_glyphs.items, 0..) |old_gid, new_idx| {
        try glyph_map.put(allocator, old_gid, @intCast(new_idx));
    }

    const num_subset_glyphs: u16 = @intCast(sorted_glyphs.items.len);

    // Build the subset font
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    // We'll build these tables: head, hhea, maxp, hmtx, cmap, loca, glyf, post, name, OS/2
    const num_tables: u16 = countAvailableTables(font);

    // -- Offset table --
    try writer.writeInt(u32, 0x00010000, .big);
    try writer.writeInt(u16, num_tables, .big);
    const search_range = calcSearchRange(num_tables);
    try writer.writeInt(u16, search_range.range, .big);
    try writer.writeInt(u16, search_range.selector, .big);
    try writer.writeInt(u16, search_range.shift, .big);

    // Reserve space for table directory
    const dir_size = @as(usize, num_tables) * 16;
    const dir_start = buf.items.len;
    try buf.appendNTimes(allocator, 0, dir_size);

    // Track table positions for directory
    var table_entries: std.ArrayListUnmanaged(TableDirEntry) = .{};
    defer table_entries.deinit(allocator);

    // -- head table --
    {
        const entry = try writeTableFromFont(allocator, font, "head", &buf);
        if (entry) |e| try table_entries.append(allocator, e);
    }

    // -- hhea table --
    {
        const hhea_start = buf.items.len;
        if (font.getTableData("hhea")) |hhea_data| {
            try buf.appendSlice(allocator, hhea_data);
            if (buf.items.len >= hhea_start + 36) {
                std.mem.writeInt(u16, buf.items[hhea_start + 34 ..][0..2], num_subset_glyphs, .big);
            }
            padToAlignment(allocator, &buf);
            try table_entries.append(allocator, .{
                .tag = "hhea".*,
                .offset = @intCast(hhea_start),
                .length = @intCast(buf.items.len - hhea_start),
            });
        }
    }

    // -- maxp table --
    {
        const maxp_start = buf.items.len;
        if (font.getTableData("maxp")) |maxp_data| {
            try buf.appendSlice(allocator, maxp_data);
            if (buf.items.len >= maxp_start + 6) {
                std.mem.writeInt(u16, buf.items[maxp_start + 4 ..][0..2], num_subset_glyphs, .big);
            }
            padToAlignment(allocator, &buf);
            try table_entries.append(allocator, .{
                .tag = "maxp".*,
                .offset = @intCast(maxp_start),
                .length = @intCast(buf.items.len - maxp_start),
            });
        }
    }

    // -- hmtx table --
    {
        const hmtx_start = buf.items.len;
        for (sorted_glyphs.items) |old_gid| {
            const aw = font.getGlyphWidth(old_gid);
            const lsb: i16 = if (old_gid < font.left_side_bearings.len)
                font.left_side_bearings[old_gid]
            else
                0;
            try writer.writeInt(u16, aw, .big);
            try writer.writeInt(i16, lsb, .big);
        }
        padToAlignment(allocator, &buf);
        try table_entries.append(allocator, .{
            .tag = "hmtx".*,
            .offset = @intCast(hmtx_start),
            .length = @intCast(buf.items.len - hmtx_start),
        });
    }

    // -- cmap table --
    {
        const cmap_start = buf.items.len;
        try buildSubsetCmap(allocator, font, &glyph_map, &buf);
        padToAlignment(allocator, &buf);
        try table_entries.append(allocator, .{
            .tag = "cmap".*,
            .offset = @intCast(cmap_start),
            .length = @intCast(buf.items.len - cmap_start),
        });
    }

    // -- glyf and loca tables --
    if (font.getTableData("glyf") != null and font.getTableData("loca") != null) {
        const loca_start = buf.items.len;
        const use_long = font.index_to_loc_format == 1;

        const loca_entry_size: usize = if (use_long) 4 else 2;
        const loca_size = (@as(usize, num_subset_glyphs) + 1) * loca_entry_size;
        try buf.appendNTimes(allocator, 0, loca_size);
        padToAlignment(allocator, &buf);
        const loca_end = buf.items.len;

        const glyf_start = buf.items.len;

        const glyf_data = font.getTableData("glyf").?;
        const loca_data = font.getTableData("loca").?;
        var glyf_offset: u32 = 0;

        for (sorted_glyphs.items, 0..) |old_gid, new_idx| {
            if (use_long) {
                const pos = loca_start + new_idx * 4;
                std.mem.writeInt(u32, buf.items[pos..][0..4], glyf_offset, .big);
            } else {
                const pos = loca_start + new_idx * 2;
                std.mem.writeInt(u16, buf.items[pos..][0..2], @intCast(glyf_offset / 2), .big);
            }

            const glyph_data = getGlyphData(loca_data, glyf_data, old_gid, font.index_to_loc_format);
            if (glyph_data.len > 0) {
                try buf.appendSlice(allocator, glyph_data);
                if (glyph_data.len % 2 != 0) {
                    try buf.append(allocator, 0);
                    glyf_offset += @intCast(glyph_data.len + 1);
                } else {
                    glyf_offset += @intCast(glyph_data.len);
                }
            }
        }

        // Final loca entry
        const final_idx = sorted_glyphs.items.len;
        if (use_long) {
            const pos = loca_start + final_idx * 4;
            std.mem.writeInt(u32, buf.items[pos..][0..4], glyf_offset, .big);
        } else {
            const pos = loca_start + final_idx * 2;
            std.mem.writeInt(u16, buf.items[pos..][0..2], @intCast(glyf_offset / 2), .big);
        }

        padToAlignment(allocator, &buf);

        try table_entries.append(allocator, .{
            .tag = "loca".*,
            .offset = @intCast(loca_start),
            .length = @intCast(loca_end - loca_start),
        });
        try table_entries.append(allocator, .{
            .tag = "glyf".*,
            .offset = @intCast(glyf_start),
            .length = @intCast(buf.items.len - glyf_start),
        });
    }

    // -- post table (minimal format 3 - no glyph names) --
    {
        const post_start = buf.items.len;
        try writer.writeInt(u32, 0x00030000, .big);
        try writer.writeInt(u32, 0, .big);
        try writer.writeInt(i16, 0, .big);
        try writer.writeInt(i16, 0, .big);
        try writer.writeInt(u32, 0, .big);
        try writer.writeInt(u32, 0, .big);
        try writer.writeInt(u32, 0, .big);
        try writer.writeInt(u32, 0, .big);
        try writer.writeInt(u32, 0, .big);
        padToAlignment(allocator, &buf);
        try table_entries.append(allocator, .{
            .tag = "post".*,
            .offset = @intCast(post_start),
            .length = @intCast(buf.items.len - post_start),
        });
    }

    // -- name table (copy from original) --
    {
        const entry = try writeTableFromFont(allocator, font, "name", &buf);
        if (entry) |e| try table_entries.append(allocator, e);
    }

    // -- OS/2 table (copy from original) --
    {
        const entry = try writeTableFromFont(allocator, font, "OS/2", &buf);
        if (entry) |e| try table_entries.append(allocator, e);
    }

    // -- Write table directory --
    std.mem.sort(TableDirEntry, table_entries.items, {}, struct {
        fn lessThan(_: void, a: TableDirEntry, b: TableDirEntry) bool {
            return std.mem.order(u8, &a.tag, &b.tag) == .lt;
        }
    }.lessThan);

    var dir_pos = dir_start;
    for (table_entries.items) |entry| {
        @memcpy(buf.items[dir_pos..][0..4], &entry.tag);
        std.mem.writeInt(u32, buf.items[dir_pos + 4 ..][0..4], calcChecksum(buf.items[entry.offset..][0..entry.length]), .big);
        std.mem.writeInt(u32, buf.items[dir_pos + 8 ..][0..4], entry.offset, .big);
        std.mem.writeInt(u32, buf.items[dir_pos + 12 ..][0..4], entry.length, .big);
        dir_pos += 16;
    }

    return SubsetResult{
        .font_data = try buf.toOwnedSlice(allocator),
        .glyph_map = glyph_map,
        .num_glyphs = num_subset_glyphs,
        .allocator = allocator,
    };
}

const TableDirEntry = struct {
    tag: [4]u8,
    offset: u32,
    length: u32,
};

fn writeTableFromFont(allocator: Allocator, font: *const TrueTypeFont, tag: []const u8, buf: *std.ArrayListUnmanaged(u8)) !?TableDirEntry {
    const data = font.getTableData(tag) orelse return null;
    const start: u32 = @intCast(buf.items.len);
    try buf.appendSlice(allocator, data);
    padToAlignment(allocator, buf);
    return TableDirEntry{
        .tag = tag[0..4].*,
        .offset = start,
        .length = @intCast(data.len),
    };
}

fn padToAlignment(allocator: Allocator, buf: *std.ArrayListUnmanaged(u8)) void {
    while (buf.items.len % 4 != 0) {
        buf.append(allocator, 0) catch break;
    }
}

fn calcChecksum(data: []const u8) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 4 <= data.len) : (i += 4) {
        sum +%= std.mem.readInt(u32, data[i..][0..4], .big);
    }
    if (i < data.len) {
        var last: [4]u8 = .{ 0, 0, 0, 0 };
        const remaining = data.len - i;
        @memcpy(last[0..remaining], data[i..][0..remaining]);
        sum +%= std.mem.readInt(u32, &last, .big);
    }
    return sum;
}

const SearchRangeResult = struct {
    range: u16,
    selector: u16,
    shift: u16,
};

fn calcSearchRange(num_tables: u16) SearchRangeResult {
    var power: u16 = 1;
    var log2: u16 = 0;
    while (power * 2 <= num_tables) {
        power *= 2;
        log2 += 1;
    }
    return .{
        .range = power * 16,
        .selector = log2,
        .shift = num_tables * 16 - power * 16,
    };
}

fn countAvailableTables(font: *const TrueTypeFont) u16 {
    var count: u16 = 5; // head, hhea, maxp, hmtx, cmap
    count += 1; // post
    if (font.getTableData("glyf") != null and font.getTableData("loca") != null) count += 2;
    if (font.getTableData("name") != null) count += 1;
    if (font.getTableData("OS/2") != null) count += 1;
    return count;
}

fn getGlyphData(loca_data: []const u8, glyf_data: []const u8, glyph_index: u16, loc_format: i16) []const u8 {
    const gid: u32 = glyph_index;
    var start_off: u32 = 0;
    var end_off: u32 = 0;

    if (loc_format == 1) {
        const pos = gid * 4;
        if (pos + 8 > loca_data.len) return &[_]u8{};
        start_off = readU32(loca_data, pos);
        end_off = readU32(loca_data, pos + 4);
    } else {
        const pos = gid * 2;
        if (pos + 4 > loca_data.len) return &[_]u8{};
        start_off = @as(u32, readU16(loca_data, pos)) * 2;
        end_off = @as(u32, readU16(loca_data, pos + 2)) * 2;
    }

    if (start_off >= end_off or end_off > glyf_data.len) return &[_]u8{};
    return glyf_data[start_off..end_off];
}

fn collectCompositeComponents(
    allocator: Allocator,
    font: *const TrueTypeFont,
    glyf_data: []const u8,
    loca_data: []const u8,
    glyph_set: *std.AutoHashMapUnmanaged(u16, void),
) !void {
    var to_check: std.ArrayListUnmanaged(u16) = .{};
    defer to_check.deinit(allocator);

    var iter = glyph_set.keyIterator();
    while (iter.next()) |key| {
        try to_check.append(allocator, key.*);
    }

    var idx: usize = 0;
    while (idx < to_check.items.len) : (idx += 1) {
        const gid = to_check.items[idx];
        const glyph_bytes = getGlyphData(loca_data, glyf_data, gid, font.index_to_loc_format);
        if (glyph_bytes.len < 10) continue;

        const num_contours = readI16(glyph_bytes, 0);
        if (num_contours >= 0) continue;

        var off: usize = 10;
        while (off + 4 <= glyph_bytes.len) {
            const flags = readU16(glyph_bytes, off);
            const component_gid = readU16(glyph_bytes, off + 2);
            off += 4;

            if (component_gid < font.num_glyphs) {
                if (!glyph_set.contains(component_gid)) {
                    try glyph_set.put(allocator, component_gid, {});
                    try to_check.append(allocator, component_gid);
                }
            }

            if (flags & 0x0001 != 0) {
                off += 4;
            } else {
                off += 2;
            }

            if (flags & 0x0008 != 0) {
                off += 2;
            } else if (flags & 0x0040 != 0) {
                off += 4;
            } else if (flags & 0x0080 != 0) {
                off += 8;
            }

            if (flags & 0x0020 == 0) break;
        }
    }
}

fn buildSubsetCmap(
    allocator: Allocator,
    font: *const TrueTypeFont,
    glyph_map: *const std.AutoHashMapUnmanaged(u16, u16),
    buf: *std.ArrayListUnmanaged(u8),
) !void {
    const writer = buf.writer(allocator);

    // Collect mappings: codepoint -> new glyph index
    var mappings: std.ArrayListUnmanaged(CmapMapping) = .{};
    defer mappings.deinit(allocator);

    var iter = font.char_to_glyph.iterator();
    while (iter.next()) |entry| {
        const codepoint = entry.key_ptr.*;
        const old_gid = entry.value_ptr.*;
        if (glyph_map.get(old_gid)) |new_gid| {
            if (codepoint <= 0xFFFF) {
                try mappings.append(allocator, .{
                    .codepoint = @intCast(codepoint),
                    .glyph_index = new_gid,
                });
            }
        }
    }

    std.mem.sort(CmapMapping, mappings.items, {}, struct {
        fn lessThan(_: void, a: CmapMapping, b: CmapMapping) bool {
            return a.codepoint < b.codepoint;
        }
    }.lessThan);

    // Build format 4 segments
    var segments: std.ArrayListUnmanaged(CmapSegment) = .{};
    defer segments.deinit(allocator);

    if (mappings.items.len > 0) {
        var seg_start = mappings.items[0].codepoint;
        var seg_end = seg_start;
        var seg_start_glyph = mappings.items[0].glyph_index;

        for (mappings.items[1..]) |m| {
            const prev_glyph_for_end = seg_start_glyph +% (seg_end - seg_start);
            if (m.codepoint == seg_end + 1 and m.glyph_index == prev_glyph_for_end + 1) {
                seg_end = m.codepoint;
            } else {
                try segments.append(allocator, .{
                    .start_code = seg_start,
                    .end_code = seg_end,
                    .delta = @as(i16, @bitCast(seg_start_glyph -% seg_start)),
                });
                seg_start = m.codepoint;
                seg_end = m.codepoint;
                seg_start_glyph = m.glyph_index;
            }
        }
        try segments.append(allocator, .{
            .start_code = seg_start,
            .end_code = seg_end,
            .delta = @as(i16, @bitCast(seg_start_glyph -% seg_start)),
        });
    }

    // Final segment (0xFFFF)
    try segments.append(allocator, .{
        .start_code = 0xFFFF,
        .end_code = 0xFFFF,
        .delta = 1,
    });

    const seg_count: u16 = @intCast(segments.items.len);
    const subtable_length: u16 = 14 + seg_count * 8;

    // cmap header
    try writer.writeInt(u16, 0, .big);
    try writer.writeInt(u16, 1, .big);

    // Encoding record
    try writer.writeInt(u16, 3, .big);
    try writer.writeInt(u16, 1, .big);
    try writer.writeInt(u32, 12, .big);

    // Format 4 subtable
    try writer.writeInt(u16, 4, .big);
    try writer.writeInt(u16, subtable_length, .big);
    try writer.writeInt(u16, 0, .big);

    const seg_count_x2 = seg_count * 2;
    const sr = calcSearchRange(seg_count);
    try writer.writeInt(u16, seg_count_x2, .big);
    try writer.writeInt(u16, sr.range, .big);
    try writer.writeInt(u16, sr.selector, .big);
    try writer.writeInt(u16, sr.shift, .big);

    for (segments.items) |seg| try writer.writeInt(u16, seg.end_code, .big);
    try writer.writeInt(u16, 0, .big); // reservedPad
    for (segments.items) |seg| try writer.writeInt(u16, seg.start_code, .big);
    for (segments.items) |seg| try writer.writeInt(i16, seg.delta, .big);
    for (segments.items) |_| try writer.writeInt(u16, 0, .big);
}

const CmapMapping = struct {
    codepoint: u16,
    glyph_index: u16,
};

const CmapSegment = struct {
    start_code: u16,
    end_code: u16,
    delta: i16,
};

// ── Tests ───────────────────────────────────────────────────────────

test "subset minimal font" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    const glyphs = [_]u16{1};
    var result = try subset(std.testing.allocator, &font, &glyphs);
    defer result.deinit();

    try std.testing.expectEqual(@as(u16, 2), result.num_glyphs);
    try std.testing.expect(result.glyph_map.get(0) != null);
    try std.testing.expect(result.glyph_map.get(1) != null);
    try std.testing.expect(result.font_data.len > 12);
    try std.testing.expectEqual(
        @as(u32, 0x00010000),
        std.mem.readInt(u32, result.font_data[0..4], .big),
    );
}

test "subset always includes notdef" {
    const font_data = try truetype.buildMinimalTestFont(std.testing.allocator);
    defer std.testing.allocator.free(font_data);

    var font = try TrueTypeFont.init(std.testing.allocator, font_data);
    defer font.deinit();

    const glyphs = [_]u16{};
    var result = try subset(std.testing.allocator, &font, &glyphs);
    defer result.deinit();

    try std.testing.expectEqual(@as(u16, 1), result.num_glyphs);
    try std.testing.expect(result.glyph_map.get(0) != null);
}

test "checksum calculation" {
    const data = [_]u8{ 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02 };
    try std.testing.expectEqual(@as(u32, 3), calcChecksum(&data));
}

test "search range calculation" {
    const r = calcSearchRange(5);
    try std.testing.expectEqual(@as(u16, 64), r.range);
    try std.testing.expectEqual(@as(u16, 2), r.selector);
    try std.testing.expectEqual(@as(u16, 16), r.shift);
}
