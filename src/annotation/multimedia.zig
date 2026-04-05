const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const annotation = @import("annotation.zig");
const Rect = annotation.Rect;

/// Encoding format used by a PDF sound stream.
pub const SoundEncoding = enum {
    raw,
    signed,
    mu_law,
    a_law,

    /// Returns the PDF name used for the /E entry in a Sound stream.
    pub fn nameValue(self: SoundEncoding) []const u8 {
        return switch (self) {
            .raw => "Raw",
            .signed => "Signed",
            .mu_law => "muLaw",
            .a_law => "ALaw",
        };
    }
};

/// Describes a Sound annotation and its embedded audio data.
pub const SoundAnnotation = struct {
    rect: Rect,
    sound_data: []const u8,
    sample_rate: u32,
    channels: u8 = 1,
    bits_per_sample: u8 = 8,
    encoding: SoundEncoding = .raw,
    name: []const u8 = "Speaker",
};

/// Controls when a Screen annotation's media should be activated.
pub const MediaActivation = enum {
    page_open,
    click,
    explicit,

    /// Returns the PDF name used in a rendition action for this activation mode.
    pub fn conditionName(self: MediaActivation) []const u8 {
        // PDF rendition action operation codes:
        //   0 = play, 1 = stop, 2 = pause, 3 = resume, 4 = play/resume
        // For activation we map to human-readable names on the /T entry.
        return switch (self) {
            .page_open => "PageOpen",
            .click => "Click",
            .explicit => "Explicit",
        };
    }
};

/// Describes a Screen annotation that plays an embedded media clip.
pub const ScreenAnnotation = struct {
    rect: Rect,
    media_data: []const u8,
    mime_type: []const u8,
    activation: MediaActivation = .click,
    title: []const u8 = "Media",
};

/// Describes a RichMedia annotation (PDF 2.0 / Adobe extension) with embedded media.
pub const RichMediaAnnotation = struct {
    rect: Rect,
    media_data: []const u8,
    mime_type: []const u8,
};

fn putRect(allocator: Allocator, dict: *PdfObject, rect: Rect) !void {
    var rect_arr = types.pdfArray(allocator);
    try rect_arr.array_obj.append(types.pdfReal(rect.x));
    try rect_arr.array_obj.append(types.pdfReal(rect.y));
    try rect_arr.array_obj.append(types.pdfReal(rect.x + rect.width));
    try rect_arr.array_obj.append(types.pdfReal(rect.y + rect.height));
    try dict.dict_obj.put(allocator, "Rect", rect_arr);
}

/// Builds a Sound annotation dictionary and the embedded sound stream.
///
/// The returned PdfObject is the annotation dictionary. An indirect sound
/// stream object is allocated in `store` and referenced from the dict's
/// /Sound entry.
pub fn buildSoundAnnotation(
    allocator: Allocator,
    store: *ObjectStore,
    sound: SoundAnnotation,
) !PdfObject {
    // 1. Create the embedded sound stream object.
    const sound_ref = try store.allocate();
    {
        var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try stream_dict.put(allocator, "Type", types.pdfName("Sound"));
        try stream_dict.put(allocator, "R", types.pdfInt(@intCast(sound.sample_rate)));
        try stream_dict.put(allocator, "C", types.pdfInt(@intCast(sound.channels)));
        try stream_dict.put(allocator, "B", types.pdfInt(@intCast(sound.bits_per_sample)));
        try stream_dict.put(allocator, "E", types.pdfName(sound.encoding.nameValue()));
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(sound.sound_data.len)));

        store.put(sound_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = sound.sound_data,
        } });
    }

    // 2. Build the annotation dictionary.
    var dict = types.pdfDict(allocator);
    errdefer dict.deinit(allocator);

    try dict.dict_obj.put(allocator, "Type", types.pdfName("Annot"));
    try dict.dict_obj.put(allocator, "Subtype", types.pdfName("Sound"));
    try putRect(allocator, &dict, sound.rect);
    try dict.dict_obj.put(allocator, "Sound", types.pdfRef(sound_ref.obj_num, sound_ref.gen_num));
    try dict.dict_obj.put(allocator, "Name", types.pdfName(sound.name));
    try dict.dict_obj.put(allocator, "F", types.pdfInt(4));

    return dict;
}

/// Builds a Screen annotation with an embedded media rendition.
///
/// Creates:
///   - an EmbeddedFile stream with the media bytes
///   - a Filespec dictionary referencing the stream
///   - a MediaClip / Rendition subtree for playback
///   - the Screen annotation dictionary
pub fn buildScreenAnnotation(
    allocator: Allocator,
    store: *ObjectStore,
    screen: ScreenAnnotation,
) !PdfObject {
    // 1. Embedded file stream for the media data.
    const media_stream_ref = try store.allocate();
    {
        var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try stream_dict.put(allocator, "Type", types.pdfName("EmbeddedFile"));
        try stream_dict.put(allocator, "Subtype", types.pdfName(screen.mime_type));
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(screen.media_data.len)));

        var params_dict = types.pdfDict(allocator);
        try params_dict.dict_obj.put(allocator, "Size", types.pdfInt(@intCast(screen.media_data.len)));
        try stream_dict.put(allocator, "Params", params_dict);

        store.put(media_stream_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = screen.media_data,
        } });
    }

    // 2. Filespec dictionary referencing the embedded media.
    const filespec_ref = try store.allocate();
    {
        var filespec = types.pdfDict(allocator);
        try filespec.dict_obj.put(allocator, "Type", types.pdfName("Filespec"));
        try filespec.dict_obj.put(allocator, "F", types.pdfString(screen.title));
        try filespec.dict_obj.put(allocator, "UF", types.pdfString(screen.title));

        var ef_dict = types.pdfDict(allocator);
        try ef_dict.dict_obj.put(allocator, "F", types.pdfRef(media_stream_ref.obj_num, media_stream_ref.gen_num));
        try filespec.dict_obj.put(allocator, "EF", ef_dict);

        store.put(filespec_ref, filespec);
    }

    // 3. MediaClip dictionary (/Type /MediaClip /S /MCD).
    const media_clip_ref = try store.allocate();
    {
        var clip = types.pdfDict(allocator);
        try clip.dict_obj.put(allocator, "Type", types.pdfName("MediaClip"));
        try clip.dict_obj.put(allocator, "S", types.pdfName("MCD"));
        try clip.dict_obj.put(allocator, "N", types.pdfString(screen.title));
        try clip.dict_obj.put(allocator, "CT", types.pdfString(screen.mime_type));
        try clip.dict_obj.put(allocator, "D", types.pdfRef(filespec_ref.obj_num, filespec_ref.gen_num));

        // Permissions dict: allow temporary file creation for playback.
        var p_dict = types.pdfDict(allocator);
        try p_dict.dict_obj.put(allocator, "TF", types.pdfString("TEMPALWAYS"));
        try clip.dict_obj.put(allocator, "P", p_dict);

        store.put(media_clip_ref, clip);
    }

    // 4. Rendition dictionary (/Type /Rendition /S /MR).
    const rendition_ref = try store.allocate();
    {
        var rend = types.pdfDict(allocator);
        try rend.dict_obj.put(allocator, "Type", types.pdfName("Rendition"));
        try rend.dict_obj.put(allocator, "S", types.pdfName("MR"));
        try rend.dict_obj.put(allocator, "N", types.pdfString(screen.title));
        try rend.dict_obj.put(allocator, "C", types.pdfRef(media_clip_ref.obj_num, media_clip_ref.gen_num));
        store.put(rendition_ref, rend);
    }

    // 5. Screen annotation dictionary with a rendition action.
    var dict = types.pdfDict(allocator);
    errdefer dict.deinit(allocator);

    try dict.dict_obj.put(allocator, "Type", types.pdfName("Annot"));
    try dict.dict_obj.put(allocator, "Subtype", types.pdfName("Screen"));
    try putRect(allocator, &dict, screen.rect);
    try dict.dict_obj.put(allocator, "T", types.pdfString(screen.title));
    try dict.dict_obj.put(allocator, "F", types.pdfInt(4));

    // Rendition action attached via /A.
    var action = types.pdfDict(allocator);
    try action.dict_obj.put(allocator, "Type", types.pdfName("Action"));
    try action.dict_obj.put(allocator, "S", types.pdfName("Rendition"));
    // OP 0 = Play
    try action.dict_obj.put(allocator, "OP", types.pdfInt(0));
    try action.dict_obj.put(allocator, "R", types.pdfRef(rendition_ref.obj_num, rendition_ref.gen_num));
    try action.dict_obj.put(allocator, "T", types.pdfString(screen.activation.conditionName()));
    try dict.dict_obj.put(allocator, "A", action);

    return dict;
}

/// Builds a RichMedia annotation with an embedded media asset.
pub fn buildRichMediaAnnotation(
    allocator: Allocator,
    store: *ObjectStore,
    media: RichMediaAnnotation,
) !PdfObject {
    // 1. Embedded file stream for the media bytes.
    const media_stream_ref = try store.allocate();
    {
        var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try stream_dict.put(allocator, "Type", types.pdfName("EmbeddedFile"));
        try stream_dict.put(allocator, "Subtype", types.pdfName(media.mime_type));
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(media.media_data.len)));

        var params_dict = types.pdfDict(allocator);
        try params_dict.dict_obj.put(allocator, "Size", types.pdfInt(@intCast(media.media_data.len)));
        try stream_dict.put(allocator, "Params", params_dict);

        store.put(media_stream_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = media.media_data,
        } });
    }

    // 2. Filespec referencing the stream.
    const filespec_ref = try store.allocate();
    {
        var filespec = types.pdfDict(allocator);
        try filespec.dict_obj.put(allocator, "Type", types.pdfName("Filespec"));
        try filespec.dict_obj.put(allocator, "F", types.pdfString("richmedia"));
        try filespec.dict_obj.put(allocator, "UF", types.pdfString("richmedia"));

        var ef_dict = types.pdfDict(allocator);
        try ef_dict.dict_obj.put(allocator, "F", types.pdfRef(media_stream_ref.obj_num, media_stream_ref.gen_num));
        try filespec.dict_obj.put(allocator, "EF", ef_dict);

        store.put(filespec_ref, filespec);
    }

    // 3. Annotation dictionary.
    var dict = types.pdfDict(allocator);
    errdefer dict.deinit(allocator);

    try dict.dict_obj.put(allocator, "Type", types.pdfName("Annot"));
    try dict.dict_obj.put(allocator, "Subtype", types.pdfName("RichMedia"));
    try putRect(allocator, &dict, media.rect);
    try dict.dict_obj.put(allocator, "F", types.pdfInt(4));

    // RichMediaContent dict with an Assets name tree.
    var content = types.pdfDict(allocator);

    var assets_names = types.pdfArray(allocator);
    try assets_names.array_obj.append(types.pdfString("richmedia"));
    try assets_names.array_obj.append(types.pdfRef(filespec_ref.obj_num, filespec_ref.gen_num));

    var assets_dict = types.pdfDict(allocator);
    try assets_dict.dict_obj.put(allocator, "Names", assets_names);
    try content.dict_obj.put(allocator, "Assets", assets_dict);

    try dict.dict_obj.put(allocator, "RichMediaContent", content);

    // RichMediaSettings with activation info.
    var settings = types.pdfDict(allocator);
    var activation = types.pdfDict(allocator);
    try activation.dict_obj.put(allocator, "Condition", types.pdfName("XA"));
    try settings.dict_obj.put(allocator, "Activation", activation);
    try dict.dict_obj.put(allocator, "RichMediaSettings", settings);

    return dict;
}

// -- Tests --

test "SoundEncoding name values" {
    try std.testing.expectEqualStrings("Raw", SoundEncoding.raw.nameValue());
    try std.testing.expectEqualStrings("Signed", SoundEncoding.signed.nameValue());
    try std.testing.expectEqualStrings("muLaw", SoundEncoding.mu_law.nameValue());
    try std.testing.expectEqualStrings("ALaw", SoundEncoding.a_law.nameValue());
}

test "MediaActivation condition names" {
    try std.testing.expectEqualStrings("PageOpen", MediaActivation.page_open.conditionName());
    try std.testing.expectEqualStrings("Click", MediaActivation.click.conditionName());
    try std.testing.expectEqualStrings("Explicit", MediaActivation.explicit.conditionName());
}

test "buildSoundAnnotation creates dict and stream" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try buildSoundAnnotation(allocator, &store, .{
        .rect = .{ .x = 10, .y = 20, .width = 30, .height = 30 },
        .sound_data = "PCMDATA!",
        .sample_rate = 44100,
        .channels = 2,
        .bits_per_sample = 16,
        .encoding = .signed,
    });
    defer ann.deinit(allocator);

    try std.testing.expect(ann.isDict());

    // Subtype should be Sound.
    const subtype = ann.dict_obj.get("Subtype").?;
    try std.testing.expectEqualStrings("Sound", subtype.asName().?);

    // Default Name entry.
    const name_obj = ann.dict_obj.get("Name").?;
    try std.testing.expectEqualStrings("Speaker", name_obj.asName().?);

    // Sound entry must be a ref.
    const sound_entry = ann.dict_obj.get("Sound").?;
    try std.testing.expect(sound_entry.isRef());

    // Sound stream should be in the store.
    try std.testing.expectEqual(@as(usize, 1), store.count());
    var stream_obj = store.get(sound_entry.asRef().?).?;
    try std.testing.expect(stream_obj.isStream());
    const sr = stream_obj.stream_obj.dict.get("R").?;
    try std.testing.expectEqual(@as(i64, 44100), sr.asInt().?);
    const enc = stream_obj.stream_obj.dict.get("E").?;
    try std.testing.expectEqualStrings("Signed", enc.asName().?);
}

test "buildScreenAnnotation creates rendition chain" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try buildScreenAnnotation(allocator, &store, .{
        .rect = .{ .x = 0, .y = 0, .width = 320, .height = 240 },
        .media_data = "VIDEOBYTES",
        .mime_type = "video/mp4",
        .activation = .page_open,
        .title = "Clip",
    });
    defer ann.deinit(allocator);

    try std.testing.expect(ann.isDict());
    const subtype = ann.dict_obj.get("Subtype").?;
    try std.testing.expectEqualStrings("Screen", subtype.asName().?);

    // Should have allocated: stream + filespec + mediaclip + rendition = 4 objects.
    try std.testing.expectEqual(@as(usize, 4), store.count());

    // Action must be present and reference the rendition.
    const action = ann.dict_obj.get("A").?;
    try std.testing.expect(action.isDict());
    const s = action.dict_obj.get("S").?;
    try std.testing.expectEqualStrings("Rendition", s.asName().?);
    const t = action.dict_obj.get("T").?;
    try std.testing.expectEqualStrings("PageOpen", t.asString().?);
}

test "buildRichMediaAnnotation embeds media" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    var ann = try buildRichMediaAnnotation(allocator, &store, .{
        .rect = .{ .x = 0, .y = 0, .width = 100, .height = 100 },
        .media_data = "SWFDATA",
        .mime_type = "application/x-shockwave-flash",
    });
    defer ann.deinit(allocator);

    try std.testing.expect(ann.isDict());
    const subtype = ann.dict_obj.get("Subtype").?;
    try std.testing.expectEqualStrings("RichMedia", subtype.asName().?);

    // stream + filespec = 2 objects.
    try std.testing.expectEqual(@as(usize, 2), store.count());

    const content = ann.dict_obj.get("RichMediaContent").?;
    try std.testing.expect(content.isDict());
    const settings = ann.dict_obj.get("RichMediaSettings").?;
    try std.testing.expect(settings.isDict());
}
