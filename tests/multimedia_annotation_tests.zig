const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

test "SoundEncoding maps to PDF names" {
    try testing.expectEqualStrings("Raw", zpdf.SoundEncoding.raw.nameValue());
    try testing.expectEqualStrings("Signed", zpdf.SoundEncoding.signed.nameValue());
    try testing.expectEqualStrings("muLaw", zpdf.SoundEncoding.mu_law.nameValue());
    try testing.expectEqualStrings("ALaw", zpdf.SoundEncoding.a_law.nameValue());
}

test "MediaActivation maps to PDF condition names" {
    try testing.expectEqualStrings("PageOpen", zpdf.MediaActivation.page_open.conditionName());
    try testing.expectEqualStrings("Click", zpdf.MediaActivation.click.conditionName());
    try testing.expectEqualStrings("Explicit", zpdf.MediaActivation.explicit.conditionName());
}

test "buildSoundAnnotation: dict + embedded stream" {
    const allocator = testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try zpdf.buildSoundAnnotation(allocator, &store, .{
        .rect = .{ .x = 10, .y = 20, .width = 30, .height = 30 },
        .sound_data = "AUDIOBYTES",
        .sample_rate = 48000,
        .channels = 2,
        .bits_per_sample = 16,
        .encoding = .signed,
    });
    defer ann.deinit(allocator);

    try testing.expect(ann.isDict());
    try testing.expectEqualStrings("Annot", ann.dict_obj.get("Type").?.asName().?);
    try testing.expectEqualStrings("Sound", ann.dict_obj.get("Subtype").?.asName().?);
    try testing.expectEqualStrings("Speaker", ann.dict_obj.get("Name").?.asName().?);

    const sound_ref_obj = ann.dict_obj.get("Sound").?;
    try testing.expect(sound_ref_obj.isRef());

    // One indirect object: the sound stream.
    try testing.expectEqual(@as(usize, 1), store.count());

    var stream = store.get(sound_ref_obj.asRef().?).?;
    try testing.expect(stream.isStream());
    try testing.expectEqualStrings("Sound", stream.stream_obj.dict.get("Type").?.asName().?);
    try testing.expectEqual(@as(i64, 48000), stream.stream_obj.dict.get("R").?.asInt().?);
    try testing.expectEqual(@as(i64, 2), stream.stream_obj.dict.get("C").?.asInt().?);
    try testing.expectEqual(@as(i64, 16), stream.stream_obj.dict.get("B").?.asInt().?);
    try testing.expectEqualStrings("Signed", stream.stream_obj.dict.get("E").?.asName().?);
    try testing.expectEqualStrings("AUDIOBYTES", stream.stream_obj.data);
}

test "buildSoundAnnotation: custom name override" {
    const allocator = testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try zpdf.buildSoundAnnotation(allocator, &store, .{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .sound_data = "x",
        .sample_rate = 8000,
        .channels = 1,
        .bits_per_sample = 8,
        .encoding = .mu_law,
        .name = "Mic",
    });
    defer ann.deinit(allocator);

    try testing.expectEqualStrings("Mic", ann.dict_obj.get("Name").?.asName().?);
}

test "buildScreenAnnotation: creates media chain" {
    const allocator = testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try zpdf.buildScreenAnnotation(allocator, &store, .{
        .rect = .{ .x = 100, .y = 200, .width = 320, .height = 240 },
        .media_data = "MP4BYTES",
        .mime_type = "video/mp4",
        .activation = .click,
        .title = "Clip",
    });
    defer ann.deinit(allocator);

    try testing.expect(ann.isDict());
    try testing.expectEqualStrings("Screen", ann.dict_obj.get("Subtype").?.asName().?);
    try testing.expectEqualStrings("Clip", ann.dict_obj.get("T").?.asString().?);

    // stream + filespec + mediaclip + rendition = 4
    try testing.expectEqual(@as(usize, 4), store.count());

    const action = ann.dict_obj.get("A").?;
    try testing.expect(action.isDict());
    try testing.expectEqualStrings("Rendition", action.dict_obj.get("S").?.asName().?);
    try testing.expectEqualStrings("Click", action.dict_obj.get("T").?.asString().?);

    const rend_ref = action.dict_obj.get("R").?.asRef().?;
    var rend = store.get(rend_ref).?;
    try testing.expect(rend.isDict());
    try testing.expectEqualStrings("Rendition", rend.dict_obj.get("Type").?.asName().?);
    try testing.expectEqualStrings("MR", rend.dict_obj.get("S").?.asName().?);
}

test "buildRichMediaAnnotation: embedded asset and settings" {
    const allocator = testing.allocator;
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try zpdf.buildRichMediaAnnotation(allocator, &store, .{
        .rect = .{ .x = 50, .y = 50, .width = 400, .height = 300 },
        .media_data = "SWFPAYLOAD",
        .mime_type = "application/x-shockwave-flash",
    });
    defer ann.deinit(allocator);

    try testing.expectEqualStrings("RichMedia", ann.dict_obj.get("Subtype").?.asName().?);

    // stream + filespec = 2
    try testing.expectEqual(@as(usize, 2), store.count());

    const content = ann.dict_obj.get("RichMediaContent").?;
    try testing.expect(content.isDict());
    const assets = content.dict_obj.get("Assets").?;
    try testing.expect(assets.isDict());
    const names = assets.dict_obj.get("Names").?;
    try testing.expect(names.isArray());
    try testing.expectEqual(@as(usize, 2), names.array_obj.list.items.len);

    const settings = ann.dict_obj.get("RichMediaSettings").?;
    try testing.expect(settings.isDict());
    const activation = settings.dict_obj.get("Activation").?;
    try testing.expect(activation.isDict());
}
