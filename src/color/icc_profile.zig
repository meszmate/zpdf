//! Per-object ICC color profile support.
//!
//! This module provides helpers for loading raw ICC profile byte buffers,
//! inspecting their color space from the ICC header, and embedding them as
//! PDF `ICCBased` color space objects that can be referenced by individual
//! images, fills, and strokes.
//!
//! A PDF `ICCBased` color space is written as a two-element array of the
//! form `[/ICCBased N R]` where `N R` is an indirect reference to a stream
//! object whose dictionary carries the number of components (`/N`) and
//! whose body contains the raw ICC profile bytes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const pdfa = @import("../pdfa/pdfa.zig");

/// The device color space a loaded ICC profile describes. These map directly
/// to the color space signature bytes at offset 16..20 of the ICC header.
pub const IccColorSpace = enum {
    rgb,
    cmyk,
    gray,

    /// Number of device components for this color space.
    pub fn numComponents(self: IccColorSpace) u8 {
        return switch (self) {
            .rgb => 3,
            .cmyk => 4,
            .gray => 1,
        };
    }
};

/// A parsed ICC profile, wrapping the raw profile bytes together with
/// metadata extracted from its header.
///
/// The `data` slice is borrowed — it is not copied and not freed by this
/// struct. Callers must keep the backing buffer alive for the lifetime of
/// any PDF object that references this profile.
pub const IccProfile = struct {
    /// Human readable name, used for diagnostics only. Not written to the
    /// PDF output.
    name: []const u8,
    /// Raw ICC profile bytes.
    data: []const u8,
    /// Number of device components described by the profile.
    num_components: u8,
    /// Device color space described by the profile.
    color_space: IccColorSpace,
};

/// Errors that can occur while parsing an ICC profile header.
pub const IccError = error{
    IccProfileTooShort,
    UnsupportedIccColorSpace,
};

/// Parse an ICC profile header and return an `IccProfile` that borrows the
/// input buffer. Only the color space signature at offset 16..20 is decoded;
/// the rest of the profile is treated as opaque bytes.
pub fn loadIccProfile(data: []const u8) IccError!IccProfile {
    // ICC header is 128 bytes long. We only need bytes 16..20 here but we
    // still require the full header to consider the profile well formed.
    if (data.len < 128) return error.IccProfileTooShort;

    const sig = data[16..20];
    const cs: IccColorSpace = if (std.mem.eql(u8, sig, "RGB "))
        .rgb
    else if (std.mem.eql(u8, sig, "CMYK"))
        .cmyk
    else if (std.mem.eql(u8, sig, "GRAY"))
        .gray
    else
        return error.UnsupportedIccColorSpace;

    return .{
        .name = "",
        .data = data,
        .num_components = cs.numComponents(),
        .color_space = cs,
    };
}

/// Same as `loadIccProfile` but also sets the display name.
pub fn loadIccProfileNamed(name: []const u8, data: []const u8) IccError!IccProfile {
    var p = try loadIccProfile(data);
    p.name = name;
    return p;
}

/// Embed an ICC profile into the given object store as an `ICCBased` color
/// space.
///
/// Returns a reference to an array object `[/ICCBased streamRef]` that can
/// be used wherever a PDF color space is expected (e.g. as the value of an
/// image's `/ColorSpace` entry or as a resource in a page's `/ColorSpace`
/// subdictionary).
pub fn embedIccProfile(
    allocator: Allocator,
    store: *ObjectStore,
    profile: IccProfile,
) !Ref {
    // 1. Stream object containing the raw ICC profile bytes.
    const stream_ref = try store.allocate();
    {
        var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try stream_dict.put(allocator, "N", types.pdfInt(@intCast(profile.num_components)));
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(profile.data.len)));

        // Optional /Alternate hint — aids viewers that cannot consume the
        // profile directly.
        const alt_name: []const u8 = switch (profile.color_space) {
            .rgb => "DeviceRGB",
            .cmyk => "DeviceCMYK",
            .gray => "DeviceGray",
        };
        try stream_dict.put(allocator, "Alternate", types.pdfName(alt_name));

        store.put(stream_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = profile.data,
        } });
    }

    // 2. Array object [/ICCBased streamRef] forming the color space value.
    const cs_ref = try store.allocate();
    {
        var arr = types.pdfArray(allocator);
        try arr.array_obj.append(types.pdfName("ICCBased"));
        try arr.array_obj.append(types.pdfRef(stream_ref.obj_num, stream_ref.gen_num));
        store.put(cs_ref, arr);
    }

    return cs_ref;
}

/// A ready-to-use sRGB ICC profile, reusing the minimal profile bytes that
/// ship with the PDF/A module. The `data` slice points into the
/// comptime-generated `pdfa.SRGB_ICC_PROFILE` storage, so it is valid for
/// the lifetime of the program.
pub const SRGB_PROFILE: IccProfile = .{
    .name = "sRGB IEC61966-2.1",
    .data = &pdfa.SRGB_ICC_PROFILE,
    .num_components = 3,
    .color_space = .rgb,
};

// -- Tests --

test "loadIccProfile detects RGB" {
    const profile = try loadIccProfile(&pdfa.SRGB_ICC_PROFILE);
    try std.testing.expectEqual(IccColorSpace.rgb, profile.color_space);
    try std.testing.expectEqual(@as(u8, 3), profile.num_components);
}

test "loadIccProfile rejects short buffers" {
    const short: [16]u8 = [_]u8{0} ** 16;
    try std.testing.expectError(error.IccProfileTooShort, loadIccProfile(&short));
}

test "loadIccProfile rejects unknown color space" {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'X';
    buf[17] = 'Y';
    buf[18] = 'Z';
    buf[19] = ' ';
    try std.testing.expectError(error.UnsupportedIccColorSpace, loadIccProfile(&buf));
}

test "loadIccProfile detects CMYK" {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'C';
    buf[17] = 'M';
    buf[18] = 'Y';
    buf[19] = 'K';
    const profile = try loadIccProfile(&buf);
    try std.testing.expectEqual(IccColorSpace.cmyk, profile.color_space);
    try std.testing.expectEqual(@as(u8, 4), profile.num_components);
}

test "loadIccProfile detects Gray" {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'G';
    buf[17] = 'R';
    buf[18] = 'A';
    buf[19] = 'Y';
    const profile = try loadIccProfile(&buf);
    try std.testing.expectEqual(IccColorSpace.gray, profile.color_space);
    try std.testing.expectEqual(@as(u8, 1), profile.num_components);
}

test "embedIccProfile writes ICCBased array and stream" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const cs_ref = try embedIccProfile(allocator, &store, SRGB_PROFILE);
    var cs_obj = store.get(cs_ref).?;
    try std.testing.expect(cs_obj.isArray());

    const arr = cs_obj.asArray().?;
    try std.testing.expectEqual(@as(usize, 2), arr.list.items.len);
    try std.testing.expectEqualStrings("ICCBased", arr.list.items[0].asName().?);

    const stream_ref = arr.list.items[1].asRef().?;
    var stream_obj = store.get(stream_ref).?;
    try std.testing.expect(stream_obj.isStream());

    const n_val = stream_obj.stream_obj.dict.get("N").?;
    try std.testing.expectEqual(@as(i64, 3), n_val.asInt().?);

    const alt_val = stream_obj.stream_obj.dict.get("Alternate").?;
    try std.testing.expectEqualStrings("DeviceRGB", alt_val.asName().?);

    try std.testing.expectEqual(@as(usize, pdfa.SRGB_ICC_PROFILE.len), stream_obj.stream_obj.data.len);
}

test "SRGB_PROFILE matches pdfa bytes" {
    try std.testing.expectEqual(@as(usize, pdfa.SRGB_ICC_PROFILE.len), SRGB_PROFILE.data.len);
    try std.testing.expectEqual(IccColorSpace.rgb, SRGB_PROFILE.color_space);
}
