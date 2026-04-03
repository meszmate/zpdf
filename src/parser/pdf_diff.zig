const std = @import("std");
const Allocator = std.mem.Allocator;
const pdf_parser = @import("pdf_parser.zig");
const ParsedDocument = pdf_parser.ParsedDocument;
const ParsedPage = pdf_parser.ParsedPage;
const text_extractor = @import("text_extractor.zig");
const DocumentInfo = @import("../metadata/info_dict.zig").DocumentInfo;

/// Classification of a difference between two PDFs.
pub const DiffType = enum {
    added,
    removed,
    changed,
    unchanged,
};

/// A difference in page-level properties (dimensions, presence).
pub const PageDiff = struct {
    page_index: usize,
    diff_type: DiffType,
    width_a: ?f64,
    height_a: ?f64,
    width_b: ?f64,
    height_b: ?f64,
};

/// A difference in document metadata fields.
pub const MetadataDiff = struct {
    field: []const u8,
    diff_type: DiffType,
    value_a: ?[]const u8,
    value_b: ?[]const u8,
};

/// A difference in extracted text for a given page.
pub const TextDiff = struct {
    page_index: usize,
    diff_type: DiffType,
    text_a: ?[]const u8,
    text_b: ?[]const u8,
};

/// The full result of comparing two parsed PDF documents.
pub const DiffResult = struct {
    allocator: Allocator,
    page_count_a: usize,
    page_count_b: usize,
    page_diffs: []PageDiff,
    metadata_diffs: []MetadataDiff,
    text_diffs: []TextDiff,

    pub fn deinit(self: *DiffResult) void {
        for (self.text_diffs) |td| {
            if (td.text_a) |t| self.allocator.free(t);
            if (td.text_b) |t| self.allocator.free(t);
        }
        self.allocator.free(self.text_diffs);
        self.allocator.free(self.metadata_diffs);
        self.allocator.free(self.page_diffs);
    }

    /// Returns true when the two documents are structurally identical.
    pub fn isIdentical(self: *const DiffResult) bool {
        for (self.page_diffs) |d| {
            if (d.diff_type != .unchanged) return false;
        }
        for (self.metadata_diffs) |d| {
            if (d.diff_type != .unchanged) return false;
        }
        for (self.text_diffs) |d| {
            if (d.diff_type != .unchanged) return false;
        }
        return true;
    }
};

/// Compare two parsed PDF documents and return a structural diff.
pub fn diffPdfs(allocator: Allocator, pdf_a: *const ParsedDocument, pdf_b: *const ParsedDocument) !DiffResult {
    var page_diffs = std.ArrayListUnmanaged(PageDiff){};
    defer page_diffs.deinit(allocator);

    var text_diffs = std.ArrayListUnmanaged(TextDiff){};
    defer text_diffs.deinit(allocator);

    const max_pages = @max(pdf_a.pages.items.len, pdf_b.pages.items.len);

    for (0..max_pages) |i| {
        const has_a = i < pdf_a.pages.items.len;
        const has_b = i < pdf_b.pages.items.len;

        if (has_a and has_b) {
            const pa = &pdf_a.pages.items[i];
            const pb = &pdf_b.pages.items[i];
            const dims_equal = pa.width == pb.width and pa.height == pb.height;
            try page_diffs.append(allocator, .{
                .page_index = i,
                .diff_type = if (dims_equal) .unchanged else .changed,
                .width_a = pa.width,
                .height_a = pa.height,
                .width_b = pb.width,
                .height_b = pb.height,
            });

            // Compare text content
            const text_a = try extractPageText(allocator, pa);
            errdefer allocator.free(text_a);
            const text_b = try extractPageText(allocator, pb);
            errdefer allocator.free(text_b);

            const texts_equal = std.mem.eql(u8, text_a, text_b);
            if (texts_equal) {
                allocator.free(text_a);
                allocator.free(text_b);
                try text_diffs.append(allocator, .{
                    .page_index = i,
                    .diff_type = .unchanged,
                    .text_a = null,
                    .text_b = null,
                });
            } else {
                try text_diffs.append(allocator, .{
                    .page_index = i,
                    .diff_type = .changed,
                    .text_a = text_a,
                    .text_b = text_b,
                });
            }
        } else if (has_a) {
            const pa = &pdf_a.pages.items[i];
            const text_a = try extractPageText(allocator, pa);
            try page_diffs.append(allocator, .{
                .page_index = i,
                .diff_type = .removed,
                .width_a = pa.width,
                .height_a = pa.height,
                .width_b = null,
                .height_b = null,
            });
            try text_diffs.append(allocator, .{
                .page_index = i,
                .diff_type = .removed,
                .text_a = text_a,
                .text_b = null,
            });
        } else {
            const pb = &pdf_b.pages.items[i];
            const text_b = try extractPageText(allocator, pb);
            try page_diffs.append(allocator, .{
                .page_index = i,
                .diff_type = .added,
                .width_a = null,
                .height_a = null,
                .width_b = pb.width,
                .height_b = pb.height,
            });
            try text_diffs.append(allocator, .{
                .page_index = i,
                .diff_type = .added,
                .text_a = null,
                .text_b = text_b,
            });
        }
    }

    // Compare metadata
    var meta_diffs = std.ArrayListUnmanaged(MetadataDiff){};
    defer meta_diffs.deinit(allocator);

    const info_a = pdf_a.info orelse DocumentInfo{};
    const info_b = pdf_b.info orelse DocumentInfo{};

    try compareMetaField(allocator, &meta_diffs, "title", info_a.title, info_b.title);
    try compareMetaField(allocator, &meta_diffs, "author", info_a.author, info_b.author);
    try compareMetaField(allocator, &meta_diffs, "subject", info_a.subject, info_b.subject);
    try compareMetaField(allocator, &meta_diffs, "keywords", info_a.keywords, info_b.keywords);
    try compareMetaField(allocator, &meta_diffs, "creator", info_a.creator, info_b.creator);
    try compareMetaField(allocator, &meta_diffs, "producer", info_a.producer, info_b.producer);

    return DiffResult{
        .allocator = allocator,
        .page_count_a = pdf_a.pages.items.len,
        .page_count_b = pdf_b.pages.items.len,
        .page_diffs = try page_diffs.toOwnedSlice(allocator),
        .metadata_diffs = try meta_diffs.toOwnedSlice(allocator),
        .text_diffs = try text_diffs.toOwnedSlice(allocator),
    };
}

fn extractPageText(allocator: Allocator, page: *const ParsedPage) ![]const u8 {
    var result = try text_extractor.extractText(allocator, page, .{});
    defer {
        for (result.lines) |line| allocator.free(line.fragments);
        allocator.free(result.lines);
        for (result.fragments) |frag| allocator.free(frag.text);
        allocator.free(result.fragments);
    }
    const text = result.plain_text;
    // We take ownership of plain_text by not freeing it
    result.plain_text = allocator.alloc(u8, 0) catch unreachable;
    return text;
}

fn compareMetaField(
    allocator: Allocator,
    diffs: *std.ArrayListUnmanaged(MetadataDiff),
    field: []const u8,
    val_a: ?[]const u8,
    val_b: ?[]const u8,
) !void {
    const diff_type: DiffType = blk: {
        if (val_a == null and val_b == null) break :blk .unchanged;
        if (val_a != null and val_b == null) break :blk .removed;
        if (val_a == null and val_b != null) break :blk .added;
        if (std.mem.eql(u8, val_a.?, val_b.?)) break :blk .unchanged;
        break :blk .changed;
    };
    try diffs.append(allocator, .{
        .field = field,
        .diff_type = diff_type,
        .value_a = val_a,
        .value_b = val_b,
    });
}

// -- Tests --

test "pdf_diff: identical empty documents" {
    const allocator = std.testing.allocator;

    var doc_a = ParsedDocument{
        .allocator = allocator,
        .info = null,
        .pages = .{},
        .form_fields = null,
        .version = "1.4",
    };
    defer doc_a.deinit();

    var doc_b = ParsedDocument{
        .allocator = allocator,
        .info = null,
        .pages = .{},
        .form_fields = null,
        .version = "1.4",
    };
    defer doc_b.deinit();

    var result = try diffPdfs(allocator, &doc_a, &doc_b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.page_diffs.len);
    try std.testing.expectEqual(@as(usize, 0), result.text_diffs.len);
    try std.testing.expect(result.isIdentical());
}

test "pdf_diff: different page counts" {
    const allocator = std.testing.allocator;

    var pages_a = std.ArrayListUnmanaged(ParsedPage){};
    defer pages_a.deinit(allocator);
    try pages_a.append(allocator, .{ .width = 612, .height = 792, .content_data = "" });

    var doc_a = ParsedDocument{
        .allocator = allocator,
        .info = null,
        .pages = pages_a,
        .form_fields = null,
        .version = "1.4",
    };

    var doc_b = ParsedDocument{
        .allocator = allocator,
        .info = null,
        .pages = .{},
        .form_fields = null,
        .version = "1.4",
    };
    defer doc_b.deinit();

    var result = try diffPdfs(allocator, &doc_a, &doc_b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.page_count_a);
    try std.testing.expectEqual(@as(usize, 0), result.page_count_b);
    try std.testing.expectEqual(@as(usize, 1), result.page_diffs.len);
    try std.testing.expectEqual(DiffType.removed, result.page_diffs[0].diff_type);
    try std.testing.expect(!result.isIdentical());
}

test "pdf_diff: metadata difference" {
    const allocator = std.testing.allocator;

    var doc_a = ParsedDocument{
        .allocator = allocator,
        .info = DocumentInfo{ .title = "Doc A" },
        .pages = .{},
        .form_fields = null,
        .version = "1.4",
    };
    defer doc_a.deinit();

    var doc_b = ParsedDocument{
        .allocator = allocator,
        .info = DocumentInfo{ .title = "Doc B" },
        .pages = .{},
        .form_fields = null,
        .version = "1.4",
    };
    defer doc_b.deinit();

    var result = try diffPdfs(allocator, &doc_a, &doc_b);
    defer result.deinit();

    // Find the title diff
    var found_title = false;
    for (result.metadata_diffs) |md| {
        if (std.mem.eql(u8, md.field, "title")) {
            try std.testing.expectEqual(DiffType.changed, md.diff_type);
            found_title = true;
        }
    }
    try std.testing.expect(found_title);
    try std.testing.expect(!result.isIdentical());
}

test "pdf_diff: same dimensions unchanged" {
    const allocator = std.testing.allocator;

    var pages_a = std.ArrayListUnmanaged(ParsedPage){};
    defer pages_a.deinit(allocator);
    try pages_a.append(allocator, .{ .width = 612, .height = 792, .content_data = "" });

    var pages_b = std.ArrayListUnmanaged(ParsedPage){};
    defer pages_b.deinit(allocator);
    try pages_b.append(allocator, .{ .width = 612, .height = 792, .content_data = "" });

    var doc_a = ParsedDocument{
        .allocator = allocator,
        .info = null,
        .pages = pages_a,
        .form_fields = null,
        .version = "1.4",
    };

    var doc_b = ParsedDocument{
        .allocator = allocator,
        .info = null,
        .pages = pages_b,
        .form_fields = null,
        .version = "1.4",
    };

    var result = try diffPdfs(allocator, &doc_a, &doc_b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.page_diffs.len);
    try std.testing.expectEqual(DiffType.unchanged, result.page_diffs[0].diff_type);
    try std.testing.expect(result.isIdentical());
}
