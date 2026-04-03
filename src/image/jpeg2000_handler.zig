const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Ref = core.Ref;
const PdfObject = core.PdfObject;
const image_embedder = @import("image_embedder.zig");
const ImageHandle = image_embedder.ImageHandle;
const ImageFormat = image_embedder.ImageFormat;

/// JP2 file format signature box: 12-byte box with type 'jP  ' followed by 0x0D0A870A.
const jp2_signature_box = [_]u8{
    0x00, 0x00, 0x00, 0x0C, // box length = 12
    0x6A, 0x50, 0x20, 0x20, // box type = 'jP  '
    0x0D, 0x0A, 0x87, 0x0A, // signature content
};

/// J2K raw codestream SOC marker.
const j2k_soc_marker = [_]u8{ 0xFF, 0x4F };

/// SIZ marker code (required after SOC in a J2K codestream).
const siz_marker = [_]u8{ 0xFF, 0x51 };

/// Information extracted from a JPEG 2000 header.
pub const Jpeg2000Info = struct {
    width: u32,
    height: u32,
    num_components: u16,
    bits_per_component: u8,
    is_jp2: bool,
};

pub const Jpeg2000Error = error{
    InvalidJpeg2000,
    UnsupportedJpeg2000,
    UnexpectedEndOfData,
};

/// Read a big-endian u32 from a 4-byte slice.
fn readU32(data: []const u8) u32 {
    return @as(u32, data[0]) << 24 |
        @as(u32, data[1]) << 16 |
        @as(u32, data[2]) << 8 |
        @as(u32, data[3]);
}

/// Read a big-endian u16 from a 2-byte slice.
fn readU16(data: []const u8) u16 {
    return @as(u16, data[0]) << 8 | @as(u16, data[1]);
}

/// Parse a JPEG 2000 file (JP2 container or raw J2K codestream) to extract
/// image dimensions, component count, and bits per component.
///
/// For JP2 files, this scans the box structure for the Image Header (ihdr) box.
/// For raw J2K codestreams, this parses the SIZ marker that must follow SOC.
pub fn parseJpeg2000(data: []const u8) Jpeg2000Error!Jpeg2000Info {
    if (data.len < 2) return Jpeg2000Error.InvalidJpeg2000;

    // Check for JP2 container format (signature box)
    if (data.len >= 12 and std.mem.eql(u8, data[0..12], &jp2_signature_box)) {
        return parseJp2Container(data);
    }

    // Check for raw J2K codestream (starts with SOC marker 0xFF4F)
    if (data[0] == 0xFF and data[1] == 0x4F) {
        return parseJ2kCodestream(data, false);
    }

    return Jpeg2000Error.InvalidJpeg2000;
}

/// Parse a JP2 container by scanning its box structure for the ihdr box.
fn parseJp2Container(data: []const u8) Jpeg2000Error!Jpeg2000Info {
    var offset: usize = 0;

    while (offset + 8 <= data.len) {
        if (offset + 4 > data.len) return Jpeg2000Error.UnexpectedEndOfData;
        const box_len_raw = readU32(data[offset .. offset + 4]);
        const box_type = data[offset + 4 .. offset + 8];

        var box_len: usize = @as(usize, box_len_raw);

        // Handle extended box length (box_len == 1 means 8-byte extended length follows)
        if (box_len_raw == 1) {
            if (offset + 16 > data.len) return Jpeg2000Error.UnexpectedEndOfData;
            // Read the high 32 bits; for practical file sizes they should be zero
            const high = readU32(data[offset + 8 .. offset + 12]);
            const low = readU32(data[offset + 12 .. offset + 16]);
            if (high != 0) return Jpeg2000Error.UnsupportedJpeg2000;
            box_len = @as(usize, low);
        }

        // box_len == 0 means the box extends to end of file
        if (box_len_raw == 0) {
            box_len = data.len - offset;
        }

        if (box_len < 8) return Jpeg2000Error.InvalidJpeg2000;

        // Check for ihdr box (Image Header Box) - can appear at top level
        if (std.mem.eql(u8, box_type, "ihdr")) {
            return parseIhdrBox(data, offset, box_len);
        }

        // Check for jp2h superbox (JP2 Header Box) - contains ihdr as sub-box
        if (std.mem.eql(u8, box_type, "jp2h")) {
            const header_size: usize = if (box_len_raw == 1) 16 else 8;
            const box_end = offset + box_len;
            var inner_offset = offset + header_size;
            while (inner_offset + 8 <= box_end) {
                const inner_len_raw = readU32(data[inner_offset .. inner_offset + 4]);
                const inner_type = data[inner_offset + 4 .. inner_offset + 8];
                var inner_len: usize = @as(usize, inner_len_raw);
                if (inner_len_raw == 0) {
                    inner_len = box_end - inner_offset;
                }
                if (inner_len < 8) break;
                if (std.mem.eql(u8, inner_type, "ihdr")) {
                    return parseIhdrBox(data, inner_offset, inner_len);
                }
                inner_offset += inner_len;
            }
        }

        // Check for jp2c box (Contiguous Codestream Box) as fallback
        if (std.mem.eql(u8, box_type, "jp2c")) {
            const header_size: usize = if (box_len_raw == 1) 16 else 8;
            if (offset + header_size + 2 > data.len) return Jpeg2000Error.UnexpectedEndOfData;
            const codestream_start = offset + header_size;
            // The codestream should start with SOC
            if (data[codestream_start] == 0xFF and data[codestream_start + 1] == 0x4F) {
                return parseJ2kCodestream(data[codestream_start..], true);
            }
        }

        offset += box_len;
    }

    return Jpeg2000Error.InvalidJpeg2000;
}

/// Parse the ihdr (Image Header Box) to extract dimensions and component info.
/// The ihdr box payload is 14 bytes:
///   - 4 bytes: height
///   - 4 bytes: width
///   - 2 bytes: number of components
///   - 1 byte: bits per component (value is bpc - 1, with sign bit)
///   - 1 byte: compression type
///   - 1 byte: colorspace unknown flag
///   - 1 byte: intellectual property flag
fn parseIhdrBox(data: []const u8, offset: usize, box_len: usize) Jpeg2000Error!Jpeg2000Info {
    const header_size: usize = 8;
    if (offset + header_size + 14 > data.len or box_len < header_size + 14) {
        return Jpeg2000Error.UnexpectedEndOfData;
    }

    const payload = offset + header_size;
    const height = readU32(data[payload .. payload + 4]);
    const width = readU32(data[payload + 4 .. payload + 8]);
    const num_components = readU16(data[payload + 8 .. payload + 10]);
    const bpc_raw = data[payload + 10];

    if (width == 0 or height == 0 or num_components == 0) {
        return Jpeg2000Error.InvalidJpeg2000;
    }

    // bpc_raw: bit 7 is sign flag, bits 6-0 are (bit_depth - 1)
    const bits_per_component: u8 = (bpc_raw & 0x7F) + 1;

    return Jpeg2000Info{
        .width = width,
        .height = height,
        .num_components = num_components,
        .bits_per_component = bits_per_component,
        .is_jp2 = true,
    };
}

/// Parse a raw J2K codestream starting at SOC, reading the SIZ marker for dimensions.
fn parseJ2kCodestream(data: []const u8, is_jp2: bool) Jpeg2000Error!Jpeg2000Info {
    // Must start with SOC (0xFF4F)
    if (data.len < 4) return Jpeg2000Error.UnexpectedEndOfData;
    if (data[0] != 0xFF or data[1] != 0x4F) return Jpeg2000Error.InvalidJpeg2000;

    // SIZ marker must immediately follow SOC
    if (data[2] != 0xFF or data[3] != 0x51) return Jpeg2000Error.InvalidJpeg2000;

    if (data.len < 4 + 2) return Jpeg2000Error.UnexpectedEndOfData;
    const siz_len = readU16(data[4..6]);

    // SIZ marker segment minimum length: 2 (Lsiz) + 2 (Rsiz) + 4*4 (Xsiz,Ysiz,XOsiz,YOsiz)
    // + 4*2 (XTsiz,YTsiz,XTOsiz,YTOsiz) + 2 (Csiz) = 38 bytes
    if (siz_len < 38) return Jpeg2000Error.InvalidJpeg2000;
    if (data.len < 4 + @as(usize, siz_len)) return Jpeg2000Error.UnexpectedEndOfData;

    // Fields within SIZ (offsets relative to after the marker code 0xFF51):
    // [0..2]  Lsiz
    // [2..4]  Rsiz (capabilities)
    // [4..8]  Xsiz (image width including offset)
    // [8..12] Ysiz (image height including offset)
    // [12..16] XOsiz (horizontal offset)
    // [16..20] YOsiz (vertical offset)
    // [20..24] XTsiz
    // [24..28] YTsiz
    // [28..32] XTOsiz
    // [32..36] YTOsiz
    // [36..38] Csiz (number of components)
    // Then for each component: 3 bytes (Ssiz, XRsiz, YRsiz)

    const siz_base: usize = 4; // after marker code
    const xsiz = readU32(data[siz_base + 4 .. siz_base + 8]);
    const ysiz = readU32(data[siz_base + 8 .. siz_base + 12]);
    const xo_siz = readU32(data[siz_base + 12 .. siz_base + 16]);
    const yo_siz = readU32(data[siz_base + 16 .. siz_base + 20]);
    const csiz = readU16(data[siz_base + 36 .. siz_base + 38]);

    if (xsiz <= xo_siz or ysiz <= yo_siz or csiz == 0) {
        return Jpeg2000Error.InvalidJpeg2000;
    }

    const width = xsiz - xo_siz;
    const height = ysiz - yo_siz;

    // Read bits per component from first component's Ssiz field
    if (data.len < siz_base + 38 + 3) return Jpeg2000Error.UnexpectedEndOfData;
    const ssiz = data[siz_base + 38];
    const bits_per_component: u8 = (ssiz & 0x7F) + 1;

    return Jpeg2000Info{
        .width = width,
        .height = height,
        .num_components = csiz,
        .bits_per_component = bits_per_component,
        .is_jp2 = is_jp2,
    };
}

/// Color space for the PDF based on component count.
fn colorSpaceForComponents(num_components: u16) []const u8 {
    return switch (num_components) {
        1 => "DeviceGray",
        3 => "DeviceRGB",
        4 => "DeviceCMYK",
        else => "DeviceRGB",
    };
}

/// Create a PDF image XObject for a JPEG 2000 image.
/// The raw JPEG 2000 data is stored as the stream with /JPXDecode filter.
/// PDF viewers handle decompression of JPEG 2000 data natively.
pub fn embedJpeg2000(allocator: Allocator, store: *ObjectStore, data: []const u8) !ImageHandle {
    const info = try parseJpeg2000(data);

    const ref = try store.allocate();

    var dict: std.StringHashMapUnmanaged(PdfObject) = .{};
    try dict.put(allocator, "Type", core.pdfName("XObject"));
    try dict.put(allocator, "Subtype", core.pdfName("Image"));
    try dict.put(allocator, "Width", core.pdfInt(@intCast(info.width)));
    try dict.put(allocator, "Height", core.pdfInt(@intCast(info.height)));
    try dict.put(allocator, "ColorSpace", core.pdfName(colorSpaceForComponents(info.num_components)));
    try dict.put(allocator, "BitsPerComponent", core.pdfInt(@intCast(info.bits_per_component)));
    try dict.put(allocator, "Filter", core.pdfName("JPXDecode"));
    try dict.put(allocator, "Length", core.pdfInt(@intCast(data.len)));

    const stream_obj = PdfObject{ .stream_obj = .{
        .dict = dict,
        .data = data,
    } };

    store.put(ref, stream_obj);

    return ImageHandle{
        .ref = ref,
        .width = info.width,
        .height = info.height,
        .format = .jpeg2000,
    };
}

// -- Tests --

test "parseJpeg2000: invalid data" {
    const result = parseJpeg2000(&[_]u8{ 0x00, 0x00 });
    try std.testing.expectError(Jpeg2000Error.InvalidJpeg2000, result);
}

test "parseJpeg2000: too short" {
    const result = parseJpeg2000(&[_]u8{0xFF});
    try std.testing.expectError(Jpeg2000Error.InvalidJpeg2000, result);
}

test "parseJpeg2000: valid J2K codestream with SIZ marker" {
    // SOC + SIZ marker with minimal valid data
    var data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ marker
        0x00, 0x29, // Lsiz = 41 (38 + 3 bytes for one component)
        0x00, 0x00, // Rsiz (capabilities)
        0x00, 0x00, 0x01, 0x00, // Xsiz = 256
        0x00, 0x00, 0x00, 0x80, // Ysiz = 128
        0x00, 0x00, 0x00, 0x00, // XOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YOsiz = 0
        0x00, 0x00, 0x01, 0x00, // XTsiz = 256
        0x00, 0x00, 0x00, 0x80, // YTsiz = 128
        0x00, 0x00, 0x00, 0x00, // XTOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YTOsiz = 0
        0x00, 0x03, // Csiz = 3 components
        0x07, 0x01, 0x01, // Component 0: Ssiz=7 (8 bits), XRsiz=1, YRsiz=1
        0x07, 0x01, 0x01, // Component 1
        0x07, 0x01, 0x01, // Component 2
    };

    const info = try parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 256), info.width);
    try std.testing.expectEqual(@as(u32, 128), info.height);
    try std.testing.expectEqual(@as(u16, 3), info.num_components);
    try std.testing.expectEqual(@as(u8, 8), info.bits_per_component);
    try std.testing.expectEqual(false, info.is_jp2);
}

test "parseJpeg2000: valid JP2 container with ihdr box" {
    // JP2 signature box + ftyp box + jp2h box containing ihdr box
    const data = [_]u8{
        // Signature box (12 bytes)
        0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A,
        // File type box (20 bytes)
        0x00, 0x00, 0x00, 0x14, // box length = 20
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x6A, 0x70, 0x32, 0x20, // brand = 'jp2 '
        0x00, 0x00, 0x00, 0x00, // minor version
        0x6A, 0x70, 0x32, 0x20, // compatibility = 'jp2 '
        // JP2 Header superbox (8 + 22 = 30 bytes)
        0x00, 0x00, 0x00, 0x1E, // box length = 30
        0x6A, 0x70, 0x32, 0x68, // 'jp2h'
        // Image Header box (ihdr, 22 bytes: 8 header + 14 payload)
        0x00, 0x00, 0x00, 0x16, // box length = 22
        0x69, 0x68, 0x64, 0x72, // 'ihdr'
        0x00, 0x00, 0x02, 0x00, // height = 512
        0x00, 0x00, 0x04, 0x00, // width = 1024
        0x00, 0x03, // num_components = 3
        0x07, // bpc = 7 -> bits_per_component = 8
        0x07, // compression type (always 7 for JP2)
        0x00, // colorspace unknown
        0x00, // intellectual property
    };

    const info = try parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 1024), info.width);
    try std.testing.expectEqual(@as(u32, 512), info.height);
    try std.testing.expectEqual(@as(u16, 3), info.num_components);
    try std.testing.expectEqual(@as(u8, 8), info.bits_per_component);
    try std.testing.expectEqual(true, info.is_jp2);
}

test "parseJpeg2000: grayscale J2K" {
    var data = [_]u8{
        0xFF, 0x4F, // SOC
        0xFF, 0x51, // SIZ marker
        0x00, 0x27, // Lsiz = 39 (38 + 1*3 = 41... but min is 38 for header)
        0x00, 0x00, // Rsiz
        0x00, 0x00, 0x00, 0x40, // Xsiz = 64
        0x00, 0x00, 0x00, 0x20, // Ysiz = 32
        0x00, 0x00, 0x00, 0x00, // XOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YOsiz = 0
        0x00, 0x00, 0x00, 0x40, // XTsiz = 64
        0x00, 0x00, 0x00, 0x20, // YTsiz = 32
        0x00, 0x00, 0x00, 0x00, // XTOsiz = 0
        0x00, 0x00, 0x00, 0x00, // YTOsiz = 0
        0x00, 0x01, // Csiz = 1 component (grayscale)
        0x07, 0x01, 0x01, // Component 0: 8 bits
    };

    const info = try parseJpeg2000(&data);
    try std.testing.expectEqual(@as(u32, 64), info.width);
    try std.testing.expectEqual(@as(u32, 32), info.height);
    try std.testing.expectEqual(@as(u16, 1), info.num_components);
    try std.testing.expectEqual(@as(u8, 8), info.bits_per_component);
}
