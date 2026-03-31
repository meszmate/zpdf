const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Errors that can occur during PDF splitting.
pub const SplitError = error{
    InvalidPdf,
    InvalidRange,
    NoPages,
};

/// Split a PDF into individual single-page PDFs.
/// Returns an array of PDF byte streams, one per page.
/// In a full implementation, this would parse the PDF structure.
/// This simplified version wraps each content section as a separate PDF.
pub fn splitByPage(allocator: Allocator, pdf_bytes: []const u8) (Allocator.Error || SplitError)![][]u8 {
    if (pdf_bytes.len == 0) return SplitError.InvalidPdf;

    // Find page boundaries by looking for /Type /Page entries
    var pages: ArrayList([]const u8) = .{};
    defer pages.deinit(allocator);

    // Simple heuristic: find "endobj" boundaries for page objects
    var pos: usize = 0;
    while (pos < pdf_bytes.len) {
        if (std.mem.indexOf(u8, pdf_bytes[pos..], "/Type /Page")) |page_start| {
            const abs_start = pos + page_start;
            // Find the end of this object
            if (std.mem.indexOf(u8, pdf_bytes[abs_start..], "endobj")) |end_offset| {
                const abs_end = abs_start + end_offset + 6; // "endobj".len
                try pages.append(allocator, pdf_bytes[abs_start..abs_end]);
                pos = abs_end;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    if (pages.items.len == 0) {
        // If no page markers found, treat the entire input as one page
        try pages.append(allocator, pdf_bytes);
    }

    // Create individual PDFs for each page
    var result = try allocator.alloc([]u8, pages.items.len);
    errdefer {
        for (result) |r| {
            allocator.free(r);
        }
        allocator.free(result);
    }

    for (pages.items, 0..) |page_content, i| {
        result[i] = try wrapAsSinglePagePdf(allocator, page_content);
    }

    return result;
}

/// Split a PDF by specified page ranges.
/// Each range is a [start, end] pair (0-based, inclusive).
pub fn splitByRanges(allocator: Allocator, pdf_bytes: []const u8, ranges: []const [2]usize) (Allocator.Error || SplitError)![][]u8 {
    if (pdf_bytes.len == 0) return SplitError.InvalidPdf;
    if (ranges.len == 0) return SplitError.InvalidRange;

    // Parse page boundaries
    var page_contents: ArrayList([]const u8) = .{};
    defer page_contents.deinit(allocator);

    var pos: usize = 0;
    while (pos < pdf_bytes.len) {
        if (std.mem.indexOf(u8, pdf_bytes[pos..], "/Type /Page")) |page_start| {
            const abs_start = pos + page_start;
            if (std.mem.indexOf(u8, pdf_bytes[abs_start..], "endobj")) |end_offset| {
                const abs_end = abs_start + end_offset + 6;
                try page_contents.append(allocator, pdf_bytes[abs_start..abs_end]);
                pos = abs_end;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    if (page_contents.items.len == 0) {
        try page_contents.append(allocator, pdf_bytes);
    }

    var result = try allocator.alloc([]u8, ranges.len);
    errdefer {
        for (result) |r| {
            allocator.free(r);
        }
        allocator.free(result);
    }

    for (ranges, 0..) |range, ri| {
        if (range[0] > range[1] or range[1] >= page_contents.items.len) {
            return SplitError.InvalidRange;
        }

        // Combine pages in this range
        var combined: ArrayList(u8) = .{};
        defer combined.deinit(allocator);

        for (range[0]..range[1] + 1) |pi| {
            try combined.appendSlice(allocator, page_contents.items[pi]);
            try combined.append(allocator, '\n');
        }

        result[ri] = try wrapAsSinglePagePdf(allocator, combined.items);
    }

    return result;
}

/// Wrap content as a minimal single-page PDF.
fn wrapAsSinglePagePdf(allocator: Allocator, content: []const u8) ![]u8 {
    var buf: ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("%PDF-1.7\n");

    // Content stream (obj 1)
    try writer.print("1 0 obj\n<< /Length {d} >>\nstream\n", .{content.len});
    try writer.writeAll(content);
    try writer.writeAll("\nendstream\nendobj\n");

    // Page (obj 2)
    try writer.writeAll("2 0 obj\n<< /Type /Page /MediaBox [0 0 612 792] /Contents 1 0 R /Parent 3 0 R >>\nendobj\n");

    // Pages (obj 3)
    try writer.writeAll("3 0 obj\n<< /Type /Pages /Kids [2 0 R] /Count 1 >>\nendobj\n");

    // Catalog (obj 4)
    try writer.writeAll("4 0 obj\n<< /Type /Catalog /Pages 3 0 R >>\nendobj\n");

    // xref + trailer (simplified)
    const xref_offset = buf.items.len;
    try writer.writeAll("xref\n0 5\n");
    try writer.writeAll("0000000000 65535 f \n");
    try writer.writeAll("0000000009 00000 n \n");
    try writer.writeAll("0000000009 00000 n \n");
    try writer.writeAll("0000000009 00000 n \n");
    try writer.writeAll("0000000009 00000 n \n");
    try writer.writeAll("trailer\n<< /Size 5 /Root 4 0 R >>\n");
    try writer.print("startxref\n{d}\n%%EOF\n", .{xref_offset});

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "splitter: splitByPage with content" {
    const allocator = std.testing.allocator;
    const pdf = "/Type /Page content1 endobj /Type /Page content2 endobj";
    const pages = try splitByPage(allocator, pdf);
    defer {
        for (pages) |p| allocator.free(p);
        allocator.free(pages);
    }

    try std.testing.expectEqual(@as(usize, 2), pages.len);
    for (pages) |p| {
        try std.testing.expect(std.mem.startsWith(u8, p, "%PDF-1.7"));
    }
}

test "splitter: splitByPage empty" {
    const allocator = std.testing.allocator;
    const result = splitByPage(allocator, "");
    try std.testing.expectError(SplitError.InvalidPdf, result);
}

test "splitter: splitByPage no markers" {
    const allocator = std.testing.allocator;
    const pages = try splitByPage(allocator, "some pdf content");
    defer {
        for (pages) |p| allocator.free(p);
        allocator.free(pages);
    }

    try std.testing.expectEqual(@as(usize, 1), pages.len);
}

test "splitter: splitByRanges" {
    const allocator = std.testing.allocator;
    const pdf = "/Type /Page page1 endobj /Type /Page page2 endobj /Type /Page page3 endobj";
    const ranges = [_][2]usize{ .{ 0, 0 }, .{ 1, 2 } };
    const result = try splitByRanges(allocator, pdf, &ranges);
    defer {
        for (result) |r| allocator.free(r);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 2), result.len);
}

test "splitter: splitByRanges invalid" {
    const allocator = std.testing.allocator;
    const result = splitByRanges(allocator, "", &[_][2]usize{.{ 0, 0 }});
    try std.testing.expectError(SplitError.InvalidPdf, result);
}
