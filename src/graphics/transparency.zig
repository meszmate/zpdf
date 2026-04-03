const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// PDF blend modes as defined in PDF Reference 1.7, Table 7.2.
pub const BlendMode = enum {
    normal,
    multiply,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,

    /// Returns the PDF name for this blend mode (e.g. "Normal", "Multiply").
    pub fn pdfName(self: BlendMode) []const u8 {
        return switch (self) {
            .normal => "Normal",
            .multiply => "Multiply",
            .screen => "Screen",
            .overlay => "Overlay",
            .darken => "Darken",
            .lighten => "Lighten",
            .color_dodge => "ColorDodge",
            .color_burn => "ColorBurn",
            .hard_light => "HardLight",
            .soft_light => "SoftLight",
            .difference => "Difference",
            .exclusion => "Exclusion",
        };
    }
};

/// Options for configuring transparency via an ExtGState dictionary.
pub const TransparencyOptions = struct {
    /// Fill opacity (0.0 = fully transparent, 1.0 = fully opaque).
    fill_opacity: ?f32 = null,
    /// Stroke opacity (0.0 = fully transparent, 1.0 = fully opaque).
    stroke_opacity: ?f32 = null,
    /// Blend mode for compositing.
    blend_mode: ?BlendMode = null,
};

/// Builds an ExtGState object for the given transparency options and stores it
/// in the provided ObjectStore. Returns the Ref to the new ExtGState object.
pub fn buildTransparencyExtGState(
    allocator: Allocator,
    store: *ObjectStore,
    options: TransparencyOptions,
) !Ref {
    const gs_ref = try store.allocate();

    var dict = types.pdfDict(allocator);
    try dict.dict_obj.put(allocator, "Type", types.pdfName("ExtGState"));

    if (options.fill_opacity) |ca| {
        const clamped = clamp(ca);
        try dict.dict_obj.put(allocator, "ca", types.pdfReal(@floatCast(clamped)));
    }

    if (options.stroke_opacity) |ca| {
        const clamped = clamp(ca);
        try dict.dict_obj.put(allocator, "CA", types.pdfReal(@floatCast(clamped)));
    }

    if (options.blend_mode) |bm| {
        try dict.dict_obj.put(allocator, "BM", types.pdfName(bm.pdfName()));
    }

    store.put(gs_ref, dict);
    return gs_ref;
}

fn clamp(v: f32) f32 {
    if (v < 0.0) return 0.0;
    if (v > 1.0) return 1.0;
    return v;
}

// -- Tests --

test "BlendMode pdfName returns correct strings" {
    try std.testing.expectEqualStrings("Normal", BlendMode.normal.pdfName());
    try std.testing.expectEqualStrings("Multiply", BlendMode.multiply.pdfName());
    try std.testing.expectEqualStrings("Screen", BlendMode.screen.pdfName());
    try std.testing.expectEqualStrings("Overlay", BlendMode.overlay.pdfName());
    try std.testing.expectEqualStrings("Darken", BlendMode.darken.pdfName());
    try std.testing.expectEqualStrings("Lighten", BlendMode.lighten.pdfName());
    try std.testing.expectEqualStrings("ColorDodge", BlendMode.color_dodge.pdfName());
    try std.testing.expectEqualStrings("ColorBurn", BlendMode.color_burn.pdfName());
    try std.testing.expectEqualStrings("HardLight", BlendMode.hard_light.pdfName());
    try std.testing.expectEqualStrings("SoftLight", BlendMode.soft_light.pdfName());
    try std.testing.expectEqualStrings("Difference", BlendMode.difference.pdfName());
    try std.testing.expectEqualStrings("Exclusion", BlendMode.exclusion.pdfName());
}

test "buildTransparencyExtGState creates object with fill opacity" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try buildTransparencyExtGState(allocator, &store, .{
        .fill_opacity = 0.5,
    });

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "buildTransparencyExtGState creates object with all options" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try buildTransparencyExtGState(allocator, &store, .{
        .fill_opacity = 0.3,
        .stroke_opacity = 0.7,
        .blend_mode = .multiply,
    });

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "clamp constrains values to 0-1 range" {
    try std.testing.expectEqual(@as(f32, 0.0), clamp(-0.5));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(1.5));
    try std.testing.expectEqual(@as(f32, 0.5), clamp(0.5));
}
