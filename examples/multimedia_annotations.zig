const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Demonstrate the low-level multimedia annotation builders by writing
    // a Sound, Screen and RichMedia annotation dict plus their supporting
    // indirect objects into an ObjectStore.
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    // 1. A short fake PCM blob used as the sound data.
    const pcm = "\x00\x10\x20\x30\x40\x50\x60\x70";

    var sound_ann = try zpdf.buildSoundAnnotation(allocator, &store, .{
        .rect = .{ .x = 72, .y = 720, .width = 24, .height = 24 },
        .sound_data = pcm,
        .sample_rate = 22050,
        .channels = 1,
        .bits_per_sample = 8,
        .encoding = .mu_law,
    });
    defer sound_ann.deinit(allocator);

    // 2. A tiny fake MP4 stand-in for a video clip.
    const mp4 = "FAKE-MP4-PAYLOAD";

    var video_ann = try zpdf.buildScreenAnnotation(allocator, &store, .{
        .rect = .{ .x = 72, .y = 500, .width = 320, .height = 180 },
        .media_data = mp4,
        .mime_type = "video/mp4",
        .activation = .click,
        .title = "Intro Video",
    });
    defer video_ann.deinit(allocator);

    // 3. A RichMedia asset.
    var rm_ann = try zpdf.buildRichMediaAnnotation(allocator, &store, .{
        .rect = .{ .x = 72, .y = 260, .width = 300, .height = 200 },
        .media_data = "RICHMEDIA-BYTES",
        .mime_type = "application/x-shockwave-flash",
    });
    defer rm_ann.deinit(allocator);

    std.debug.print(
        "Built multimedia annotations. Indirect objects allocated: {d}\n",
        .{store.count()},
    );
    std.debug.print("  Sound annotation subtype:    {s}\n", .{
        sound_ann.dict_obj.get("Subtype").?.asName().?,
    });
    std.debug.print("  Screen annotation subtype:   {s}\n", .{
        video_ann.dict_obj.get("Subtype").?.asName().?,
    });
    std.debug.print("  RichMedia annotation subtype: {s}\n", .{
        rm_ann.dict_obj.get("Subtype").?.asName().?,
    });
}
