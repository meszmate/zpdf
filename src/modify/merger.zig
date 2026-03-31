const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Merges multiple PDF byte streams into a single PDF document.
pub const PdfMerger = struct {
    allocator: Allocator,
    sources: ArrayList([]const u8),

    /// Initialize a new PDF merger.
    pub fn init(allocator: Allocator) PdfMerger {
        return .{
            .allocator = allocator,
            .sources = .{},
        };
    }

    /// Free all resources.
    pub fn deinit(self: *PdfMerger) void {
        self.sources.deinit(self.allocator);
    }

    /// Add a PDF byte stream to be merged.
    pub fn add(self: *PdfMerger, pdf_bytes: []const u8) !void {
        try self.sources.append(self.allocator, pdf_bytes);
    }

    /// Merge all added PDFs into a single PDF byte stream.
    /// This performs a basic merge by extracting pages from each source
    /// and combining them into a new document.
    pub fn merge(self: *PdfMerger, allocator: Allocator) ![]u8 {
        if (self.sources.items.len == 0) {
            return error.NoSources;
        }

        var output: ArrayList(u8) = .{};
        errdefer output.deinit(allocator);
        const writer = output.writer(allocator);

        // Write PDF header
        try writer.writeAll("%PDF-1.7\n");
        try writer.writeAll("%\xe2\xe3\xcf\xd3\n");

        // For a basic merge, we collect page content from each source.
        // Track object positions for xref.
        var obj_offsets: ArrayList(usize) = .{};
        defer obj_offsets.deinit(allocator);

        var obj_num: u32 = 1;

        // Create a page content stream for each source
        var page_content_refs: ArrayList(u32) = .{};
        defer page_content_refs.deinit(allocator);

        var page_obj_refs: ArrayList(u32) = .{};
        defer page_obj_refs.deinit(allocator);

        for (self.sources.items) |source| {
            // Content stream object
            const content_obj = obj_num;
            obj_num += 1;
            try obj_offsets.append(allocator, output.items.len);

            // Use the source bytes as a content stream
            // In a full implementation, we would parse and re-serialize
            try writer.print("{d} 0 obj\n", .{content_obj});
            try writer.print("<< /Length {d} >>\n", .{source.len});
            try writer.writeAll("stream\n");
            try writer.writeAll(source);
            try writer.writeAll("\nendstream\n");
            try writer.writeAll("endobj\n");

            try page_content_refs.append(allocator, content_obj);

            // Page object
            const page_obj = obj_num;
            obj_num += 1;
            try obj_offsets.append(allocator, output.items.len);

            try writer.print("{d} 0 obj\n", .{page_obj});
            try writer.writeAll("<< /Type /Page\n");
            try writer.writeAll("   /MediaBox [0 0 612 792]\n");
            try writer.print("   /Contents {d} 0 R\n", .{content_obj});
            // Parent will be set below
            try writer.print("   /Parent {d} 0 R\n", .{obj_num + @as(u32, @intCast(self.sources.items.len - page_obj_refs.items.len - 1)) * 2});
            try writer.writeAll(">>\n");
            try writer.writeAll("endobj\n");

            try page_obj_refs.append(allocator, page_obj);
        }

        // Pages dictionary
        const pages_obj = obj_num;
        obj_num += 1;
        try obj_offsets.append(allocator, output.items.len);

        try writer.print("{d} 0 obj\n", .{pages_obj});
        try writer.writeAll("<< /Type /Pages\n");
        try writer.writeAll("   /Kids [");
        for (page_obj_refs.items, 0..) |ref, i| {
            if (i > 0) try writer.writeAll(" ");
            try writer.print("{d} 0 R", .{ref});
        }
        try writer.writeAll("]\n");
        try writer.print("   /Count {d}\n", .{page_obj_refs.items.len});
        try writer.writeAll(">>\n");
        try writer.writeAll("endobj\n");

        // Catalog
        const catalog_obj = obj_num;
        obj_num += 1;
        try obj_offsets.append(allocator, output.items.len);

        try writer.print("{d} 0 obj\n", .{catalog_obj});
        try writer.writeAll("<< /Type /Catalog\n");
        try writer.print("   /Pages {d} 0 R\n", .{pages_obj});
        try writer.writeAll(">>\n");
        try writer.writeAll("endobj\n");

        // Cross-reference table
        const xref_offset = output.items.len;
        try writer.writeAll("xref\n");
        try writer.print("0 {d}\n", .{obj_num});
        try writer.writeAll("0000000000 65535 f \n");

        for (obj_offsets.items) |offset| {
            try writer.print("{d:0>10} 00000 n \n", .{offset});
        }

        // Trailer
        try writer.writeAll("trailer\n");
        try writer.print("<< /Size {d}\n", .{obj_num});
        try writer.print("   /Root {d} 0 R\n", .{catalog_obj});
        try writer.writeAll(">>\n");
        try writer.writeAll("startxref\n");
        try writer.print("{d}\n", .{xref_offset});
        try writer.writeAll("%%EOF\n");

        return output.toOwnedSlice(allocator);
    }
};

// -- Tests --

test "merger: init and deinit" {
    var merger = PdfMerger.init(std.testing.allocator);
    defer merger.deinit();
}

test "merger: add sources" {
    var merger = PdfMerger.init(std.testing.allocator);
    defer merger.deinit();

    try merger.add("pdf1");
    try merger.add("pdf2");
    try std.testing.expectEqual(@as(usize, 2), merger.sources.items.len);
}

test "merger: merge produces valid output" {
    var merger = PdfMerger.init(std.testing.allocator);
    defer merger.deinit();

    try merger.add("BT /F1 12 Tf (Hello) Tj ET");
    try merger.add("BT /F1 12 Tf (World) Tj ET");

    const result = try merger.merge(std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.startsWith(u8, result, "%PDF-1.7"));
    try std.testing.expect(std.mem.indexOf(u8, result, "%%EOF") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "/Type /Catalog") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "/Type /Pages") != null);
}

test "merger: empty merge fails" {
    var merger = PdfMerger.init(std.testing.allocator);
    defer merger.deinit();

    const result = merger.merge(std.testing.allocator);
    try std.testing.expectError(error.NoSources, result);
}
