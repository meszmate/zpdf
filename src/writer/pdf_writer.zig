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
const header_footer = @import("../layout/header_footer.zig");
const pdfa = @import("../pdfa/pdfa.zig");

/// PDF file serializer. Converts a Document into a complete PDF byte stream.
pub const PdfWriter = struct {
    /// Serializes a full PDF document to bytes.
    pub fn writePdf(allocator: Allocator, doc: *Document) ![]u8 {
        // Apply headers/footers before building page objects
        if (doc.header != null or doc.footer != null) {
            const page_ptrs = doc.pages.items;
            try header_footer.applyHeadersFooters(page_ptrs, doc.header, doc.footer, 1);
        }

        var buffer = ByteBuffer.init(allocator);
        defer buffer.deinit();

        // -- Write PDF header --
        if (doc.pdfa_level) |level| {
            try buffer.writeFmt("%PDF-{s}\n", .{level.pdfVersion()});
        } else {
            try buffer.write("%PDF-1.7\n");
        }
        // Binary comment to signal binary content (per PDF spec recommendation)
        try buffer.write("%\xe2\xe3\xcf\xd3\n");

        // We build all objects fresh into a local store so we control numbering.
        var store = ObjectStore.init(allocator);
        defer store.deinit();

        // Track byte offsets for each object number for the xref table.
        var offsets: ArrayList(u64) = .{};
        defer offsets.deinit(allocator);

        // Object 0 is the free head entry (not a real object).
        try offsets.append(allocator, 0);

        // -- Build Info dictionary --
        var info_ref: ?Ref = null;
        if (doc.title != null or doc.author != null or doc.subject != null or
            doc.keywords != null or doc.creator != null or doc.producer != null)
        {
            const ref = try store.allocate();
            info_ref = ref;

            var dict = types.pdfDict(allocator);
            if (doc.title) |t| try dict.dict_obj.put(allocator,"Title", types.pdfString(t));
            if (doc.author) |a| try dict.dict_obj.put(allocator,"Author", types.pdfString(a));
            if (doc.subject) |s| try dict.dict_obj.put(allocator,"Subject", types.pdfString(s));
            if (doc.keywords) |k| try dict.dict_obj.put(allocator,"Keywords", types.pdfString(k));
            if (doc.creator) |c| try dict.dict_obj.put(allocator,"Creator", types.pdfString(c));
            if (doc.producer) |p| try dict.dict_obj.put(allocator,"Producer", types.pdfString(p));

            store.put(ref, dict);
        }

        // -- Build font objects and collect refs --
        var font_name_to_ref: StringHashMap(Ref) = .{};
        defer font_name_to_ref.deinit(allocator);

        var font_iter = doc.font_refs.iterator();
        while (font_iter.next()) |entry| {
            const pdf_name = entry.key_ptr.*;
            const ref = try store.allocate();
            var dict = types.pdfDict(allocator);
            try dict.dict_obj.put(allocator,"Type", types.pdfName("Font"));
            try dict.dict_obj.put(allocator,"Subtype", types.pdfName("Type1"));
            try dict.dict_obj.put(allocator,"BaseFont", types.pdfName(pdf_name));
            store.put(ref, dict);
            try font_name_to_ref.put(allocator, pdf_name, ref);
        }

        // -- Build page objects --
        var page_refs: ArrayList(Ref) = .{};
        defer page_refs.deinit(allocator);

        for (doc.pages.items) |page| {
            const page_ref = try store.allocate();
            try page_refs.append(allocator, page_ref);

            // Build content stream object
            const content_ref = try store.allocate();
            const content_data = page.content.items;

            var stream_dict: StringHashMap(PdfObject) = .{};
            try stream_dict.put(allocator,"Length", types.pdfInt(@intCast(content_data.len)));

            store.put(content_ref, .{ .stream_obj = .{
                .dict = stream_dict,
                .data = content_data,
            } });

            // Build font resource dict for this page
            var font_dict = types.pdfDict(allocator);
            var page_font_iter = page.resources.fonts.iterator();
            while (page_font_iter.next()) |fentry| {
                const font_pdf_name = fentry.key_ptr.*;
                const res_name = fentry.value_ptr.name;
                if (font_name_to_ref.get(font_pdf_name)) |fref| {
                    try font_dict.dict_obj.put(allocator,res_name, types.pdfRef(fref.obj_num, fref.gen_num));
                }
            }

            // Build pattern resource dict for this page
            var pattern_dict = types.pdfDict(allocator);
            {
                var pat_iter = page.resources.patterns.iterator();
                while (pat_iter.next()) |pentry| {
                    const pat = pentry.value_ptr.*;
                    try pattern_dict.dict_obj.put(allocator, pat.name, types.pdfRef(pat.ref.obj_num, pat.ref.gen_num));
                }
            }

            // Build ExtGState resource dict for this page
            var gs_dict = types.pdfDict(allocator);
            {
                for (page.resources.ext_g_states.items) |gs| {
                    try gs_dict.dict_obj.put(allocator, gs.name, types.pdfRef(gs.ref.obj_num, gs.ref.gen_num));
                }
            }

            // Build resources dict
            var resources_dict = types.pdfDict(allocator);
            if (font_dict.dict_obj.count() > 0) {
                try resources_dict.dict_obj.put(allocator,"Font", font_dict);
            } else {
                font_dict.deinit(allocator);
            }
            if (pattern_dict.dict_obj.count() > 0) {
                try resources_dict.dict_obj.put(allocator, "Pattern", pattern_dict);
            } else {
                pattern_dict.deinit(allocator);
            }
            if (gs_dict.dict_obj.count() > 0) {
                try resources_dict.dict_obj.put(allocator, "ExtGState", gs_dict);
            } else {
                gs_dict.deinit(allocator);
            }

            // Build page dict (parent will be set after we know pages_ref)
            var page_dict = types.pdfDict(allocator);
            try page_dict.dict_obj.put(allocator,"Type", types.pdfName("Page"));

            var media_box = types.pdfArray(allocator);
            try media_box.array_obj.append(types.pdfInt(0));
            try media_box.array_obj.append(types.pdfInt(0));
            try media_box.array_obj.append(types.pdfReal(@floatCast(page.width)));
            try media_box.array_obj.append(types.pdfReal(@floatCast(page.height)));
            try page_dict.dict_obj.put(allocator,"MediaBox", media_box);

            try page_dict.dict_obj.put(allocator,"Contents", types.pdfRef(content_ref.obj_num, content_ref.gen_num));
            try page_dict.dict_obj.put(allocator,"Resources", resources_dict);

            if (page.rotation != 0) {
                try page_dict.dict_obj.put(allocator,"Rotate", types.pdfInt(@intCast(page.rotation)));
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
            try pages_dict.dict_obj.put(allocator,"Type", types.pdfName("Pages"));
            try pages_dict.dict_obj.put(allocator,"Kids", kids_array);
            try pages_dict.dict_obj.put(allocator,"Count", types.pdfInt(@intCast(page_refs.items.len)));
            store.put(pages_ref, pages_dict);
        }

        // Set Parent on each page dict
        for (page_refs.items) |pref| {
            for (store.objects.items) |*entry| {
                if (entry.ref.eql(pref)) {
                    if (entry.object) |*o| {
                        if (o.* == .dict_obj) {
                            try o.dict_obj.put(allocator,"Parent", types.pdfRef(pages_ref.obj_num, pages_ref.gen_num));
                        }
                    }
                    break;
                }
            }
        }

        // -- Copy AcroForm objects from document object store --
        // The FormBuilder stores field objects and the AcroForm dict in doc.object_store.
        // We need to copy them into the writer's store with remapped object numbers.
        var acroform_new_ref: ?Ref = null;
        {
            // Build a mapping from old obj_num to new Ref
            var ref_map = std.AutoHashMapUnmanaged(u32, Ref){};
            defer ref_map.deinit(allocator);

            // First pass: allocate new refs for all doc.object_store objects
            for (doc.object_store.objects.items) |entry| {
                const new_ref = try store.allocate();
                try ref_map.put(allocator, entry.ref.obj_num, new_ref);
            }

            // Second pass: copy objects, remapping internal references
            for (doc.object_store.objects.items) |entry| {
                const new_ref = ref_map.get(entry.ref.obj_num).?;

                if (entry.object) |obj| {
                    // Remap references within this object
                    const remapped = try remapRefsAuto(allocator, obj, &ref_map);
                    store.put(new_ref, remapped);

                    // Check if this is the AcroForm dictionary (has "Fields" key)
                    if (obj == .dict_obj) {
                        if (obj.dict_obj.get("Fields")) |_| {
                            acroform_new_ref = new_ref;
                        }
                    }
                }
            }
        }
        // -- Build PDF/A objects if needed --
        var pdfa_metadata_ref: ?Ref = null;
        var pdfa_output_intent_ref: ?Ref = null;
        var pdfa_xmp_data: ?[]u8 = null;
        defer if (pdfa_xmp_data) |xmp| allocator.free(xmp);

        if (doc.pdfa_level) |level| {
            // Generate XMP metadata with PDF/A identification
            pdfa_xmp_data = try pdfa.generatePdfAXmp(allocator, level, .{
                .title = doc.title,
                .author = doc.author,
                .subject = doc.subject,
                .keywords = doc.keywords,
                .creator = doc.creator,
                .producer = doc.producer,
            });

            // Build metadata stream
            pdfa_metadata_ref = try pdfa.buildMetadataStream(allocator, &store, pdfa_xmp_data.?);

            // Build output intent with ICC profile
            const icc_profile = &pdfa.SRGB_ICC_PROFILE;
            pdfa_output_intent_ref = try pdfa.buildOutputIntent(allocator, &store, icc_profile);
        }

        // -- Build Catalog --
        const catalog_ref = try store.allocate();
        {
            var catalog_dict = types.pdfDict(allocator);
            try catalog_dict.dict_obj.put(allocator,"Type", types.pdfName("Catalog"));
            try catalog_dict.dict_obj.put(allocator,"Pages", types.pdfRef(pages_ref.obj_num, pages_ref.gen_num));
            if (acroform_new_ref) |af_ref| {
                try catalog_dict.dict_obj.put(allocator,"AcroForm", types.pdfRef(af_ref.obj_num, af_ref.gen_num));
            }

            // Add PDF/A entries to catalog
            if (pdfa_metadata_ref) |meta_ref| {
                try catalog_dict.dict_obj.put(allocator, "Metadata", types.pdfRef(meta_ref.obj_num, meta_ref.gen_num));
            }
            if (pdfa_output_intent_ref) |intent_ref| {
                var intents_array = types.pdfArray(allocator);
                try intents_array.array_obj.append(types.pdfRef(intent_ref.obj_num, intent_ref.gen_num));
                try catalog_dict.dict_obj.put(allocator, "OutputIntents", intents_array);
            }

            store.put(catalog_ref, catalog_dict);
        }

        // -- Write all objects and record offsets --
        for (store.objects.items) |entry| {
            const offset: u64 = @intCast(buffer.len());
            try offsets.append(allocator, offset);

            try buffer.writeFmt("{d} {d} obj\n", .{ entry.ref.obj_num, entry.ref.gen_num });
            if (entry.object) |obj| {
                try object_serializer.writeObject(&buffer, obj);
            } else {
                try buffer.write("null");
            }
            try buffer.write("\nendobj\n");
        }

        // -- Write xref table --
        var xref_entries: ArrayList(XrefEntry) = .{};
        defer xref_entries.deinit(allocator);

        // Entry 0: free head
        try xref_entries.append(allocator, .{ .offset = 0, .gen = 65535, .in_use = false });

        // Entries for each object
        for (offsets.items[1..]) |off| {
            try xref_entries.append(allocator, .{ .offset = off, .gen = 0, .in_use = true });
        }

        const xref_offset = try xref_writer.writeXref(&buffer, xref_entries.items);

        // -- Write trailer --
        try xref_writer.writeTrailer(&buffer, xref_entries.items.len, catalog_ref, info_ref);

        // -- Write startxref --
        try buffer.writeFmt("startxref\n{d}\n", .{xref_offset});
        try buffer.write("%%EOF\n");

        return buffer.toOwnedSlice();
    }

    // Writes a PdfObject into a ByteBuffer using the object serializer.
    fn writeObjectToBuf(buf: *ByteBuffer, obj: PdfObject) !void {
        try object_serializer.writeObject(buf, obj);
    }
};

// Recursively remap indirect references within a PdfObject to use new object numbers.
fn remapRefsAuto(allocator: Allocator, obj: PdfObject, ref_map: *const std.AutoHashMapUnmanaged(u32, Ref)) Allocator.Error!PdfObject {
    switch (obj) {
        .ref_obj => |ref| {
            if (ref_map.get(ref.obj_num)) |new_ref| {
                return types.pdfRef(new_ref.obj_num, new_ref.gen_num);
            }
            return obj;
        },
        .array_obj => |arr| {
            var new_arr = types.pdfArray(allocator);
            for (arr.list.items) |item| {
                const remapped = try remapRefsAuto(allocator, item, ref_map);
                try new_arr.array_obj.append(remapped);
            }
            return new_arr;
        },
        .dict_obj => |dict| {
            var new_dict = types.pdfDict(allocator);
            var it = dict.iterator();
            while (it.next()) |entry| {
                const remapped = try remapRefsAuto(allocator, entry.value_ptr.*, ref_map);
                try new_dict.dict_obj.put(allocator, entry.key_ptr.*, remapped);
            }
            return new_dict;
        },
        else => return obj,
    }
}

// -- Tests --

test "PdfWriter produces valid PDF header" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);

    const pdf = try PdfWriter.writePdf(std.testing.allocator, &doc);
    defer std.testing.allocator.free(pdf);

    try std.testing.expect(std.mem.startsWith(u8, pdf, "%PDF-1.7\n"));
    try std.testing.expect(std.mem.indexOf(u8, pdf, "%%EOF") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "xref") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "trailer") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "startxref") != null);
}

test "PdfWriter includes metadata" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    doc.setTitle("Test Document");
    doc.setAuthor("zpdf");
    _ = try doc.addPage(.letter);

    const pdf = try PdfWriter.writePdf(std.testing.allocator, &doc);
    defer std.testing.allocator.free(pdf);

    try std.testing.expect(std.mem.indexOf(u8, pdf, "Test Document") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "/Catalog") != null);
}
