const std = @import("std");
const zpdf = @import("zpdf");

test "SRGB profile has valid header" {
    const profile = zpdf.SRGB_ICC_PROFILE;
    try std.testing.expectEqual(zpdf.IccColorSpace.rgb, profile.color_space);
    try std.testing.expectEqual(@as(u8, 3), profile.num_components);
    try std.testing.expect(profile.data.len >= 128);
    try std.testing.expectEqualStrings("acsp", profile.data[36..40]);
}

test "loadIccProfile returns RGB for sRGB bytes" {
    const profile = try zpdf.loadIccProfile(zpdf.SRGB_ICC_PROFILE.data);
    try std.testing.expectEqual(zpdf.IccColorSpace.rgb, profile.color_space);
    try std.testing.expectEqual(@as(u8, 3), profile.num_components);
    try std.testing.expectEqual(zpdf.SRGB_ICC_PROFILE.data.len, profile.data.len);
}

test "loadIccProfile rejects buffers shorter than the header" {
    const tiny: [10]u8 = [_]u8{0} ** 10;
    try std.testing.expectError(error.IccProfileTooShort, zpdf.loadIccProfile(&tiny));
}

test "loadIccProfile rejects unknown color space signatures" {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'L';
    buf[17] = 'a';
    buf[18] = 'b';
    buf[19] = ' ';
    try std.testing.expectError(error.UnsupportedIccColorSpace, zpdf.loadIccProfile(&buf));
}

test "loadIccProfile recognises CMYK profile signature" {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'C';
    buf[17] = 'M';
    buf[18] = 'Y';
    buf[19] = 'K';
    const profile = try zpdf.loadIccProfile(&buf);
    try std.testing.expectEqual(zpdf.IccColorSpace.cmyk, profile.color_space);
    try std.testing.expectEqual(@as(u8, 4), profile.num_components);
}

test "loadIccProfile recognises Gray profile signature" {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'G';
    buf[17] = 'R';
    buf[18] = 'A';
    buf[19] = 'Y';
    const profile = try zpdf.loadIccProfile(&buf);
    try std.testing.expectEqual(zpdf.IccColorSpace.gray, profile.color_space);
    try std.testing.expectEqual(@as(u8, 1), profile.num_components);
}

test "IccColorSpace.numComponents mapping" {
    try std.testing.expectEqual(@as(u8, 3), zpdf.IccColorSpace.rgb.numComponents());
    try std.testing.expectEqual(@as(u8, 4), zpdf.IccColorSpace.cmyk.numComponents());
    try std.testing.expectEqual(@as(u8, 1), zpdf.IccColorSpace.gray.numComponents());
}

test "embedIccProfile produces [/ICCBased streamRef] array" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const cs_ref = try zpdf.embedIccProfile(allocator, &store, zpdf.SRGB_ICC_PROFILE);
    var cs_obj = store.get(cs_ref).?;
    try std.testing.expect(cs_obj.isArray());

    const arr = cs_obj.asArray().?;
    try std.testing.expectEqual(@as(usize, 2), arr.list.items.len);
    try std.testing.expectEqualStrings("ICCBased", arr.list.items[0].asName().?);
    try std.testing.expect(arr.list.items[1].isRef());
}

test "embedIccProfile stream carries raw ICC bytes and /N entry" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const cs_ref = try zpdf.embedIccProfile(allocator, &store, zpdf.SRGB_ICC_PROFILE);
    var cs_obj = store.get(cs_ref).?;
    const stream_ref = cs_obj.asArray().?.list.items[1].asRef().?;
    var stream_obj = store.get(stream_ref).?;
    try std.testing.expect(stream_obj.isStream());

    const n_val = stream_obj.stream_obj.dict.get("N").?;
    try std.testing.expectEqual(@as(i64, 3), n_val.asInt().?);

    const length_val = stream_obj.stream_obj.dict.get("Length").?;
    try std.testing.expectEqual(
        @as(i64, @intCast(zpdf.SRGB_ICC_PROFILE.data.len)),
        length_val.asInt().?,
    );

    try std.testing.expectEqual(
        zpdf.SRGB_ICC_PROFILE.data.len,
        stream_obj.stream_obj.data.len,
    );
    try std.testing.expectEqualSlices(
        u8,
        zpdf.SRGB_ICC_PROFILE.data,
        stream_obj.stream_obj.data,
    );
}

test "embedIccProfile uses DeviceCMYK alternate for CMYK profiles" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[16] = 'C';
    buf[17] = 'M';
    buf[18] = 'Y';
    buf[19] = 'K';
    const profile = try zpdf.loadIccProfile(&buf);

    const cs_ref = try zpdf.embedIccProfile(allocator, &store, profile);
    var cs_obj = store.get(cs_ref).?;
    const stream_ref = cs_obj.asArray().?.list.items[1].asRef().?;
    var stream_obj = store.get(stream_ref).?;

    const n_val = stream_obj.stream_obj.dict.get("N").?;
    try std.testing.expectEqual(@as(i64, 4), n_val.asInt().?);

    const alt_val = stream_obj.stream_obj.dict.get("Alternate").?;
    try std.testing.expectEqualStrings("DeviceCMYK", alt_val.asName().?);
}

test "multiple embeds allocate distinct object numbers" {
    const allocator = std.testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const a = try zpdf.embedIccProfile(allocator, &store, zpdf.SRGB_ICC_PROFILE);
    const b = try zpdf.embedIccProfile(allocator, &store, zpdf.SRGB_ICC_PROFILE);
    try std.testing.expect(a.obj_num != b.obj_num);
    try std.testing.expectEqual(@as(usize, 4), store.count());
}
