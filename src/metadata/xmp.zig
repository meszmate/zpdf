const std = @import("std");
const Allocator = std.mem.Allocator;
const DocumentInfo = @import("info_dict.zig").DocumentInfo;

/// Generate XMP (Extensible Metadata Platform) XML metadata from document info.
/// Returns a newly allocated XML string suitable for embedding as a PDF metadata stream.
pub fn generateXmp(allocator: Allocator, info: DocumentInfo) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n");
    try writer.writeAll("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n");
    try writer.writeAll("<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n");

    // Dublin Core properties
    try writer.writeAll("<rdf:Description rdf:about=\"\"\n");
    try writer.writeAll("  xmlns:dc=\"http://purl.org/dc/elements/1.1/\"\n");
    try writer.writeAll("  xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"\n");
    try writer.writeAll("  xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\"\n");
    try writer.writeAll("  xmlns:pdfaid=\"http://www.aiim.org/pdfa/ns/id/\">\n");

    if (info.title) |title| {
        try writer.writeAll("  <dc:title>\n");
        try writer.writeAll("    <rdf:Alt>\n");
        try writer.print("      <rdf:li xml:lang=\"x-default\">{s}</rdf:li>\n", .{title});
        try writer.writeAll("    </rdf:Alt>\n");
        try writer.writeAll("  </dc:title>\n");
    }

    if (info.author) |author| {
        try writer.writeAll("  <dc:creator>\n");
        try writer.writeAll("    <rdf:Seq>\n");
        try writer.print("      <rdf:li>{s}</rdf:li>\n", .{author});
        try writer.writeAll("    </rdf:Seq>\n");
        try writer.writeAll("  </dc:creator>\n");
    }

    if (info.subject) |subject| {
        try writer.writeAll("  <dc:description>\n");
        try writer.writeAll("    <rdf:Alt>\n");
        try writer.print("      <rdf:li xml:lang=\"x-default\">{s}</rdf:li>\n", .{subject});
        try writer.writeAll("    </rdf:Alt>\n");
        try writer.writeAll("  </dc:description>\n");
    }

    if (info.keywords) |keywords| {
        try writer.print("  <pdf:Keywords>{s}</pdf:Keywords>\n", .{keywords});
    }

    if (info.creator) |creator| {
        try writer.print("  <xmp:CreatorTool>{s}</xmp:CreatorTool>\n", .{creator});
    }

    if (info.producer) |producer| {
        try writer.print("  <pdf:Producer>{s}</pdf:Producer>\n", .{producer});
    }

    if (info.creation_date) |date| {
        try writer.print("  <xmp:CreateDate>{s}</xmp:CreateDate>\n", .{date});
    }

    if (info.mod_date) |date| {
        try writer.print("  <xmp:ModifyDate>{s}</xmp:ModifyDate>\n", .{date});
    }

    try writer.writeAll("</rdf:Description>\n");
    try writer.writeAll("</rdf:RDF>\n");
    try writer.writeAll("</x:xmpmeta>\n");
    try writer.writeAll("<?xpacket end=\"w\"?>");

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "xmp: generate with all fields" {
    const allocator = std.testing.allocator;
    const xmp = try generateXmp(allocator, .{
        .title = "Test",
        .author = "Author",
        .subject = "Subject",
        .keywords = "test, pdf",
        .creator = "zpdf",
        .producer = "zpdf",
        .creation_date = "2024-01-01",
        .mod_date = "2024-01-02",
    });
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket begin=") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<dc:title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "Test") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<dc:creator>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket end=") != null);
}

test "xmp: generate empty" {
    const allocator = std.testing.allocator;
    const xmp = try generateXmp(allocator, .{});
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket begin=") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<dc:title>") == null);
}

test "xmp: generate partial" {
    const allocator = std.testing.allocator;
    const xmp = try generateXmp(allocator, .{ .title = "Only Title" });
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "Only Title") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<dc:creator>") == null);
}
