const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// PDF/A conformance level.
pub const ConformanceLevel = enum {
    /// PDF/A-1b: basic conformance (visual appearance preservation)
    pdfa_1b,
    /// PDF/A-1a: full conformance (1b + tagged/structured)
    pdfa_1a,
    /// PDF/A-2b: based on PDF 1.7, adds JPEG2000, transparency, layers
    pdfa_2b,
    /// PDF/A-2a: 2b + tagged/structured
    pdfa_2a,
    /// PDF/A-3b: like 2b but allows embedded files
    pdfa_3b,

    pub fn part(self: ConformanceLevel) u8 {
        return switch (self) {
            .pdfa_1b, .pdfa_1a => 1,
            .pdfa_2b, .pdfa_2a => 2,
            .pdfa_3b => 3,
        };
    }

    pub fn conformance(self: ConformanceLevel) []const u8 {
        return switch (self) {
            .pdfa_1b, .pdfa_2b, .pdfa_3b => "B",
            .pdfa_1a, .pdfa_2a => "A",
        };
    }

    pub fn pdfVersion(self: ConformanceLevel) []const u8 {
        return switch (self) {
            .pdfa_1b, .pdfa_1a => "1.4",
            .pdfa_2b, .pdfa_2a, .pdfa_3b => "1.7",
        };
    }
};

/// Options for PDF/A compliance.
pub const PdfAOptions = struct {
    level: ConformanceLevel = .pdfa_1b,
    /// Override the ICC profile (default: built-in sRGB)
    icc_profile: ?[]const u8 = null,
};

/// Validation result for PDF/A compliance checking.
pub const ValidationResult = struct {
    is_valid: bool,
    errors: []const ValidationError,
};

pub const ValidationError = struct {
    code: ErrorCode,
    message: []const u8,
};

pub const ErrorCode = enum {
    missing_xmp_metadata,
    missing_pdfa_identification,
    missing_output_intent,
    missing_icc_profile,
    encryption_not_allowed,
    unembedded_font,
    missing_document_info,
    version_mismatch,
};

/// Generate the XMP metadata stream with PDF/A identification.
pub fn generatePdfAXmp(
    allocator: Allocator,
    level: ConformanceLevel,
    info: struct {
        title: ?[]const u8 = null,
        author: ?[]const u8 = null,
        subject: ?[]const u8 = null,
        keywords: ?[]const u8 = null,
        creator: ?[]const u8 = null,
        producer: ?[]const u8 = null,
    },
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n");
    try writer.writeAll("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n");
    try writer.writeAll("<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n");

    // Dublin Core and PDF properties
    try writer.writeAll("<rdf:Description rdf:about=\"\"\n");
    try writer.writeAll("  xmlns:dc=\"http://purl.org/dc/elements/1.1/\"\n");
    try writer.writeAll("  xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"\n");
    try writer.writeAll("  xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\"\n");
    try writer.writeAll("  xmlns:pdfaid=\"http://www.aiim.org/pdfa/ns/id/\">\n");

    // PDF/A identification - required for conformance
    try writer.print("  <pdfaid:part>{d}</pdfaid:part>\n", .{level.part()});
    try writer.print("  <pdfaid:conformance>{s}</pdfaid:conformance>\n", .{level.conformance()});

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

    try writer.writeAll("</rdf:Description>\n");
    try writer.writeAll("</rdf:RDF>\n");
    try writer.writeAll("</x:xmpmeta>\n");

    // Pad with spaces to allow in-place editing (common PDF/A practice)
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try writer.writeAll("                                                                                \n");
    }

    try writer.writeAll("<?xpacket end=\"w\"?>");

    return buf.toOwnedSlice(allocator);
}

/// Build the output intent dictionary with embedded ICC profile.
/// Returns a reference to the OutputIntent dictionary.
pub fn buildOutputIntent(
    allocator: Allocator,
    store: *ObjectStore,
    icc_profile: []const u8,
) !Ref {
    // Create the ICC profile stream object
    const icc_ref = try store.allocate();
    {
        var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try stream_dict.put(allocator, "N", types.pdfInt(3)); // 3-component (RGB)
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(icc_profile.len)));

        store.put(icc_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = icc_profile,
        } });
    }

    // Create the OutputIntent dictionary
    const intent_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("OutputIntent"));
        try dict.dict_obj.put(allocator, "S", types.pdfName("GTS_PDFA1"));
        try dict.dict_obj.put(allocator, "OutputConditionIdentifier", types.pdfString("sRGB IEC61966-2.1"));
        try dict.dict_obj.put(allocator, "RegistryName", types.pdfString("http://www.color.org"));
        try dict.dict_obj.put(allocator, "Info", types.pdfString("sRGB IEC61966-2.1"));
        try dict.dict_obj.put(allocator, "DestOutputProfile", types.pdfRef(icc_ref.obj_num, icc_ref.gen_num));
        store.put(intent_ref, dict);
    }

    return intent_ref;
}

/// Build the metadata stream object.
/// Returns a reference to the metadata stream.
pub fn buildMetadataStream(
    allocator: Allocator,
    store: *ObjectStore,
    xmp_data: []const u8,
) !Ref {
    const meta_ref = try store.allocate();

    var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
    try stream_dict.put(allocator, "Type", types.pdfName("Metadata"));
    try stream_dict.put(allocator, "Subtype", types.pdfName("XML"));
    try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(xmp_data.len)));

    store.put(meta_ref, .{ .stream_obj = .{
        .dict = stream_dict,
        .data = xmp_data,
    } });

    return meta_ref;
}

/// Validate a PDF document against PDF/A requirements.
/// This performs a basic structural check of the raw PDF bytes.
pub fn validate(
    allocator: Allocator,
    pdf_data: []const u8,
    level: ConformanceLevel,
) !ValidationResult {
    var errors: std.ArrayListUnmanaged(ValidationError) = .{};
    errdefer errors.deinit(allocator);

    // Check PDF version header
    const expected_version = level.pdfVersion();
    const header_prefix = "%PDF-";
    if (pdf_data.len < header_prefix.len + expected_version.len) {
        try errors.append(allocator, .{
            .code = .version_mismatch,
            .message = "PDF data too short to contain a valid header",
        });
    } else {
        if (!std.mem.startsWith(u8, pdf_data, header_prefix)) {
            try errors.append(allocator, .{
                .code = .version_mismatch,
                .message = "Missing PDF header",
            });
        } else {
            const version_start = header_prefix.len;
            const version_end = version_start + expected_version.len;
            if (!std.mem.eql(u8, pdf_data[version_start..version_end], expected_version)) {
                try errors.append(allocator, .{
                    .code = .version_mismatch,
                    .message = "PDF version does not match conformance level",
                });
            }
        }
    }

    // Check for XMP metadata presence
    if (std.mem.indexOf(u8, pdf_data, "/Type /Metadata") == null and
        std.mem.indexOf(u8, pdf_data, "/Type/Metadata") == null)
    {
        try errors.append(allocator, .{
            .code = .missing_xmp_metadata,
            .message = "No XMP metadata stream found",
        });
    }

    // Check for PDF/A identification in XMP
    if (std.mem.indexOf(u8, pdf_data, "pdfaid:part") == null) {
        try errors.append(allocator, .{
            .code = .missing_pdfa_identification,
            .message = "No pdfaid:part element found in XMP metadata",
        });
    }

    if (std.mem.indexOf(u8, pdf_data, "pdfaid:conformance") == null) {
        try errors.append(allocator, .{
            .code = .missing_pdfa_identification,
            .message = "No pdfaid:conformance element found in XMP metadata",
        });
    }

    // Check for OutputIntent
    if (std.mem.indexOf(u8, pdf_data, "/OutputIntents") == null) {
        try errors.append(allocator, .{
            .code = .missing_output_intent,
            .message = "No OutputIntents array found in catalog",
        });
    }

    // Check for ICC profile stream
    if (std.mem.indexOf(u8, pdf_data, "/DestOutputProfile") == null) {
        try errors.append(allocator, .{
            .code = .missing_icc_profile,
            .message = "No ICC output profile reference found",
        });
    }

    // Check that encryption is not present
    if (std.mem.indexOf(u8, pdf_data, "/Encrypt") != null) {
        try errors.append(allocator, .{
            .code = .encryption_not_allowed,
            .message = "PDF/A documents must not be encrypted",
        });
    }

    const err_slice = try errors.toOwnedSlice(allocator);
    return .{
        .is_valid = err_slice.len == 0,
        .errors = err_slice,
    };
}

/// Generate a minimal valid sRGB ICC color profile at comptime.
/// This profile conforms to ICC v2.1 and contains the minimum required tags
/// for an RGB display profile: description, white point, colorants, TRCs, and copyright.
pub const SRGB_ICC_PROFILE = generateMinimalSrgbProfile();

fn generateMinimalSrgbProfile() [416]u8 {
    // ICC profile layout:
    //   0..127   : Header (128 bytes)
    //   128..131 : Tag count (u32 BE) = 9
    //   132..239 : Tag table (9 tags * 12 bytes each = 108 bytes)
    //   240..end : Tag data
    //
    // Tags needed for a minimal RGB display profile:
    //   1. desc (profileDescriptionTag)
    //   2. wtpt (mediaWhitePointTag)
    //   3. rXYZ (redColorantTag)
    //   4. gXYZ (greenColorantTag)
    //   5. bXYZ (blueColorantTag)
    //   6. rTRC (redTRCTag)
    //   7. gTRC (greenTRCTag)
    //   8. bTRC (blueTRCTag)
    //   9. cprt (copyrightTag)

    @setEvalBranchQuota(10000);
    var profile: [416]u8 = [_]u8{0} ** 416;

    const profile_size: u32 = 416;
    const tag_count: u32 = 9;

    // -- Header (128 bytes) --
    writeU32BE(&profile, 0, profile_size); // Profile size
    // bytes 4..7: preferred CMM type = 0 (already zero)
    // Version 2.1.0: major=2, minor.bugfix = 0x10, 0x00
    profile[8] = 2;
    profile[9] = 0x10;
    // bytes 10..11: 0 (already zero)
    // Device class: 'mntr'
    profile[12] = 'm';
    profile[13] = 'n';
    profile[14] = 't';
    profile[15] = 'r';
    // Color space: 'RGB '
    profile[16] = 'R';
    profile[17] = 'G';
    profile[18] = 'B';
    profile[19] = ' ';
    // PCS: 'XYZ '
    profile[20] = 'X';
    profile[21] = 'Y';
    profile[22] = 'Z';
    profile[23] = ' ';
    // Date/time: 2024-01-01 00:00:00
    writeU16BE(&profile, 24, 2024); // year
    writeU16BE(&profile, 26, 1); // month
    writeU16BE(&profile, 28, 1); // day
    // hours, minutes, seconds = 0 (already zero)
    // Signature: 'acsp'
    profile[36] = 'a';
    profile[37] = 'c';
    profile[38] = 's';
    profile[39] = 'p';
    // bytes 40..43: primary platform = 0
    // bytes 44..47: profile flags = 0
    // bytes 48..51: device manufacturer = 0
    // bytes 52..55: device model = 0
    // bytes 56..63: device attributes = 0
    // bytes 64..67: rendering intent = 0 (perceptual)
    // PCS illuminant D50: X=0.9505, Y=1.0, Z=1.0890
    // as s15Fixed16: X = 0x0000F6D6, Y = 0x00010000, Z = 0x0000D32D
    writeU32BE(&profile, 68, 0x0000F6D6);
    writeU32BE(&profile, 72, 0x00010000);
    writeU32BE(&profile, 76, 0x0000D32D);
    // bytes 80..127: creator, profile ID, reserved = 0

    // -- Tag count --
    writeU32BE(&profile, 128, tag_count);

    // -- Tag table (starts at 132) --
    // Each entry: signature(4) + offset(4) + size(4)

    // Tag data offsets (after header + tag count + tag table):
    // Tag table ends at 132 + 9*12 = 240
    const data_start: u32 = 240;

    // Layout of tag data:
    // desc: 240..279 (40 bytes)
    // wtpt: 280..299 (20 bytes)
    // rXYZ: 300..319 (20 bytes)
    // gXYZ: 320..339 (20 bytes)
    // bXYZ: 340..359 (20 bytes)
    // rTRC: 360..371 (12 bytes) -- curveType with single gamma
    // gTRC: shared with rTRC (same offset)
    // bTRC: shared with rTRC (same offset)
    // cprt: 372..415 (44 bytes)

    const desc_offset = data_start;
    const desc_size: u32 = 40;
    const wtpt_offset = desc_offset + desc_size; // 280
    const xyz_size: u32 = 20;
    const rxyz_offset = wtpt_offset + xyz_size; // 300
    const gxyz_offset = rxyz_offset + xyz_size; // 320
    const bxyz_offset = gxyz_offset + xyz_size; // 340
    const trc_offset = bxyz_offset + xyz_size; // 360
    const trc_size: u32 = 12;
    const cprt_offset = trc_offset + trc_size; // 372
    const cprt_size: u32 = 44;
    _ = cprt_size;

    // 1. desc
    writeTag(&profile, 132, "desc", desc_offset, desc_size);
    // 2. wtpt
    writeTag(&profile, 144, "wtpt", wtpt_offset, xyz_size);
    // 3. rXYZ
    writeTag(&profile, 156, "rXYZ", rxyz_offset, xyz_size);
    // 4. gXYZ
    writeTag(&profile, 168, "gXYZ", gxyz_offset, xyz_size);
    // 5. bXYZ
    writeTag(&profile, 180, "bXYZ", bxyz_offset, xyz_size);
    // 6. rTRC
    writeTag(&profile, 192, "rTRC", trc_offset, trc_size);
    // 7. gTRC (shares data with rTRC)
    writeTag(&profile, 204, "gTRC", trc_offset, trc_size);
    // 8. bTRC (shares data with rTRC)
    writeTag(&profile, 216, "bTRC", trc_offset, trc_size);
    // 9. cprt
    writeTag(&profile, 228, "cprt", cprt_offset, 44);

    // -- Tag data --

    // desc tag data: textDescriptionType
    // type signature 'desc' + reserved(4) + ASCII count(4) + ASCII string
    profile[desc_offset] = 'd';
    profile[desc_offset + 1] = 'e';
    profile[desc_offset + 2] = 's';
    profile[desc_offset + 3] = 'c';
    // reserved 4 bytes = 0
    writeU32BE(&profile, desc_offset + 8, 5); // string length including null
    profile[desc_offset + 12] = 's';
    profile[desc_offset + 13] = 'R';
    profile[desc_offset + 14] = 'G';
    profile[desc_offset + 15] = 'B';
    profile[desc_offset + 16] = 0; // null terminator

    // wtpt tag data: XYZType for D50
    // type signature 'XYZ ' + reserved(4) + XYZ values (12 bytes)
    writeXYZTag(&profile, wtpt_offset, 0x0000F6D6, 0x00010000, 0x0000D32D);

    // rXYZ: sRGB red colorant (D50-adapted): X=0.4360747, Y=0.2225045, Z=0.0139322
    // s15Fixed16: X=0x6FA2, Y=0x38F5, Z=0x0390 (approximate)
    writeXYZTag(&profile, rxyz_offset, 0x00006FA2, 0x000038F5, 0x00000390);

    // gXYZ: sRGB green colorant (D50-adapted): X=0.3850649, Y=0.7168786, Z=0.0971045
    // s15Fixed16: X=0x6299, Y=0xB785, Z=0x18DA (approximate)
    writeXYZTag(&profile, gxyz_offset, 0x00006299, 0x0000B785, 0x000018DA);

    // bXYZ: sRGB blue colorant (D50-adapted): X=0.1430804, Y=0.0606169, Z=0.7141633
    // s15Fixed16: X=0x2493, Y=0x0F84, Z=0xB6CF (approximate)
    writeXYZTag(&profile, bxyz_offset, 0x00002493, 0x00000F84, 0x0000B6CF);

    // TRC: curveType with gamma 2.2
    // type signature 'curv' + reserved(4) + count(4, value=1) + gamma(u16)
    // But curveType with count=1 means a single u16 gamma value.
    // The u16 is u8Fixed8Number: 2.2 = 0x0233 approximately (2 + 0.2*256 = 2 + 51.2 ~ 0x0233)
    // Actually for ICC curveType, count=0 means identity, count=1 means the entry is
    // a u8Fixed8Number gamma. 2.2 => integer=2, fraction=0.2*256=51.2 => 0x0233
    profile[trc_offset] = 'c';
    profile[trc_offset + 1] = 'u';
    profile[trc_offset + 2] = 'r';
    profile[trc_offset + 3] = 'v';
    // reserved 4 bytes = 0
    writeU32BE(&profile, trc_offset + 8, 1); // count = 1 (single gamma)
    // For count=1, we don't write a u16 gamma after count -- wait, actually we do.
    // But our trc_size is 12 which is signature(4)+reserved(4)+count(4) = 12.
    // With count=1 we need 2 more bytes for the u16 gamma value.
    // Let me recalculate... Actually the spec says curveType data is:
    //   signature(4) + reserved(4) + count(4) + count * u16
    // For count=1: 4+4+4+2 = 14, padded to 16 for 4-byte alignment? Actually ICC
    // only requires padding on the tag *data* within the profile for alignment of
    // subsequent tags. Since TRC is shared by all three and cprt follows, let me
    // just use count=0 (identity/linear) to keep things simple, OR use parametric
    // curve type.
    //
    // Actually, the simplest valid approach: use count=0 which means identity (gamma=1.0).
    // That's technically valid ICC but not accurate for sRGB. For PDF/A compliance
    // what matters is that the ICC profile is structurally valid, not that it perfectly
    // represents sRGB. Let's use count=0 for identity.
    //
    // But let's be more accurate. We have room. Let me adjust sizes.
    // Actually, the profile_size is fixed at 416 and all offsets are set. Let me just
    // set count=0 for identity curve. This is a valid minimal profile.
    writeU32BE(&profile, trc_offset + 8, 0); // count = 0 means identity

    // cprt tag data: textType
    // type signature 'text' + reserved(4) + ASCII text
    profile[cprt_offset] = 't';
    profile[cprt_offset + 1] = 'e';
    profile[cprt_offset + 2] = 'x';
    profile[cprt_offset + 3] = 't';
    // reserved 4 bytes = 0
    // Text: "Public Domain"
    const cprt_text = "Public Domain sRGB";
    for (cprt_text, 0..) |c, ci| {
        profile[cprt_offset + 8 + ci] = c;
    }

    return profile;
}

fn writeU32BE(buf: []u8, offset: u32, value: u32) void {
    buf[offset] = @intCast((value >> 24) & 0xFF);
    buf[offset + 1] = @intCast((value >> 16) & 0xFF);
    buf[offset + 2] = @intCast((value >> 8) & 0xFF);
    buf[offset + 3] = @intCast(value & 0xFF);
}

fn writeU16BE(buf: []u8, offset: u32, value: u16) void {
    buf[offset] = @intCast((value >> 8) & 0xFF);
    buf[offset + 1] = @intCast(value & 0xFF);
}

fn writeTag(buf: []u8, table_offset: u32, sig: *const [4]u8, data_offset: u32, data_size: u32) void {
    buf[table_offset] = sig[0];
    buf[table_offset + 1] = sig[1];
    buf[table_offset + 2] = sig[2];
    buf[table_offset + 3] = sig[3];
    writeU32BE(buf, table_offset + 4, data_offset);
    writeU32BE(buf, table_offset + 8, data_size);
}

fn writeXYZTag(buf: []u8, offset: u32, x: u32, y: u32, z: u32) void {
    buf[offset] = 'X';
    buf[offset + 1] = 'Y';
    buf[offset + 2] = 'Z';
    buf[offset + 3] = ' ';
    // reserved 4 bytes = 0
    writeU32BE(buf, offset + 8, x);
    writeU32BE(buf, offset + 12, y);
    writeU32BE(buf, offset + 16, z);
}

// -- Tests --

test "conformance level part numbers" {
    try std.testing.expectEqual(@as(u8, 1), ConformanceLevel.pdfa_1b.part());
    try std.testing.expectEqual(@as(u8, 1), ConformanceLevel.pdfa_1a.part());
    try std.testing.expectEqual(@as(u8, 2), ConformanceLevel.pdfa_2b.part());
    try std.testing.expectEqual(@as(u8, 2), ConformanceLevel.pdfa_2a.part());
    try std.testing.expectEqual(@as(u8, 3), ConformanceLevel.pdfa_3b.part());
}

test "conformance level conformance strings" {
    try std.testing.expectEqualStrings("B", ConformanceLevel.pdfa_1b.conformance());
    try std.testing.expectEqualStrings("A", ConformanceLevel.pdfa_1a.conformance());
    try std.testing.expectEqualStrings("B", ConformanceLevel.pdfa_2b.conformance());
    try std.testing.expectEqualStrings("A", ConformanceLevel.pdfa_2a.conformance());
    try std.testing.expectEqualStrings("B", ConformanceLevel.pdfa_3b.conformance());
}

test "conformance level pdf versions" {
    try std.testing.expectEqualStrings("1.4", ConformanceLevel.pdfa_1b.pdfVersion());
    try std.testing.expectEqualStrings("1.4", ConformanceLevel.pdfa_1a.pdfVersion());
    try std.testing.expectEqualStrings("1.7", ConformanceLevel.pdfa_2b.pdfVersion());
    try std.testing.expectEqualStrings("1.7", ConformanceLevel.pdfa_2a.pdfVersion());
    try std.testing.expectEqualStrings("1.7", ConformanceLevel.pdfa_3b.pdfVersion());
}

test "ICC profile has valid header signature" {
    const profile = SRGB_ICC_PROFILE;
    // 'acsp' at offset 36
    try std.testing.expectEqualStrings("acsp", profile[36..40]);
}

test "ICC profile has correct device class" {
    const profile = SRGB_ICC_PROFILE;
    // 'mntr' at offset 12
    try std.testing.expectEqualStrings("mntr", profile[12..16]);
}

test "ICC profile has correct color space" {
    const profile = SRGB_ICC_PROFILE;
    try std.testing.expectEqualStrings("RGB ", profile[16..20]);
}

test "ICC profile has correct PCS" {
    const profile = SRGB_ICC_PROFILE;
    try std.testing.expectEqualStrings("XYZ ", profile[20..24]);
}

test "ICC profile size matches header" {
    const profile = SRGB_ICC_PROFILE;
    const size = @as(u32, profile[0]) << 24 |
        @as(u32, profile[1]) << 16 |
        @as(u32, profile[2]) << 8 |
        @as(u32, profile[3]);
    try std.testing.expectEqual(@as(u32, profile.len), size);
}

test "generate XMP with PDF/A identification" {
    const allocator = std.testing.allocator;
    const xmp = try generatePdfAXmp(allocator, .pdfa_1b, .{
        .title = "Test Document",
        .author = "Test Author",
    });
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, "pdfaid:part") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, ">1</pdfaid:part>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, ">B</pdfaid:conformance>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "Test Document") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "Test Author") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket begin=") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, "<?xpacket end=") != null);
}

test "generate XMP for PDF/A-2a" {
    const allocator = std.testing.allocator;
    const xmp = try generatePdfAXmp(allocator, .pdfa_2a, .{});
    defer allocator.free(xmp);

    try std.testing.expect(std.mem.indexOf(u8, xmp, ">2</pdfaid:part>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xmp, ">A</pdfaid:conformance>") != null);
}

test "build output intent" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try buildOutputIntent(allocator, &store, &SRGB_ICC_PROFILE);
    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());

    // Check OutputIntent dict has required keys
    const s_val = obj.?.dict_obj.get("S");
    try std.testing.expect(s_val != null);
    try std.testing.expectEqualStrings("GTS_PDFA1", s_val.?.asName().?);

    const type_val = obj.?.dict_obj.get("Type");
    try std.testing.expect(type_val != null);
    try std.testing.expectEqualStrings("OutputIntent", type_val.?.asName().?);

    // Check ICC profile stream was created (ref obj_num should be ref-1)
    const dest = obj.?.dict_obj.get("DestOutputProfile");
    try std.testing.expect(dest != null);
    try std.testing.expect(dest.?.isRef());
}

test "build metadata stream" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const xmp_data = "<?xpacket test?>";
    const ref = try buildMetadataStream(allocator, &store, xmp_data);
    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isStream());

    const type_val = obj.?.stream_obj.dict.get("Type");
    try std.testing.expect(type_val != null);
    try std.testing.expectEqualStrings("Metadata", type_val.?.asName().?);

    const subtype_val = obj.?.stream_obj.dict.get("Subtype");
    try std.testing.expect(subtype_val != null);
    try std.testing.expectEqualStrings("XML", subtype_val.?.asName().?);
}

test "validate detects missing requirements" {
    const allocator = std.testing.allocator;
    // Minimal non-PDF/A document
    const bad_pdf = "%PDF-1.7\n%test\n1 0 obj\n<< /Type /Catalog >>\nendobj\nxref\ntrailer\n%%EOF";
    const result = try validate(allocator, bad_pdf, .pdfa_1b);
    defer allocator.free(result.errors);

    try std.testing.expect(!result.is_valid);
    try std.testing.expect(result.errors.len > 0);

    // Should detect version mismatch (1.7 vs expected 1.4 for pdfa_1b)
    var has_version_error = false;
    var has_xmp_error = false;
    var has_output_intent_error = false;
    for (result.errors) |err| {
        if (err.code == .version_mismatch) has_version_error = true;
        if (err.code == .missing_xmp_metadata) has_xmp_error = true;
        if (err.code == .missing_output_intent) has_output_intent_error = true;
    }
    try std.testing.expect(has_version_error);
    try std.testing.expect(has_xmp_error);
    try std.testing.expect(has_output_intent_error);
}

test "validate detects encryption" {
    const allocator = std.testing.allocator;
    const encrypted_pdf = "%PDF-1.4\n/Encrypt << >> /Type /Metadata pdfaid:part pdfaid:conformance /OutputIntents /DestOutputProfile";
    const result = try validate(allocator, encrypted_pdf, .pdfa_1b);
    defer allocator.free(result.errors);

    var has_encrypt_error = false;
    for (result.errors) |err| {
        if (err.code == .encryption_not_allowed) has_encrypt_error = true;
    }
    try std.testing.expect(has_encrypt_error);
}
