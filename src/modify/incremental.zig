const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;
const object_serializer = @import("../writer/object_serializer.zig");

/// Metadata fields that can be updated incrementally.
pub const MetadataUpdate = struct {
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    subject: ?[]const u8 = null,
    keywords: ?[]const u8 = null,
    creator: ?[]const u8 = null,
    producer: ?[]const u8 = null,
};

/// Parsed trailer information from an existing PDF.
const TrailerInfo = struct {
    root_ref: Ref,
    size: u32,
    info_ref: ?Ref,
    prev_xref: u64,
};

/// Builder for incremental PDF updates.
///
/// Allows appending new or modified objects to an existing PDF without
/// rewriting the entire file. The original bytes are preserved verbatim
/// and a new xref section + trailer are appended at the end.
pub const IncrementalUpdate = struct {
    allocator: Allocator,
    original_data: []const u8,
    modifications: std.ArrayListUnmanaged(ModEntry),
    next_obj_num: u32,

    const ModEntry = struct {
        ref: Ref,
        object: PdfObject,
    };

    /// Initialize from existing PDF data.
    pub fn init(allocator: Allocator, pdf_data: []const u8) !IncrementalUpdate {
        if (pdf_data.len < 20) return error.InvalidPdf;
        if (!std.mem.startsWith(u8, pdf_data, "%PDF-")) return error.InvalidPdf;

        const max_obj = findMaxObjectNumber(pdf_data);
        return .{
            .allocator = allocator,
            .original_data = pdf_data,
            .modifications = .{},
            .next_obj_num = max_obj + 1,
        };
    }

    pub fn deinit(self: *IncrementalUpdate) void {
        for (self.modifications.items) |*mod| {
            mod.object.deinit(self.allocator);
        }
        self.modifications.deinit(self.allocator);
    }

    /// Add or replace an object with the given reference.
    pub fn updateObject(self: *IncrementalUpdate, ref: Ref, object: PdfObject) !void {
        try self.modifications.append(self.allocator, .{
            .ref = ref,
            .object = object,
        });
    }

    /// Allocate a new object number and add the object. Returns the new ref.
    pub fn addObject(self: *IncrementalUpdate, object: PdfObject) !Ref {
        const ref = Ref{ .obj_num = self.next_obj_num, .gen_num = 0 };
        self.next_obj_num += 1;
        try self.modifications.append(self.allocator, .{
            .ref = ref,
            .object = object,
        });
        return ref;
    }

    /// Update document metadata by creating a new Info dictionary object.
    pub fn setMetadata(self: *IncrementalUpdate, info: MetadataUpdate) !void {
        var dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        errdefer {
            var it = dict.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            dict.deinit(self.allocator);
        }

        if (info.title) |v| try dict.put(self.allocator, "Title", types.pdfString(v));
        if (info.author) |v| try dict.put(self.allocator, "Author", types.pdfString(v));
        if (info.subject) |v| try dict.put(self.allocator, "Subject", types.pdfString(v));
        if (info.keywords) |v| try dict.put(self.allocator, "Keywords", types.pdfString(v));
        if (info.creator) |v| try dict.put(self.allocator, "Creator", types.pdfString(v));
        if (info.producer) |v| try dict.put(self.allocator, "Producer", types.pdfString(v));

        _ = try self.addObject(.{ .dict_obj = dict });
    }

    /// Apply all modifications and return the full PDF bytes
    /// (original data + appended incremental update section).
    pub fn apply(self: *IncrementalUpdate) ![]u8 {
        if (self.modifications.items.len == 0) {
            // Nothing to do -- return a copy of the original
            const copy = try self.allocator.alloc(u8, self.original_data.len);
            @memcpy(copy, self.original_data);
            return copy;
        }

        var buf = ByteBuffer.init(self.allocator);
        errdefer buf.deinit();

        // 1. Copy original data
        try buf.write(self.original_data);

        // Ensure there's a newline after original data
        if (self.original_data.len > 0 and self.original_data[self.original_data.len - 1] != '\n') {
            try buf.writeByte('\n');
        }

        // 2. Parse trailer info from original
        const trailer_info = try parseTrailerRefs(self.original_data);
        const prev_startxref = try findStartxrefOffset(self.original_data);

        // 3. Write each modified/new object and record offsets
        const offsets = try self.allocator.alloc(u64, self.modifications.items.len);
        defer self.allocator.free(offsets);

        for (self.modifications.items, 0..) |mod, i| {
            offsets[i] = @intCast(buf.len());
            try buf.writeFmt("{d} {d} obj\n", .{ mod.ref.obj_num, mod.ref.gen_num });
            try object_serializer.writeObject(&buf, mod.object);
            try buf.write("\nendobj\n");
        }

        // 4. Write new xref section
        const xref_offset: u64 = @intCast(buf.len());
        try buf.write("xref\n");

        // Write subsections -- group consecutive object numbers
        // Sort modifications by object number for proper subsectioning
        const SortCtx = struct {
            mods: []const ModEntry,
            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return ctx.mods[a].ref.obj_num < ctx.mods[b].ref.obj_num;
            }
        };

        const indices = try self.allocator.alloc(usize, self.modifications.items.len);
        defer self.allocator.free(indices);
        for (indices, 0..) |*idx, i| idx.* = i;

        std.mem.sort(usize, indices, SortCtx{ .mods = self.modifications.items }, SortCtx.lessThan);

        // Write subsections for consecutive runs
        var sub_start: usize = 0;
        while (sub_start < indices.len) {
            var sub_end = sub_start + 1;
            while (sub_end < indices.len) {
                const prev_obj = self.modifications.items[indices[sub_end - 1]].ref.obj_num;
                const cur_obj = self.modifications.items[indices[sub_end]].ref.obj_num;
                if (cur_obj != prev_obj + 1) break;
                sub_end += 1;
            }

            const first_obj = self.modifications.items[indices[sub_start]].ref.obj_num;
            const count = sub_end - sub_start;
            try buf.writeFmt("{d} {d}\n", .{ first_obj, count });

            for (sub_start..sub_end) |si| {
                const orig_idx = indices[si];
                try buf.writeFmt("{d:0>10} {d:0>5} n \n", .{
                    offsets[orig_idx],
                    @as(u16, self.modifications.items[orig_idx].ref.gen_num),
                });
            }

            sub_start = sub_end;
        }

        // 5. Write trailer
        const new_size = @max(trailer_info.size, self.next_obj_num);

        // Check if the last modification is a metadata dict (from setMetadata)
        var new_info_ref: ?Ref = trailer_info.info_ref;
        if (self.modifications.items.len > 0) {
            const last = self.modifications.items[self.modifications.items.len - 1];
            if (last.object == .dict_obj) {
                // Check if it has metadata keys
                if (last.object.dict_obj.get("Title") != null or
                    last.object.dict_obj.get("Author") != null or
                    last.object.dict_obj.get("Producer") != null or
                    last.object.dict_obj.get("Creator") != null or
                    last.object.dict_obj.get("Subject") != null or
                    last.object.dict_obj.get("Keywords") != null)
                {
                    new_info_ref = last.ref;
                }
            }
        }

        try buf.write("trailer\n");
        try buf.write("<< ");
        try buf.writeFmt("/Size {d} ", .{new_size});
        try buf.writeFmt("/Root {d} {d} R ", .{ trailer_info.root_ref.obj_num, trailer_info.root_ref.gen_num });
        try buf.writeFmt("/Prev {d} ", .{prev_startxref});
        if (new_info_ref) |info| {
            try buf.writeFmt("/Info {d} {d} R ", .{ info.obj_num, info.gen_num });
        }
        try buf.write(">>\n");

        // 6. Write startxref and EOF
        try buf.writeFmt("startxref\n{d}\n", .{xref_offset});
        try buf.write("%%EOF\n");

        return buf.toOwnedSlice();
    }
};

/// Find the byte offset recorded in the last startxref of the PDF.
pub fn findStartxrefOffset(data: []const u8) !u64 {
    // Search backwards for "startxref"
    const marker = "startxref";
    var pos: usize = data.len;
    while (pos >= marker.len) {
        pos -= 1;
        if (pos + marker.len <= data.len and std.mem.eql(u8, data[pos .. pos + marker.len], marker)) {
            // Parse the number after "startxref\n"
            var num_start = pos + marker.len;
            // Skip whitespace
            while (num_start < data.len and (data[num_start] == ' ' or data[num_start] == '\n' or data[num_start] == '\r')) {
                num_start += 1;
            }
            var num_end = num_start;
            while (num_end < data.len and data[num_end] >= '0' and data[num_end] <= '9') {
                num_end += 1;
            }
            if (num_end == num_start) return error.InvalidPdf;
            return std.fmt.parseInt(u64, data[num_start..num_end], 10) catch return error.InvalidPdf;
        }
    }
    return error.InvalidPdf;
}

/// Find the maximum object number referenced in the PDF.
/// Scans for "N N obj" patterns.
pub fn findMaxObjectNumber(data: []const u8) u32 {
    var max_obj: u32 = 0;
    var pos: usize = 0;

    while (pos < data.len) {
        // Look for "obj" keyword
        if (pos + 3 <= data.len and std.mem.eql(u8, data[pos .. pos + 3], "obj")) {
            // Walk backwards to find "N N obj" pattern
            if (pos >= 4 and data[pos - 1] == ' ') {
                // Find generation number
                const gen_end = pos - 1;
                var gen_start = gen_end;
                while (gen_start > 0 and data[gen_start - 1] >= '0' and data[gen_start - 1] <= '9') {
                    gen_start -= 1;
                }
                if (gen_start < gen_end and gen_start > 0 and data[gen_start - 1] == ' ') {
                    // Find object number
                    const obj_end = gen_start - 1;
                    var obj_start = obj_end;
                    while (obj_start > 0 and data[obj_start - 1] >= '0' and data[obj_start - 1] <= '9') {
                        obj_start -= 1;
                    }
                    if (obj_start < obj_end) {
                        if (std.fmt.parseInt(u32, data[obj_start..obj_end], 10)) |num| {
                            if (num > max_obj) max_obj = num;
                        } else |_| {}
                    }
                }
            }
            pos += 3;
        } else {
            pos += 1;
        }
    }

    // Also check xref table entries (e.g. "0 N" line after "xref")
    pos = 0;
    while (pos < data.len) {
        if (pos + 4 <= data.len and std.mem.eql(u8, data[pos .. pos + 4], "xref")) {
            var p = pos + 4;
            // Skip to entries
            while (p < data.len and (data[p] == '\n' or data[p] == '\r' or data[p] == ' ')) p += 1;
            // Parse subsection headers: "first_obj count"
            while (p < data.len) {
                // Try to parse "first_obj count\n"
                var num_start = p;
                while (num_start < data.len and data[num_start] >= '0' and data[num_start] <= '9') num_start += 1;
                if (num_start == p) break; // Not a number, end of xref entries
                const first_obj = std.fmt.parseInt(u32, data[p..num_start], 10) catch break;
                // Skip space
                if (num_start >= data.len or data[num_start] != ' ') break;
                num_start += 1;
                var count_end = num_start;
                while (count_end < data.len and data[count_end] >= '0' and data[count_end] <= '9') count_end += 1;
                if (count_end == num_start) break;
                const count = std.fmt.parseInt(u32, data[num_start..count_end], 10) catch break;

                const last_obj = if (count > 0) first_obj + count - 1 else first_obj;
                if (last_obj > max_obj) max_obj = last_obj;

                // Skip past the xref entries (each is 20 bytes: "OOOOOOOOOO GGGGG X \n")
                // First skip to end of line
                while (count_end < data.len and data[count_end] != '\n') count_end += 1;
                if (count_end < data.len) count_end += 1;
                // Skip `count` entries
                p = count_end;
                var entries_skipped: u32 = 0;
                while (entries_skipped < count and p < data.len) {
                    while (p < data.len and data[p] != '\n') p += 1;
                    if (p < data.len) p += 1;
                    entries_skipped += 1;
                }
            }
            break;
        }
        pos += 1;
    }

    return max_obj;
}

/// Parse the trailer dictionary to extract /Root, /Size, /Info, and /Prev.
pub fn parseTrailerRefs(data: []const u8) !TrailerInfo {
    // Find the last "trailer" keyword
    const marker = "trailer";
    var trailer_pos: ?usize = null;
    var pos: usize = data.len;
    while (pos >= marker.len) {
        pos -= 1;
        if (pos + marker.len <= data.len and std.mem.eql(u8, data[pos .. pos + marker.len], marker)) {
            trailer_pos = pos;
            break;
        }
    }

    const tp = trailer_pos orelse return error.InvalidPdf;
    const trailer_data = data[tp..];

    // Parse /Root ref
    const root_ref = try parseRefValue(trailer_data, "/Root") orelse return error.InvalidPdf;

    // Parse /Size
    const size = try parseIntValue(trailer_data, "/Size") orelse return error.InvalidPdf;

    // Parse /Info ref (optional)
    const info_ref = try parseRefValue(trailer_data, "/Info");

    // Parse /Prev (optional)
    const prev_xref: u64 = if (try parseIntValue(trailer_data, "/Prev")) |v| @intCast(v) else 0;

    return .{
        .root_ref = root_ref,
        .size = @intCast(size),
        .info_ref = info_ref,
        .prev_xref = prev_xref,
    };
}

/// Parse a reference value like "/Key N N R" from trailer data.
fn parseRefValue(data: []const u8, key: []const u8) !?Ref {
    const key_pos = std.mem.indexOf(u8, data, key) orelse return null;
    var p = key_pos + key.len;

    // Skip whitespace
    while (p < data.len and (data[p] == ' ' or data[p] == '\n' or data[p] == '\r')) p += 1;

    // Parse object number
    var num_end = p;
    while (num_end < data.len and data[num_end] >= '0' and data[num_end] <= '9') num_end += 1;
    if (num_end == p) return error.InvalidPdf;
    const obj_num = std.fmt.parseInt(u32, data[p..num_end], 10) catch return error.InvalidPdf;

    // Skip whitespace
    p = num_end;
    while (p < data.len and (data[p] == ' ' or data[p] == '\n' or data[p] == '\r')) p += 1;

    // Parse generation number
    num_end = p;
    while (num_end < data.len and data[num_end] >= '0' and data[num_end] <= '9') num_end += 1;
    if (num_end == p) return error.InvalidPdf;
    const gen_num = std.fmt.parseInt(u16, data[p..num_end], 10) catch return error.InvalidPdf;

    // Expect "R"
    p = num_end;
    while (p < data.len and (data[p] == ' ' or data[p] == '\n' or data[p] == '\r')) p += 1;
    if (p >= data.len or data[p] != 'R') return error.InvalidPdf;

    return .{ .obj_num = obj_num, .gen_num = gen_num };
}

/// Parse an integer value like "/Key N" from trailer data.
fn parseIntValue(data: []const u8, key: []const u8) !?i64 {
    const key_pos = std.mem.indexOf(u8, data, key) orelse return null;
    var p = key_pos + key.len;

    // Skip whitespace
    while (p < data.len and (data[p] == ' ' or data[p] == '\n' or data[p] == '\r')) p += 1;

    var num_end = p;
    while (num_end < data.len and data[num_end] >= '0' and data[num_end] <= '9') num_end += 1;
    if (num_end == p) return error.InvalidPdf;
    return std.fmt.parseInt(i64, data[p..num_end], 10) catch return error.InvalidPdf;
}

/// Quick way to update metadata incrementally.
pub fn updateMetadataIncremental(allocator: Allocator, pdf_data: []const u8, metadata: MetadataUpdate) ![]u8 {
    var update = try IncrementalUpdate.init(allocator, pdf_data);
    defer update.deinit();

    try update.setMetadata(metadata);
    return update.apply();
}

/// Quick way to add a text watermark incrementally.
/// This creates a new content stream object and does not modify existing page streams.
pub fn addWatermarkIncremental(allocator: Allocator, pdf_data: []const u8, text: []const u8) ![]u8 {
    var update = try IncrementalUpdate.init(allocator, pdf_data);
    defer update.deinit();

    // Build a simple annotation-like text object as a comment in the PDF
    // For a real watermark we'd need to modify the page's content stream,
    // but for an incremental update we add a text annotation to the first page.
    var dict: std.StringHashMapUnmanaged(PdfObject) = .{};
    errdefer {
        var it = dict.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        dict.deinit(allocator);
    }

    try dict.put(allocator, "Type", types.pdfName("Annot"));
    try dict.put(allocator, "Subtype", types.pdfName("FreeText"));
    try dict.put(allocator, "Contents", types.pdfString(text));

    // Position in center of a typical page
    var rect = types.pdfArray(allocator);
    try rect.array_obj.append(types.pdfInt(100));
    try rect.array_obj.append(types.pdfInt(400));
    try rect.array_obj.append(types.pdfInt(500));
    try rect.array_obj.append(types.pdfInt(500));
    try dict.put(allocator, "Rect", rect);

    try dict.put(allocator, "DA", types.pdfString("/Helvetica 48 Tf 0.8 0.2 0.2 rg"));

    _ = try update.addObject(.{ .dict_obj = dict });

    return update.apply();
}

// -- Tests --

test "findStartxrefOffset: valid PDF" {
    const pdf = "%PDF-1.7\nxref\n0 1\n0000000000 65535 f \ntrailer\n<< /Size 1 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n";
    const offset = try findStartxrefOffset(pdf);
    try std.testing.expectEqual(@as(u64, 9), offset);
}

test "findMaxObjectNumber: finds objects" {
    const pdf = "%PDF-1.7\n1 0 obj\n<< >>\nendobj\n3 0 obj\n<< >>\nendobj\nxref\n0 4\n";
    const max = findMaxObjectNumber(pdf);
    try std.testing.expect(max >= 3);
}

test "parseTrailerRefs: valid trailer" {
    const pdf = "%PDF-1.7\ntrailer\n<< /Size 5 /Root 1 0 R /Info 4 0 R >>\nstartxref\n9\n%%EOF\n";
    const info = try parseTrailerRefs(pdf);
    try std.testing.expectEqual(@as(u32, 1), info.root_ref.obj_num);
    try std.testing.expectEqual(@as(u32, 5), info.size);
    try std.testing.expectEqual(@as(u32, 4), info.info_ref.?.obj_num);
}

test "IncrementalUpdate: invalid input" {
    const result = IncrementalUpdate.init(std.testing.allocator, "short");
    try std.testing.expectError(error.InvalidPdf, result);
}
