const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// Represents a file to be embedded in the PDF document.
pub const Attachment = struct {
    name: []const u8,
    data: []const u8,
    mime_type: ?[]const u8 = null,
    description: ?[]const u8 = null,
    creation_date: ?[]const u8 = null,
    mod_date: ?[]const u8 = null,
};

/// Builds PDF embedded file attachment objects.
///
/// Attachments are stored in the catalog's /Names /EmbeddedFiles name tree.
/// Each attachment produces a file specification dictionary and an embedded
/// file stream object in the PDF.
pub const AttachmentBuilder = struct {
    allocator: Allocator,
    attachments: ArrayList(Attachment),

    pub fn init(allocator: Allocator) AttachmentBuilder {
        return .{
            .allocator = allocator,
            .attachments = .{},
        };
    }

    pub fn deinit(self: *AttachmentBuilder) void {
        self.attachments.deinit(self.allocator);
    }

    /// Add an attachment with full options.
    pub fn addAttachment(self: *AttachmentBuilder, attachment: Attachment) !void {
        try self.attachments.append(self.allocator, attachment);
    }

    /// Convenience: add a file by name and data with no extra metadata.
    pub fn addFile(self: *AttachmentBuilder, name: []const u8, data: []const u8) !void {
        try self.attachments.append(self.allocator, .{
            .name = name,
            .data = data,
        });
    }

    /// Build all attachment objects into the object store.
    /// Returns a ref to the Names dictionary containing /EmbeddedFiles.
    pub fn build(self: *AttachmentBuilder, store: *ObjectStore) !Ref {
        const allocator = self.allocator;

        // Build the name tree array: [(name1) filespec_ref1 (name2) filespec_ref2 ...]
        var names_array = types.pdfArray(allocator);

        for (self.attachments.items) |att| {
            // 1. Create the embedded file stream object
            const stream_ref = try store.allocate();
            {
                var stream_dict: std.StringHashMapUnmanaged(types.PdfObject) = .{};
                try stream_dict.put(allocator, "Type", types.pdfName("EmbeddedFile"));
                if (att.mime_type) |mime| {
                    try stream_dict.put(allocator, "Subtype", types.pdfName(mime));
                }
                try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(att.data.len)));

                // /Params dict with /Size
                var params_dict = types.pdfDict(allocator);
                try params_dict.dict_obj.put(allocator, "Size", types.pdfInt(@intCast(att.data.len)));
                if (att.creation_date) |cd| {
                    try params_dict.dict_obj.put(allocator, "CreationDate", types.pdfString(cd));
                }
                if (att.mod_date) |md| {
                    try params_dict.dict_obj.put(allocator, "ModDate", types.pdfString(md));
                }
                try stream_dict.put(allocator, "Params", params_dict);

                store.put(stream_ref, .{ .stream_obj = .{
                    .dict = stream_dict,
                    .data = att.data,
                } });
            }

            // 2. Create the file specification dictionary
            const filespec_ref = try store.allocate();
            {
                var filespec_dict = types.pdfDict(allocator);
                try filespec_dict.dict_obj.put(allocator, "Type", types.pdfName("Filespec"));
                try filespec_dict.dict_obj.put(allocator, "F", types.pdfString(att.name));
                try filespec_dict.dict_obj.put(allocator, "UF", types.pdfString(att.name));

                // /EF dict pointing to stream
                var ef_dict = types.pdfDict(allocator);
                try ef_dict.dict_obj.put(allocator, "F", types.pdfRef(stream_ref.obj_num, stream_ref.gen_num));
                try filespec_dict.dict_obj.put(allocator, "EF", ef_dict);

                if (att.description) |desc| {
                    try filespec_dict.dict_obj.put(allocator, "Desc", types.pdfString(desc));
                }

                store.put(filespec_ref, filespec_dict);
            }

            // 3. Add to name tree array: (filename) ref
            try names_array.array_obj.append(types.pdfString(att.name));
            try names_array.array_obj.append(types.pdfRef(filespec_ref.obj_num, filespec_ref.gen_num));
        }

        // Build the EmbeddedFiles name tree dict
        var ef_names_dict = types.pdfDict(allocator);
        try ef_names_dict.dict_obj.put(allocator, "Names", names_array);

        // Build the Names dict containing /EmbeddedFiles
        const names_ref = try store.allocate();
        var names_dict = types.pdfDict(allocator);
        try names_dict.dict_obj.put(allocator, "EmbeddedFiles", ef_names_dict);
        store.put(names_ref, names_dict);

        return names_ref;
    }
};

// -- Tests --

test "AttachmentBuilder init and deinit" {
    var builder = AttachmentBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try std.testing.expectEqual(@as(usize, 0), builder.attachments.items.len);
}

test "addFile adds attachment" {
    var builder = AttachmentBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addFile("test.txt", "hello world");
    try std.testing.expectEqual(@as(usize, 1), builder.attachments.items.len);
    try std.testing.expectEqualStrings("test.txt", builder.attachments.items[0].name);
    try std.testing.expectEqualStrings("hello world", builder.attachments.items[0].data);
    try std.testing.expect(builder.attachments.items[0].mime_type == null);
}

test "addAttachment with full metadata" {
    var builder = AttachmentBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addAttachment(.{
        .name = "report.csv",
        .data = "a,b,c\n1,2,3\n",
        .mime_type = "text/csv",
        .description = "Sales report",
        .creation_date = "D:20260101120000",
        .mod_date = "D:20260301120000",
    });

    try std.testing.expectEqual(@as(usize, 1), builder.attachments.items.len);
    try std.testing.expectEqualStrings("text/csv", builder.attachments.items[0].mime_type.?);
    try std.testing.expectEqualStrings("Sales report", builder.attachments.items[0].description.?);
}

test "build creates objects in store" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var builder = AttachmentBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addFile("test.txt", "hello");
    try builder.addAttachment(.{
        .name = "data.csv",
        .data = "x,y\n1,2\n",
        .mime_type = "text/csv",
        .description = "Test CSV",
    });

    const names_ref = try builder.build(&store);

    // Verify the names dict was created
    const names_obj = store.get(names_ref);
    try std.testing.expect(names_obj != null);

    // 2 attachments = 2 stream objects + 2 filespec objects + 1 names dict = 5 objects
    try std.testing.expectEqual(@as(usize, 5), store.count());
}
