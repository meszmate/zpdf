const std = @import("std");
const zpdf = @import("zpdf");

test "validator: validate generated pdf" {
    const allocator = std.testing.allocator;

    // Create a PDF with known content
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Test Document");
    const page = try doc.addPage(.a4);
    try page.drawText("Hello World", .{ .x = 72, .y = 720, .font = .helvetica, .font_size = 12 });

    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    var result = try zpdf.validatePdf(allocator, pdf_bytes, .{});
    defer result.deinit();

    // A properly generated PDF should have no errors
    var error_count: usize = 0;
    for (result.issues) |issue| {
        if (issue.severity == .error_) error_count += 1;
    }
    try std.testing.expect(error_count == 0);
}

test "validator: reject empty data" {
    const allocator = std.testing.allocator;

    var result = try zpdf.validatePdf(allocator, "", .{});
    defer result.deinit();

    try std.testing.expect(!result.is_valid);
    try std.testing.expect(result.issues.len > 0);
}

test "validator: reject garbage data" {
    const allocator = std.testing.allocator;

    var result = try zpdf.validatePdf(allocator, "this is definitely not a valid pdf file content at all", .{});
    defer result.deinit();

    try std.testing.expect(!result.is_valid);
}

test "validator: detect missing eof" {
    const allocator = std.testing.allocator;

    const pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
    ;
    var result = try zpdf.validatePdf(allocator, pdf, .{});
    defer result.deinit();

    var found = false;
    for (result.issues) |issue| {
        if (issue.code == .missing_eof_marker) found = true;
    }
    try std.testing.expect(found);
}

test "validator: options struct defaults" {
    const opts = zpdf.ValidationOptions{};
    try std.testing.expect(opts.check_xref);
    try std.testing.expect(opts.check_streams);
    try std.testing.expect(opts.check_required_keys);
    try std.testing.expect(!opts.strict);
}

test "validator: issue code enum completeness" {
    // Verify all issue codes are distinct
    const codes = [_]zpdf.IssueCode{
        .invalid_header,
        .missing_binary_comment,
        .missing_eof_marker,
        .invalid_startxref,
        .missing_xref,
        .xref_entry_count_mismatch,
        .xref_offset_invalid,
        .missing_trailer,
        .trailer_missing_size,
        .trailer_missing_root,
        .catalog_missing_type,
        .catalog_missing_pages,
        .pages_missing_type,
        .pages_missing_kids,
        .pages_missing_count,
        .page_missing_type,
        .page_missing_mediabox,
        .page_missing_parent,
        .stream_length_mismatch,
        .object_not_delimited,
        .duplicate_object_number,
        .xref_inconsistent,
    };
    // Just verify they can all be used
    try std.testing.expect(codes.len == 22);
}

test "validator: severity levels" {
    try std.testing.expect(@intFromEnum(zpdf.Severity.error_) != @intFromEnum(zpdf.Severity.warning));
    try std.testing.expect(@intFromEnum(zpdf.Severity.warning) != @intFromEnum(zpdf.Severity.info));
}

test "validator: validation result deinit" {
    const allocator = std.testing.allocator;

    var result = try zpdf.validatePdf(allocator, "%PDF-1.4\n%%EOF", .{});
    // Ensure deinit does not leak
    result.deinit();
}
