const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// The type of soft mask to apply.
pub const SoftMaskType = enum {
    /// Alpha-based masking: the mask's alpha channel controls opacity.
    alpha,
    /// Luminosity-based masking: the mask's luminance values control opacity.
    luminosity,

    /// Returns the PDF name for this soft mask subtype.
    pub fn pdfName(self: SoftMaskType) []const u8 {
        return switch (self) {
            .alpha => "Alpha",
            .luminosity => "Luminosity",
        };
    }
};

/// Defines a linear gradient mask that fades opacity along a line.
pub const GradientMask = struct {
    /// Start x coordinate of the gradient axis.
    x0: f32,
    /// Start y coordinate of the gradient axis.
    y0: f32,
    /// End x coordinate of the gradient axis.
    x1: f32,
    /// End y coordinate of the gradient axis.
    y1: f32,
    /// Opacity at the start of the gradient (0.0 = transparent, 1.0 = opaque).
    start_opacity: f32 = 1.0,
    /// Opacity at the end of the gradient (0.0 = transparent, 1.0 = opaque).
    end_opacity: f32 = 0.0,
};

/// A soft mask specification that can be applied to a page's graphics state.
pub const SoftMask = struct {
    /// The type of soft mask (alpha or luminosity).
    mask_type: SoftMaskType = .luminosity,
    /// The gradient definition for the mask.
    gradient_mask: GradientMask,
};

/// Bounding box for the mask form XObject.
pub const BBox = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32,
    height: f32,
};

/// Result of building a soft mask: the ExtGState reference and the resource name.
pub const SoftMaskResult = struct {
    /// Reference to the ExtGState object containing the SMask.
    ext_g_state_ref: Ref,
    /// The content stream for the form XObject (for inspection/testing).
    form_ref: Ref,
    /// The SMask dictionary reference.
    smask_ref: Ref,
};

/// Builds a soft mask with a gradient transparency effect.
///
/// Creates a Form XObject transparency group that paints a gradient from white
/// to black (for luminosity masks) or varies the alpha channel (for alpha masks),
/// wraps it in an SMask dictionary, and returns the references.
///
/// The caller should create an ExtGState with the returned SMask ref and register
/// it as a page resource.
pub fn buildSoftMask(
    allocator: Allocator,
    store: *ObjectStore,
    mask: SoftMask,
    bbox: BBox,
) !SoftMaskResult {
    // Build the shading function (Type 2 exponential interpolation)
    const func_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "FunctionType", types.pdfInt(2));

        var domain = types.pdfArray(allocator);
        try domain.array_obj.append(types.pdfReal(0.0));
        try domain.array_obj.append(types.pdfReal(1.0));
        try dict.dict_obj.put(allocator, "Domain", domain);

        try dict.dict_obj.put(allocator, "N", types.pdfReal(1.0));

        // For luminosity masks: white = opaque, black = transparent
        // Map start_opacity/end_opacity to grayscale values
        const start_gray: f64 = @floatCast(mask.gradient_mask.start_opacity);
        const end_gray: f64 = @floatCast(mask.gradient_mask.end_opacity);

        var c0 = types.pdfArray(allocator);
        try c0.array_obj.append(types.pdfReal(start_gray));
        try dict.dict_obj.put(allocator, "C0", c0);

        var c1 = types.pdfArray(allocator);
        try c1.array_obj.append(types.pdfReal(end_gray));
        try dict.dict_obj.put(allocator, "C1", c1);

        store.put(func_ref, dict);
    }

    // Build the shading dictionary (Type 2 = axial)
    const shading_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "ShadingType", types.pdfInt(2));
        try dict.dict_obj.put(allocator, "ColorSpace", types.pdfName("DeviceGray"));

        var coords = types.pdfArray(allocator);
        try coords.array_obj.append(types.pdfReal(@floatCast(mask.gradient_mask.x0)));
        try coords.array_obj.append(types.pdfReal(@floatCast(mask.gradient_mask.y0)));
        try coords.array_obj.append(types.pdfReal(@floatCast(mask.gradient_mask.x1)));
        try coords.array_obj.append(types.pdfReal(@floatCast(mask.gradient_mask.y1)));
        try dict.dict_obj.put(allocator, "Coords", coords);

        try dict.dict_obj.put(allocator, "Function", types.pdfRef(func_ref.obj_num, func_ref.gen_num));

        var extend = types.pdfArray(allocator);
        try extend.array_obj.append(types.pdfBool(true));
        try extend.array_obj.append(types.pdfBool(true));
        try dict.dict_obj.put(allocator, "Extend", extend);

        store.put(shading_ref, dict);
    }

    // Build the Form XObject content stream that paints the shading
    const form_ref = try store.allocate();
    {
        // The content stream references the shading as /Sh0
        const content = "/Sh0 sh\n";

        // Build the Resources dict for the form XObject
        var shading_res = types.pdfDict(allocator);
        try shading_res.dict_obj.put(allocator, "Sh0", types.pdfRef(shading_ref.obj_num, shading_ref.gen_num));

        var resources = types.pdfDict(allocator);
        try resources.dict_obj.put(allocator, "Shading", shading_res);

        // Build the transparency group dict
        var group = types.pdfDict(allocator);
        try group.dict_obj.put(allocator, "Type", types.pdfName("Group"));
        try group.dict_obj.put(allocator, "S", types.pdfName("Transparency"));
        try group.dict_obj.put(allocator, "CS", types.pdfName("DeviceGray"));

        // Build the Form XObject stream dict
        var bbox_arr = types.pdfArray(allocator);
        try bbox_arr.array_obj.append(types.pdfReal(@floatCast(bbox.x)));
        try bbox_arr.array_obj.append(types.pdfReal(@floatCast(bbox.y)));
        try bbox_arr.array_obj.append(types.pdfReal(@floatCast(bbox.x + bbox.width)));
        try bbox_arr.array_obj.append(types.pdfReal(@floatCast(bbox.y + bbox.height)));

        var stream_dict: std.StringHashMapUnmanaged(PdfObject) = .{};
        try stream_dict.put(allocator, "Type", types.pdfName("XObject"));
        try stream_dict.put(allocator, "Subtype", types.pdfName("Form"));
        try stream_dict.put(allocator, "FormType", types.pdfInt(1));
        try stream_dict.put(allocator, "BBox", bbox_arr);
        try stream_dict.put(allocator, "Group", group);
        try stream_dict.put(allocator, "Resources", resources);
        try stream_dict.put(allocator, "Length", types.pdfInt(@intCast(content.len)));

        store.put(form_ref, .{ .stream_obj = .{
            .dict = stream_dict,
            .data = content,
        } });
    }

    // Build the SMask dictionary
    const smask_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("Mask"));
        try dict.dict_obj.put(allocator, "S", types.pdfName(mask.mask_type.pdfName()));
        try dict.dict_obj.put(allocator, "G", types.pdfRef(form_ref.obj_num, form_ref.gen_num));

        store.put(smask_ref, dict);
    }

    // Build the ExtGState dictionary
    const gs_ref = try store.allocate();
    {
        var dict = types.pdfDict(allocator);
        try dict.dict_obj.put(allocator, "Type", types.pdfName("ExtGState"));
        try dict.dict_obj.put(allocator, "SMask", types.pdfRef(smask_ref.obj_num, smask_ref.gen_num));

        store.put(gs_ref, dict);
    }

    return .{
        .ext_g_state_ref = gs_ref,
        .form_ref = form_ref,
        .smask_ref = smask_ref,
    };
}

/// Builds an ExtGState that clears the soft mask (sets /SMask /None).
pub fn buildClearSoftMask(allocator: Allocator, store: *ObjectStore) !Ref {
    const gs_ref = try store.allocate();

    var dict = types.pdfDict(allocator);
    try dict.dict_obj.put(allocator, "Type", types.pdfName("ExtGState"));
    try dict.dict_obj.put(allocator, "SMask", types.pdfName("None"));

    store.put(gs_ref, dict);
    return gs_ref;
}

// -- Tests --

test "SoftMaskType pdfName" {
    try std.testing.expectEqualStrings("Alpha", SoftMaskType.alpha.pdfName());
    try std.testing.expectEqualStrings("Luminosity", SoftMaskType.luminosity.pdfName());
}

test "buildSoftMask creates expected objects" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const result = try buildSoftMask(allocator, &store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 0,
            .y0 = 0,
            .x1 = 200,
            .y1 = 0,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .width = 200,
        .height = 100,
    });

    // function + shading + form XObject + SMask dict + ExtGState = 5 objects
    try std.testing.expectEqual(@as(usize, 5), store.count());

    // ExtGState should exist and be a dict
    const gs_obj = store.get(result.ext_g_state_ref);
    try std.testing.expect(gs_obj != null);
    try std.testing.expect(gs_obj.?.isDict());

    // Form XObject should be a stream
    const form_obj = store.get(result.form_ref);
    try std.testing.expect(form_obj != null);
    try std.testing.expect(form_obj.?.isStream());

    // SMask should be a dict
    const smask_obj = store.get(result.smask_ref);
    try std.testing.expect(smask_obj != null);
    try std.testing.expect(smask_obj.?.isDict());
}

test "buildSoftMask with alpha type" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const result = try buildSoftMask(allocator, &store, .{
        .mask_type = .alpha,
        .gradient_mask = .{
            .x0 = 0,
            .y0 = 0,
            .x1 = 100,
            .y1 = 100,
            .start_opacity = 0.8,
            .end_opacity = 0.2,
        },
    }, .{
        .width = 100,
        .height = 100,
    });

    const smask_obj = store.get(result.smask_ref);
    try std.testing.expect(smask_obj != null);
}

test "buildClearSoftMask creates ExtGState with None" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try buildClearSoftMask(allocator, &store);

    try std.testing.expectEqual(@as(usize, 1), store.count());

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}
