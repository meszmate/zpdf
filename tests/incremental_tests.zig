const std = @import("std");
const testing = std.testing;
const zpdf = @import("zpdf");

const IncrementalUpdate = zpdf.IncrementalUpdate;
const MetadataUpdate = zpdf.MetadataUpdate;
const findStartxrefOffset = zpdf.modify.incremental.findStartxrefOffset;
const findMaxObjectNumber = zpdf.modify.incremental.findMaxObjectNumber;
const parseTrailerRefs = zpdf.modify.incremental.parseTrailerRefs;
const updateMetadataIncremental = zpdf.modify.incremental.updateMetadataIncremental;

const Document = zpdf.Document;

/// Helper: create a minimal valid PDF using the Document API.
fn createMinimalPdf(allocator: std.mem.Allocator) ![]u8 {
    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Test Document");
    const page = try doc.addPage(.a4);

    const font_handle = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(font_handle.font.pdfName(), font_handle.ref);

    try page.drawText("Hello, World!", .{
        .x = 72,
        .y = 720,
        .font = .helvetica,
        .font_size = 12,
    });

    return doc.save(allocator);
}

test "findStartxrefOffset in a generated PDF" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    const offset = try findStartxrefOffset(pdf);
    // The offset should point to somewhere within the PDF
    try testing.expect(offset > 0);
    try testing.expect(offset < pdf.len);

    // At that offset, we should find "xref"
    const at_offset = pdf[@intCast(offset)..];
    try testing.expect(std.mem.startsWith(u8, at_offset, "xref"));
}

test "findMaxObjectNumber in a generated PDF" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    const max = findMaxObjectNumber(pdf);
    // A simple PDF should have at least a few objects (catalog, page tree, page, font, etc.)
    try testing.expect(max >= 3);
}

test "parseTrailerRefs from a generated PDF" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    const info = try parseTrailerRefs(pdf);
    try testing.expect(info.root_ref.obj_num > 0);
    try testing.expect(info.size > 0);
}

test "add a new object incrementally" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    var update = try IncrementalUpdate.init(allocator, pdf);
    defer update.deinit();

    // Add a simple dictionary object
    const ref = try update.addObject(zpdf.core.types.pdfDict(allocator));
    try testing.expect(ref.obj_num > 0);

    const result = try update.apply();
    defer allocator.free(result);

    // Result should start with the original PDF header
    try testing.expect(std.mem.startsWith(u8, result, "%PDF-"));
    // Result should end with %%EOF
    try testing.expect(std.mem.endsWith(u8, result, "%%EOF\n"));
    // Result should be longer than the original
    try testing.expect(result.len > pdf.len);
    // Original bytes should be preserved as a prefix
    try testing.expect(std.mem.startsWith(u8, result, pdf));
}

test "update metadata incrementally" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    const result = try updateMetadataIncremental(allocator, pdf, .{
        .title = "Updated Title",
        .author = "Test Author",
    });
    defer allocator.free(result);

    // Basic validity checks
    try testing.expect(std.mem.startsWith(u8, result, "%PDF-"));
    try testing.expect(std.mem.endsWith(u8, result, "%%EOF\n"));

    // Original bytes preserved
    try testing.expect(std.mem.startsWith(u8, result, pdf));

    // Should contain the new metadata
    try testing.expect(std.mem.indexOf(u8, result, "Updated Title") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Test Author") != null);

    // Should have a /Prev entry in the new trailer (incremental marker)
    // Find the LAST trailer
    const last_trailer_pos = std.mem.lastIndexOf(u8, result, "trailer") orelse unreachable;
    const last_trailer = result[last_trailer_pos..];
    try testing.expect(std.mem.indexOf(u8, last_trailer, "/Prev") != null);
    try testing.expect(std.mem.indexOf(u8, last_trailer, "/Info") != null);
}

test "result is still a valid PDF structure" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    var update = try IncrementalUpdate.init(allocator, pdf);
    defer update.deinit();

    _ = try update.addObject(zpdf.core.types.pdfInt(42));

    const result = try update.apply();
    defer allocator.free(result);

    // Starts with %PDF
    try testing.expect(std.mem.startsWith(u8, result, "%PDF-"));
    // Ends with %%EOF
    try testing.expect(std.mem.endsWith(u8, result, "%%EOF\n"));
    // Has xref section
    try testing.expect(std.mem.indexOf(u8, result, "xref\n") != null);
    // Has trailer
    try testing.expect(std.mem.indexOf(u8, result, "trailer\n") != null);
    // Has startxref
    try testing.expect(std.mem.indexOf(u8, result, "startxref\n") != null);
    // Has /Root
    try testing.expect(std.mem.indexOf(u8, result, "/Root") != null);
    // Has /Size
    try testing.expect(std.mem.indexOf(u8, result, "/Size") != null);
}

test "original bytes are preserved (prefix match)" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    var update = try IncrementalUpdate.init(allocator, pdf);
    defer update.deinit();

    _ = try update.addObject(zpdf.core.types.pdfString("new content"));

    const result = try update.apply();
    defer allocator.free(result);

    // The first N bytes of the result must exactly match the original
    try testing.expectEqualSlices(u8, pdf, result[0..pdf.len]);
}

test "multiple incremental updates" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    // First incremental update
    const updated1 = try updateMetadataIncremental(allocator, pdf, .{
        .title = "First Update",
    });
    defer allocator.free(updated1);

    // Second incremental update on top of the first
    const updated2 = try updateMetadataIncremental(allocator, updated1, .{
        .author = "Second Update Author",
    });
    defer allocator.free(updated2);

    // Basic validity
    try testing.expect(std.mem.startsWith(u8, updated2, "%PDF-"));
    try testing.expect(std.mem.endsWith(u8, updated2, "%%EOF\n"));

    // Both updates' content should be present
    try testing.expect(std.mem.indexOf(u8, updated2, "First Update") != null);
    try testing.expect(std.mem.indexOf(u8, updated2, "Second Update Author") != null);

    // The first update's bytes should be preserved in the second
    try testing.expect(std.mem.startsWith(u8, updated2, updated1));

    // Should be larger than both previous versions
    try testing.expect(updated2.len > updated1.len);
    try testing.expect(updated1.len > pdf.len);
}

test "no modifications returns copy of original" {
    const allocator = testing.allocator;
    const pdf = try createMinimalPdf(allocator);
    defer allocator.free(pdf);

    var update = try IncrementalUpdate.init(allocator, pdf);
    defer update.deinit();

    // Don't add any modifications
    const result = try update.apply();
    defer allocator.free(result);

    try testing.expectEqualSlices(u8, pdf, result);
}
