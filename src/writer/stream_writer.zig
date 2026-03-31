const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const StringHashMap = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;
const object_serializer = @import("object_serializer.zig");
const xref_writer = @import("xref_writer.zig");
const XrefEntry = xref_writer.XrefEntry;
const Document = @import("../document/document.zig").Document;
const Page = @import("../document/page.zig").Page;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// A counting writer that wraps a GenericWriter and tracks total bytes written.
/// This works with writers returned by ArrayList.writer(), fixedBufferStream.writer(), etc.
pub fn CountingWriter(comptime WriterType: type) type {
    return struct {
        inner: WriterType,
        bytes_written: u64 = 0,

        const Self = @This();

        pub const Error = WriterType.Error;
        pub const Writer = std.io.GenericWriter(*Self, WriterType.Error, appendWrite);

        fn appendWrite(self: *Self, bytes: []const u8) WriterType.Error!usize {
            const n = try self.inner.write(bytes);
            self.bytes_written += n;
            return n;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

/// Wraps a GenericWriter to count the total number of bytes written through it.
pub fn countingWriter(inner: anytype) CountingWriter(@TypeOf(inner)) {
    return .{ .inner = inner };
}

/// Stream a PDF document directly to any writer that supports `writeAll`.
///
/// This replicates the logic of `PdfWriter.writePdf()` but writes bytes
/// directly to the provided writer instead of accumulating them in memory.
/// Object metadata is still built in a temporary `ObjectStore` (which is small),
/// but the serialized PDF bytes are streamed out immediately.
///
/// The writer can be any type that has a `writeAll([]const u8) !void` method,
/// such as `std.ArrayList(u8).writer()`, `std.io.fixedBufferStream().writer()`,
/// or a `CountingWriter(...).writer()`.
pub fn streamPdf(allocator: Allocator, doc: *Document, wr: anytype) !void {
    // Track total bytes written so we can record xref offsets.
    var bytes_written: u64 = 0;

    // Helper: write bytes to the writer and track the count.
    const Helper = struct {
        fn flush(w: @TypeOf(wr), buf: *ByteBuffer, counter: *u64) !void {
            const data = buf.items();
            try w.writeAll(data);
            counter.* += @intCast(data.len);
            buf.list.clearRetainingCapacity();
        }
    };

    // Temp buffer for serializing individual objects / sections.
    var tmp_buf = ByteBuffer.init(allocator);
    defer tmp_buf.deinit();

    // -- Write PDF header --
    try tmp_buf.write("%PDF-1.7\n");
    try tmp_buf.write("%\xe2\xe3\xcf\xd3\n");
    try Helper.flush(wr, &tmp_buf, &bytes_written);

    // Build all objects into a local store (same as PdfWriter).
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    var offsets: ArrayList(u64) = .{};
    defer offsets.deinit(allocator);

    // Object 0 is the free head entry.
    try offsets.append(allocator, 0);

    // -- Build Info dictionary --
    var info_ref: ?Ref = null;
    if (doc.title != null or doc.author != null or doc.subject != null or
        doc.keywords != null or doc.creator != null or doc.producer != null)
    {
        const ref = try store.allocate();
        info_ref = ref;

        var dict = types.pdfDict(allocator);
        if (doc.title) |t| try dict.dict_obj.put(allocator, "Title", types.pdfString(t));
        if (doc.author) |a| try dict.dict_obj.put(allocator, "Author", types.pdfString(a));
        if (doc.subject) |s| try dict.dict_obj.put(allocator, "Subject", types.pdfString(s));
        if (doc.keywords) |k| try dict.dict_obj.put(allocator, "Keywords", types.pdfString(k));
        if (doc.creator) |c| try dict.dict_obj.put(allocator, "Creator", types.pdfString(c));
        if (doc.producer) |p| try dict.dict_obj.put(allocator, "Producer", types.pdfString(p));

        store.put(ref, dict);
    }

    // -- Build font objects --
    var font_name_to_ref: StringHashMap(Ref) = .{};
    defer font_name_to_ref.deinit(allocator);

    var font_iter = doc.font_refs.iterator();
    while (font_iter.next()) |entry| {
        const pdf_name = entry.key_ptr.*;
        const ref = try store.allocate();
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("Font"));
        try dict.dict_obj.put(allocator, "Subtype", types.pdfName("Type1"));
        try dict.dict_obj.put(allocator, "BaseFont", types.pdfName(pdf_name));
        store.put(ref, dict);
        try font_name_to_ref.put(allocator, pdf_name, ref);
    }

    // -- Build page objects --
    var page_refs: ArrayList(Ref) = .{};
    defer page_refs.deinit(allocator);

    for (doc.pages.items) |page| {
        const page_ref = try store.allocate();
        try page_refs.append(allocator, page_ref);

        const content_ref = try store.allocate();
        const content_data = page.content.items;

        var stream_dict: StringHashMap(PdfObject) = .{};
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(content_data.len)));

        store.put(content_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = content_data,
        } });

        var font_dict = types.pdfDict(allocator);
        var page_font_iter = page.resources.fonts.iterator();
        while (page_font_iter.next()) |fentry| {
            const font_pdf_name = fentry.key_ptr.*;
            const res_name = fentry.value_ptr.name;
            if (font_name_to_ref.get(font_pdf_name)) |fref| {
                try font_dict.dict_obj.put(allocator, res_name, types.pdfRef(fref.obj_num, fref.gen_num));
            }
        }

        var resources_dict = types.pdfDict(allocator);
        if (font_dict.dict_obj.count() > 0) {
            try resources_dict.dict_obj.put(allocator, "Font", font_dict);
        } else {
            font_dict.deinit(allocator);
        }

        var page_dict = types.pdfDict(allocator);
        try page_dict.dict_obj.put(allocator, "Type", types.pdfName("Page"));

        var media_box = types.pdfArray(allocator);
        try media_box.array_obj.append(types.pdfInt(0));
        try media_box.array_obj.append(types.pdfInt(0));
        try media_box.array_obj.append(types.pdfReal(@floatCast(page.width)));
        try media_box.array_obj.append(types.pdfReal(@floatCast(page.height)));
        try page_dict.dict_obj.put(allocator, "MediaBox", media_box);

        try page_dict.dict_obj.put(allocator, "Contents", types.pdfRef(content_ref.obj_num, content_ref.gen_num));
        try page_dict.dict_obj.put(allocator, "Resources", resources_dict);

        if (page.rotation != 0) {
            try page_dict.dict_obj.put(allocator, "Rotate", types.pdfInt(@intCast(page.rotation)));
        }

        store.put(page_ref, page_dict);
    }

    // -- Build Pages dictionary --
    const pages_ref = try store.allocate();
    {
        var kids_array = types.pdfArray(allocator);
        for (page_refs.items) |pref| {
            try kids_array.array_obj.append(types.pdfRef(pref.obj_num, pref.gen_num));
        }

        var pages_dict = types.pdfDict(allocator);
        try pages_dict.dict_obj.put(allocator, "Type", types.pdfName("Pages"));
        try pages_dict.dict_obj.put(allocator, "Kids", kids_array);
        try pages_dict.dict_obj.put(allocator, "Count", types.pdfInt(@intCast(page_refs.items.len)));
        store.put(pages_ref, pages_dict);
    }

    // Set Parent on each page dict
    for (page_refs.items) |pref| {
        for (store.objects.items) |*sentry| {
            if (sentry.ref.eql(pref)) {
                if (sentry.object) |*o| {
                    if (o.* == .dict_obj) {
                        try o.dict_obj.put(allocator, "Parent", types.pdfRef(pages_ref.obj_num, pages_ref.gen_num));
                    }
                }
                break;
            }
        }
    }

    // -- Build Catalog --
    const catalog_ref = try store.allocate();
    {
        var catalog_dict = types.pdfDict(allocator);
        try catalog_dict.dict_obj.put(allocator, "Type", types.pdfName("Catalog"));
        try catalog_dict.dict_obj.put(allocator, "Pages", types.pdfRef(pages_ref.obj_num, pages_ref.gen_num));
        store.put(catalog_ref, catalog_dict);
    }

    // -- Write all objects, recording byte offsets --
    for (store.objects.items) |obj_entry| {
        const offset: u64 = bytes_written;
        try offsets.append(allocator, offset);

        try tmp_buf.writeFmt("{d} {d} obj\n", .{ obj_entry.ref.obj_num, obj_entry.ref.gen_num });
        if (obj_entry.object) |obj| {
            try object_serializer.writeObject(&tmp_buf, obj);
        } else {
            try tmp_buf.write("null");
        }
        try tmp_buf.write("\nendobj\n");

        try Helper.flush(wr, &tmp_buf, &bytes_written);
    }

    // -- Write xref table --
    var xref_entries: ArrayList(XrefEntry) = .{};
    defer xref_entries.deinit(allocator);

    try xref_entries.append(allocator, .{ .offset = 0, .gen = 65535, .in_use = false });

    for (offsets.items[1..]) |off| {
        try xref_entries.append(allocator, .{ .offset = off, .gen = 0, .in_use = true });
    }

    // The xref offset is the current byte position in the stream.
    const xref_offset = bytes_written;
    _ = try xref_writer.writeXref(&tmp_buf, xref_entries.items);
    try Helper.flush(wr, &tmp_buf, &bytes_written);

    // -- Write trailer --
    try xref_writer.writeTrailer(&tmp_buf, xref_entries.items.len, catalog_ref, info_ref);
    try Helper.flush(wr, &tmp_buf, &bytes_written);

    // -- Write startxref --
    try tmp_buf.writeFmt("startxref\n{d}\n", .{xref_offset});
    try tmp_buf.write("%%EOF\n");
    try Helper.flush(wr, &tmp_buf, &bytes_written);
}
