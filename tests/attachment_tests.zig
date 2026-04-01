const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const Document = zpdf.Document;
const Attachment = zpdf.Attachment;
const AttachmentBuilder = zpdf.AttachmentBuilder;

test "add attachment to document" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addAttachment(.{
        .name = "test.txt",
        .data = "Hello, World!",
        .mime_type = "text/plain",
        .description = "A test file",
    });

    try testing.expect(doc.attachment_builder != null);
    try testing.expectEqual(@as(usize, 1), doc.attachment_builder.?.attachments.items.len);
}

test "add multiple attachments" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addAttachment(.{ .name = "file1.txt", .data = "content1" });
    try doc.addAttachment(.{ .name = "file2.csv", .data = "a,b\n1,2\n", .mime_type = "text/csv" });

    try testing.expectEqual(@as(usize, 2), doc.attachment_builder.?.attachments.items.len);
}

test "attachment builder standalone" {
    var builder = AttachmentBuilder.init(testing.allocator);
    defer builder.deinit();

    try builder.addFile("simple.txt", "data");
    try builder.addAttachment(.{
        .name = "full.pdf",
        .data = "fake pdf data",
        .mime_type = "application/pdf",
        .description = "Embedded PDF",
        .creation_date = "D:20260101000000",
        .mod_date = "D:20260301000000",
    });

    try testing.expectEqual(@as(usize, 2), builder.attachments.items.len);
    try testing.expectEqualStrings("simple.txt", builder.attachments.items[0].name);
    try testing.expect(builder.attachments.items[0].mime_type == null);
    try testing.expectEqualStrings("application/pdf", builder.attachments.items[1].mime_type.?);
}

test "attachment builder builds objects in store" {
    var store = zpdf.ObjectStore.init(testing.allocator);
    defer store.deinit();

    var builder = AttachmentBuilder.init(testing.allocator);
    defer builder.deinit();

    try builder.addFile("readme.txt", "Read me!");
    const names_ref = try builder.build(&store);

    // Should have: 1 stream + 1 filespec + 1 names dict = 3 objects
    try testing.expectEqual(@as(usize, 3), store.count());

    // The names dict should exist
    const names_obj = store.get(names_ref);
    try testing.expect(names_obj != null);
}

test "PDF output contains embedded file markers" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);

    try doc.addAttachment(.{
        .name = "notes.txt",
        .data = "Some attached notes",
        .mime_type = "text/plain",
        .description = "Meeting notes",
    });

    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    // The output should contain key PDF attachment structures
    try testing.expect(std.mem.indexOf(u8, pdf, "/EmbeddedFiles") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "/Filespec") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "/EmbeddedFile") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "notes.txt") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "Some attached notes") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "Meeting notes") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "/Names") != null);
}

test "PDF with attachment has valid structure" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    try doc.addAttachment(.{ .name = "data.bin", .data = "binary content here" });

    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    // Basic PDF structure checks
    try testing.expect(std.mem.startsWith(u8, pdf, "%PDF-1.7"));
    try testing.expect(std.mem.indexOf(u8, pdf, "%%EOF") != null);
    try testing.expect(std.mem.indexOf(u8, pdf, "/Catalog") != null);
}

test "document without attachments has no Names" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);

    const pdf = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf);

    // Should not have /EmbeddedFiles if no attachments
    try testing.expect(std.mem.indexOf(u8, pdf, "/EmbeddedFiles") == null);
}
