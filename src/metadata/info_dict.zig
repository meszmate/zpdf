const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;

/// Document metadata for the /Info dictionary.
pub const DocumentInfo = struct {
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    subject: ?[]const u8 = null,
    keywords: ?[]const u8 = null,
    creator: ?[]const u8 = null,
    producer: ?[]const u8 = null,
    creation_date: ?[]const u8 = null,
    mod_date: ?[]const u8 = null,
};

/// Build a PDF /Info dictionary from a DocumentInfo struct.
pub fn buildInfoDict(allocator: Allocator, info: DocumentInfo) !PdfObject {
    var dict = types.pdfDict(allocator);
    errdefer dict.deinit(allocator);

    if (info.title) |v| try dict.dict_obj.put(allocator, "Title", types.pdfString(v));
    if (info.author) |v| try dict.dict_obj.put(allocator, "Author", types.pdfString(v));
    if (info.subject) |v| try dict.dict_obj.put(allocator, "Subject", types.pdfString(v));
    if (info.keywords) |v| try dict.dict_obj.put(allocator, "Keywords", types.pdfString(v));
    if (info.creator) |v| try dict.dict_obj.put(allocator, "Creator", types.pdfString(v));
    if (info.producer) |v| try dict.dict_obj.put(allocator, "Producer", types.pdfString(v));
    if (info.creation_date) |v| try dict.dict_obj.put(allocator, "CreationDate", types.pdfString(v));
    if (info.mod_date) |v| try dict.dict_obj.put(allocator, "ModDate", types.pdfString(v));

    return dict;
}

// -- Tests --

test "info dict: empty" {
    const allocator = std.testing.allocator;
    var dict = try buildInfoDict(allocator, .{});
    defer dict.deinit(allocator);

    try std.testing.expect(dict.isDict());
    try std.testing.expectEqual(@as(usize, 0), dict.dict_obj.count());
}

test "info dict: all fields" {
    const allocator = std.testing.allocator;
    var dict = try buildInfoDict(allocator, .{
        .title = "Test PDF",
        .author = "John Doe",
        .subject = "Testing",
        .keywords = "pdf, test",
        .creator = "zpdf",
        .producer = "zpdf library",
        .creation_date = "D:20240101120000+00'00'",
        .mod_date = "D:20240101120000+00'00'",
    });
    defer dict.deinit(allocator);

    try std.testing.expect(dict.isDict());
    try std.testing.expectEqual(@as(usize, 8), dict.dict_obj.count());

    const title = dict.dict_obj.get("Title");
    try std.testing.expect(title != null);
    try std.testing.expectEqualStrings("Test PDF", title.?.asString().?);
}

test "info dict: partial fields" {
    const allocator = std.testing.allocator;
    var dict = try buildInfoDict(allocator, .{
        .title = "My Document",
        .author = "Author",
    });
    defer dict.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), dict.dict_obj.count());
}
