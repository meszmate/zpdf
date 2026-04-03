const std = @import("std");
const zpdf = @import("zpdf");

test "diff: identical generated pdfs" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Test");
    const page = try doc.addPage(.a4);
    try page.drawText("Hello", .{ .x = 72, .y = 750, .font = .helvetica, .font_size = 12 });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    var parsed_a = try zpdf.parsePdf(allocator, bytes);
    defer parsed_a.deinit();

    var parsed_b = try zpdf.parsePdf(allocator, bytes);
    defer parsed_b.deinit();

    var result = try zpdf.diffPdfs(allocator, &parsed_a, &parsed_b);
    defer result.deinit();

    try std.testing.expect(result.isIdentical());
}

test "diff: different page sizes" {
    const allocator = std.testing.allocator;

    var doc_a = zpdf.Document.init(allocator);
    defer doc_a.deinit();
    _ = try doc_a.addPage(.a4);
    const bytes_a = try doc_a.save(allocator);
    defer allocator.free(bytes_a);

    var doc_b = zpdf.Document.init(allocator);
    defer doc_b.deinit();
    _ = try doc_b.addPage(.letter);
    const bytes_b = try doc_b.save(allocator);
    defer allocator.free(bytes_b);

    var parsed_a = try zpdf.parsePdf(allocator, bytes_a);
    defer parsed_a.deinit();

    var parsed_b = try zpdf.parsePdf(allocator, bytes_b);
    defer parsed_b.deinit();

    var result = try zpdf.diffPdfs(allocator, &parsed_a, &parsed_b);
    defer result.deinit();

    try std.testing.expect(!result.isIdentical());
    try std.testing.expectEqual(@as(usize, 1), result.page_diffs.len);
}

test "diff: added page detected" {
    const allocator = std.testing.allocator;

    var doc_a = zpdf.Document.init(allocator);
    defer doc_a.deinit();
    _ = try doc_a.addPage(.a4);
    const bytes_a = try doc_a.save(allocator);
    defer allocator.free(bytes_a);

    var doc_b = zpdf.Document.init(allocator);
    defer doc_b.deinit();
    _ = try doc_b.addPage(.a4);
    _ = try doc_b.addPage(.a4);
    const bytes_b = try doc_b.save(allocator);
    defer allocator.free(bytes_b);

    var parsed_a = try zpdf.parsePdf(allocator, bytes_a);
    defer parsed_a.deinit();

    var parsed_b = try zpdf.parsePdf(allocator, bytes_b);
    defer parsed_b.deinit();

    var result = try zpdf.diffPdfs(allocator, &parsed_a, &parsed_b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.page_count_a);
    try std.testing.expectEqual(@as(usize, 2), result.page_count_b);
    try std.testing.expectEqual(@as(usize, 2), result.page_diffs.len);
    try std.testing.expectEqual(zpdf.DiffType.added, result.page_diffs[1].diff_type);
}

test "diff: metadata change detected" {
    const allocator = std.testing.allocator;
    const ParsedDocument = zpdf.parser.pdf_parser.ParsedDocument;
    const ParsedPage = zpdf.parser.pdf_parser.ParsedPage;
    const DocumentInfo = zpdf.DocumentInfo;

    // Construct documents directly to control metadata
    var pages_a = std.ArrayListUnmanaged(ParsedPage){};
    defer pages_a.deinit(allocator);
    try pages_a.append(allocator, .{ .width = 612, .height = 792, .content_data = "" });

    var pages_b = std.ArrayListUnmanaged(ParsedPage){};
    defer pages_b.deinit(allocator);
    try pages_b.append(allocator, .{ .width = 612, .height = 792, .content_data = "" });

    var parsed_a = ParsedDocument{
        .allocator = allocator,
        .info = DocumentInfo{ .title = "Title A" },
        .pages = pages_a,
        .form_fields = null,
        .version = "1.4",
    };

    var parsed_b = ParsedDocument{
        .allocator = allocator,
        .info = DocumentInfo{ .title = "Title B" },
        .pages = pages_b,
        .form_fields = null,
        .version = "1.4",
    };

    var result = try zpdf.diffPdfs(allocator, &parsed_a, &parsed_b);
    defer result.deinit();

    try std.testing.expect(!result.isIdentical());
    // Verify title field is marked as changed
    var found = false;
    for (result.metadata_diffs) |md| {
        if (std.mem.eql(u8, md.field, "title") and md.diff_type == .changed) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "diff: result struct fields" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(.a4);
    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    var parsed_a = try zpdf.parsePdf(allocator, bytes);
    defer parsed_a.deinit();
    var parsed_b = try zpdf.parsePdf(allocator, bytes);
    defer parsed_b.deinit();

    var result = try zpdf.diffPdfs(allocator, &parsed_a, &parsed_b);
    defer result.deinit();

    try std.testing.expect(result.page_diffs.len > 0);
    try std.testing.expect(result.metadata_diffs.len > 0);
    try std.testing.expect(result.text_diffs.len > 0);
}
