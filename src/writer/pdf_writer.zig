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
const color_mod = @import("../color/color.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const header_footer = @import("../layout/header_footer.zig");
const pdfa = @import("../pdfa/pdfa.zig");
const AttachmentBuilder = @import("../document/attachments.zig").AttachmentBuilder;

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

        // -- Pre-allocate remapped refs for every object in doc.object_store.
        // This lets page resources (e.g. OCG /Properties entries) refer to
        // those objects before they are copied below.
        var doc_ref_map = std.AutoHashMapUnmanaged(u32, Ref){};
        defer doc_ref_map.deinit(allocator);
        for (doc.object_store.objects.items) |entry| {
            const new_ref = try store.allocate();
            try doc_ref_map.put(allocator, entry.ref.obj_num, new_ref);
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

            // Build Properties (optional content) resource dict for this page.
            // Layer refs live in doc.object_store and are remapped via doc_ref_map.
            var properties_dict = types.pdfDict(allocator);
            {
                for (page.resources.properties.items) |prop| {
                    const mapped = doc_ref_map.get(prop.ref.obj_num) orelse prop.ref;
                    try properties_dict.dict_obj.put(allocator, prop.name, types.pdfRef(mapped.obj_num, mapped.gen_num));
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
            if (properties_dict.dict_obj.count() > 0) {
                try resources_dict.dict_obj.put(allocator, "Properties", properties_dict);
            } else {
                properties_dict.deinit(allocator);
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

            // Build internal link annotations for this page
            {
                var annots_array = types.pdfArray(allocator);
                const page_idx = page_refs.items.len - 1; // current page index

                for (doc.internal_links.items) |il| {
                    if (il.page_index == page_idx) {
                        const annot_ref = try store.allocate();

                        var annot_dict = types.pdfDict(allocator);
                        try annot_dict.dict_obj.put(allocator, "Type", types.pdfName("Annot"));
                        try annot_dict.dict_obj.put(allocator, "Subtype", types.pdfName("Link"));

                        var rect_arr = types.pdfArray(allocator);
                        try rect_arr.array_obj.append(types.pdfReal(@floatCast(il.link.rect[0])));
                        try rect_arr.array_obj.append(types.pdfReal(@floatCast(il.link.rect[1])));
                        try rect_arr.array_obj.append(types.pdfReal(@floatCast(il.link.rect[2])));
                        try rect_arr.array_obj.append(types.pdfReal(@floatCast(il.link.rect[3])));
                        try annot_dict.dict_obj.put(allocator, "Rect", rect_arr);

                        // Border
                        var border_arr = types.pdfArray(allocator);
                        try border_arr.array_obj.append(types.pdfReal(0));
                        try border_arr.array_obj.append(types.pdfReal(0));
                        try border_arr.array_obj.append(types.pdfReal(@floatCast(il.link.border_width)));
                        try annot_dict.dict_obj.put(allocator, "Border", border_arr);

                        // Color
                        if (il.link.color) |c| {
                            const rgb_val = c.toRgb();
                            var color_arr = types.pdfArray(allocator);
                            try color_arr.array_obj.append(types.pdfReal(@as(f64, @floatFromInt(rgb_val.r)) / 255.0));
                            try color_arr.array_obj.append(types.pdfReal(@as(f64, @floatFromInt(rgb_val.g)) / 255.0));
                            try color_arr.array_obj.append(types.pdfReal(@as(f64, @floatFromInt(rgb_val.b)) / 255.0));
                            try annot_dict.dict_obj.put(allocator, "C", color_arr);
                        }

                        // Destination reference by name
                        try annot_dict.dict_obj.put(allocator, "Dest", types.pdfString(il.link.dest_name));

                        // Print flag
                        try annot_dict.dict_obj.put(allocator, "F", types.pdfInt(4));

                        store.put(annot_ref, annot_dict);
                        try annots_array.array_obj.append(types.pdfRef(annot_ref.obj_num, annot_ref.gen_num));
                    }
                }

                if (annots_array.array_obj.list.items.len > 0) {
                    try page_dict.dict_obj.put(allocator, "Annots", annots_array);
                } else {
                    annots_array.deinit(allocator);
                }
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

        // -- Copy objects from document object store --
        // The FormBuilder, OcgBuilder, and other subsystems stash objects in
        // doc.object_store. Their new refs were pre-allocated above so pages
        // can reference them; here we actually copy each object, remapping
        // any internal references.
        var acroform_new_ref: ?Ref = null;
        {
            for (doc.object_store.objects.items) |entry| {
                const new_ref = doc_ref_map.get(entry.ref.obj_num).?;

                if (entry.object) |obj| {
                    const remapped = try remapRefsAuto(allocator, obj, &doc_ref_map);
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

        // -- Build attachment objects if any --
        var attachment_names_ref: ?Ref = null;
        if (doc.attachment_builder) |*ab| {
            attachment_names_ref = try ab.build(&store);
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

            // Optional Content Properties (layers), remapped from doc.object_store.
            if (doc.oc_properties_ref) |ocp| {
                if (doc_ref_map.get(ocp.obj_num)) |mapped| {
                    try catalog_dict.dict_obj.put(allocator, "OCProperties", types.pdfRef(mapped.obj_num, mapped.gen_num));
                }
            }

            // Add attachment names to catalog
            if (attachment_names_ref) |names_ref| {
                try catalog_dict.dict_obj.put(allocator, "Names", types.pdfRef(names_ref.obj_num, names_ref.gen_num));
            }

            // Add named destinations to catalog
            if (doc.named_destinations.items.len > 0) {
                var names_array = types.pdfArray(allocator);
                for (doc.named_destinations.items) |dest| {
                    // Name string
                    try names_array.array_obj.append(types.pdfString(dest.name));

                    // Destination array: [page_ref /Type params...]
                    var dest_arr = types.pdfArray(allocator);
                    if (dest.page_index < page_refs.items.len) {
                        const pref = page_refs.items[dest.page_index];
                        try dest_arr.array_obj.append(types.pdfRef(pref.obj_num, pref.gen_num));
                    } else {
                        try dest_arr.array_obj.append(types.pdfInt(0));
                    }

                    switch (dest.dest_type) {
                        .xyz => {
                            try dest_arr.array_obj.append(types.pdfName("XYZ"));
                            if (dest.left) |l| {
                                try dest_arr.array_obj.append(types.pdfReal(@floatCast(l)));
                            } else {
                                try dest_arr.array_obj.append(.null_obj);
                            }
                            if (dest.top) |t| {
                                try dest_arr.array_obj.append(types.pdfReal(@floatCast(t)));
                            } else {
                                try dest_arr.array_obj.append(.null_obj);
                            }
                            if (dest.zoom) |z| {
                                try dest_arr.array_obj.append(types.pdfReal(@floatCast(z)));
                            } else {
                                try dest_arr.array_obj.append(.null_obj);
                            }
                        },
                        .fit => {
                            try dest_arr.array_obj.append(types.pdfName("Fit"));
                        },
                        .fit_h => {
                            try dest_arr.array_obj.append(types.pdfName("FitH"));
                            if (dest.top) |t| {
                                try dest_arr.array_obj.append(types.pdfReal(@floatCast(t)));
                            } else {
                                try dest_arr.array_obj.append(.null_obj);
                            }
                        },
                        .fit_v => {
                            try dest_arr.array_obj.append(types.pdfName("FitV"));
                            if (dest.left) |l| {
                                try dest_arr.array_obj.append(types.pdfReal(@floatCast(l)));
                            } else {
                                try dest_arr.array_obj.append(.null_obj);
                            }
                        },
                        .fit_r => {
                            try dest_arr.array_obj.append(types.pdfName("FitR"));
                            try dest_arr.array_obj.append(types.pdfReal(@floatCast(dest.left orelse 0)));
                            try dest_arr.array_obj.append(types.pdfReal(@floatCast(dest.bottom orelse 0)));
                            try dest_arr.array_obj.append(types.pdfReal(@floatCast(dest.right orelse 0)));
                            try dest_arr.array_obj.append(types.pdfReal(@floatCast(dest.top orelse 0)));
                        },
                    }

                    try names_array.array_obj.append(dest_arr);
                }

                // Build /Names << /Dests << /Names [...] >> >>
                var dests_dict = types.pdfDict(allocator);
                try dests_dict.dict_obj.put(allocator, "Names", names_array);

                var names_dict = types.pdfDict(allocator);
                try names_dict.dict_obj.put(allocator, "Dests", dests_dict);

                try catalog_dict.dict_obj.put(allocator, "Names", names_dict);
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
