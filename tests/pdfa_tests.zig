const std = @import("std");
const zpdf = @import("zpdf");

const ConformanceLevel = zpdf.PdfAConformanceLevel;
const pdfa = zpdf.pdfa;

test "conformance level part mapping" {
    try std.testing.expectEqual(@as(u8, 1), ConformanceLevel.pdfa_1b.part());
    try std.testing.expectEqual(@as(u8, 1), ConformanceLevel.pdfa_1a.part());
    try std.testing.expectEqual(@as(u8, 2), ConformanceLevel.pdfa_2b.part());
    try std.testing.expectEqual(@as(u8, 2), ConformanceLevel.pdfa_2a.part());
    try std.testing.expectEqual(@as(u8, 3), ConformanceLevel.pdfa_3b.part());
}

test "conformance level conformance string mapping" {
    try std.testing.expectEqualStrings("B", ConformanceLevel.pdfa_1b.conformance());
    try std.testing.expectEqualStrings("A", ConformanceLevel.pdfa_1a.conformance());
    try std.testing.expectEqualStrings("B", ConformanceLevel.pdfa_2b.conformance());
    try std.testing.expectEqualStrings("A", ConformanceLevel.pdfa_2a.conformance());
    try std.testing.expectEqualStrings("B", ConformanceLevel.pdfa_3b.conformance());
}

test "conformance level pdf version selection" {
    try std.testing.expectEqualStrings("1.4", ConformanceLevel.pdfa_1b.pdfVersion());
    try std.testing.expectEqualStrings("1.4", ConformanceLevel.pdfa_1a.pdfVersion());
    try std.testing.expectEqualStrings("1.7", ConformanceLevel.pdfa_2b.pdfVersion());
    try std.testing.expectEqualStrings("1.7", ConformanceLevel.pdfa_2a.pdfVersion());
    try std.testing.expectEqualStrings("1.7", ConformanceLevel.pdfa_3b.pdfVersion());
}

test "XMP generation includes PDF/A identification for 1b" {
    const allocator = std.testing.allocator;
    const xmp = try pdfa.generatePdfAXmp(allocator, .pdfa_1b, .{
        .title = "Archival Document",
        .author = "Test",
    });
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "<pdfaid:part>1</pdfaid:part>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<pdfaid:conformance>B</pdfaid:conformance>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "Archival Document") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket begin=") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket end=") != null);
}

test "XMP generation includes PDF/A identification for 2a" {
    const allocator = std.testing.allocator;
    const xmp = try pdfa.generatePdfAXmp(allocator, .pdfa_2a, .{});
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "<pdfaid:part>2</pdfaid:part>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<pdfaid:conformance>A</pdfaid:conformance>") != null);
}

test "XMP generation includes PDF/A identification for 3b" {
    const allocator = std.testing.allocator;
    const xmp = try pdfa.generatePdfAXmp(allocator, .pdfa_3b, .{});
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "<pdfaid:part>3</pdfaid:part>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<pdfaid:conformance>B</pdfaid:conformance>") != null);
}

test "ICC profile has valid acsp signature" {
    const profile = pdfa.SRGB_ICC_PROFILE;
    try std.testing.expectEqualStrings("acsp", profile[36..40]);
}

test "ICC profile has correct size in header" {
    const profile = pdfa.SRGB_ICC_PROFILE;
    const size = @as(u32, profile[0]) << 24 |
        @as(u32, profile[1]) << 16 |
        @as(u32, profile[2]) << 8 |
        @as(u32, profile[3]);
    try std.testing.expectEqual(@as(u32, profile.len), size);
}

test "ICC profile is RGB display profile" {
    const profile = pdfa.SRGB_ICC_PROFILE;
    try std.testing.expectEqualStrings("mntr", profile[12..16]);
    try std.testing.expectEqualStrings("RGB ", profile[16..20]);
    try std.testing.expectEqualStrings("XYZ ", profile[20..24]);
}

test "output intent dictionary structure" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try pdfa.buildOutputIntent(allocator, &store, &pdfa.SRGB_ICC_PROFILE);
    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());

    // Verify required OutputIntent keys
    const type_val = obj.?.dict_obj.get("Type");
    try std.testing.expect(type_val != null);
    try std.testing.expectEqualStrings("OutputIntent", type_val.?.asName().?);

    const s_val = obj.?.dict_obj.get("S");
    try std.testing.expect(s_val != null);
    try std.testing.expectEqualStrings("GTS_PDFA1", s_val.?.asName().?);

    const oci_val = obj.?.dict_obj.get("OutputConditionIdentifier");
    try std.testing.expect(oci_val != null);

    const dest = obj.?.dict_obj.get("DestOutputProfile");
    try std.testing.expect(dest != null);
    try std.testing.expect(dest.?.isRef());
}

test "metadata stream creation" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const xmp_data = "<?xpacket begin?><test/><?xpacket end?>";
    const ref = try pdfa.buildMetadataStream(allocator, &store, xmp_data);
    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isStream());

    const type_val = obj.?.stream_obj.dict.get("Type");
    try std.testing.expect(type_val != null);
    try std.testing.expectEqualStrings("Metadata", type_val.?.asName().?);

    const sub_val = obj.?.stream_obj.dict.get("Subtype");
    try std.testing.expect(sub_val != null);
    try std.testing.expectEqualStrings("XML", sub_val.?.asName().?);
}

test "validation detects missing PDF/A requirements" {
    const allocator = std.testing.allocator;
    const bad_pdf = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF";
    const result = try pdfa.validate(allocator, bad_pdf, .pdfa_1b);
    defer allocator.free(result.errors);

    try std.testing.expect(!result.is_valid);
    try std.testing.expect(result.errors.len >= 3);
}

test "validation detects encryption" {
    const allocator = std.testing.allocator;
    const encrypted = "%PDF-1.4\n/Encrypt /Type /Metadata pdfaid:part pdfaid:conformance /OutputIntents /DestOutputProfile";
    const result = try pdfa.validate(allocator, encrypted, .pdfa_1b);
    defer allocator.free(result.errors);

    var found_encrypt_error = false;
    for (result.errors) |err| {
        if (err.code == .encryption_not_allowed) found_encrypt_error = true;
    }
    try std.testing.expect(found_encrypt_error);
}

test "validation detects version mismatch" {
    const allocator = std.testing.allocator;
    // PDF/A-1b expects version 1.4, but we give 1.7
    const wrong_version = "%PDF-1.7\n/Type /Metadata pdfaid:part pdfaid:conformance /OutputIntents /DestOutputProfile";
    const result = try pdfa.validate(allocator, wrong_version, .pdfa_1b);
    defer allocator.free(result.errors);

    var found_version_error = false;
    for (result.errors) |err| {
        if (err.code == .version_mismatch) found_version_error = true;
    }
    try std.testing.expect(found_version_error);
}

test "document setPdfAConformance" {
    const allocator = std.testing.allocator;
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    try std.testing.expect(doc.pdfa_level == null);
    doc.setPdfAConformance(.pdfa_1b);
    try std.testing.expect(doc.pdfa_level != null);
    try std.testing.expectEqual(zpdf.PdfAConformanceLevel.pdfa_1b, doc.pdfa_level.?);
}

test "PDF/A document generates correct version header" {
    const allocator = std.testing.allocator;
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setPdfAConformance(.pdfa_1b);
    doc.setTitle("PDF/A Test");
    _ = try doc.addPage(.a4);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    // Should have PDF 1.4 header for PDF/A-1b
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-1.4\n"));
}

test "PDF/A document includes XMP metadata and output intent" {
    const allocator = std.testing.allocator;
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setPdfAConformance(.pdfa_1b);
    doc.setTitle("Archival Test");
    doc.setAuthor("zpdf");
    _ = try doc.addPage(.a4);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    // Check for PDF/A-specific content
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/Type /Metadata") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/Subtype /XML") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "pdfaid:part") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "pdfaid:conformance") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/OutputIntents") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/GTS_PDFA1") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/DestOutputProfile") != null);
}
