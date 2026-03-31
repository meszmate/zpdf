const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Color = @import("../color/color.zig").Color;
const RgbColor = @import("../color/color.zig").RgbColor;

/// A color stop within a gradient, specifying a color at a position along the gradient axis.
pub const ColorStop = struct {
    offset: f32, // 0.0 to 1.0
    color: Color,
};

/// A linear (axial) gradient defined by two endpoints and color stops.
pub const LinearGradient = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    stops: []const ColorStop,
    extend_start: bool = false,
    extend_end: bool = false,
};

/// A radial gradient defined by two circles and color stops.
pub const RadialGradient = struct {
    cx0: f32,
    cy0: f32,
    r0: f32,
    cx1: f32,
    cy1: f32,
    r1: f32,
    stops: []const ColorStop,
    extend_start: bool = false,
    extend_end: bool = false,
};

pub const GradientError = error{
    TooFewStops,
    InvalidStopOrder,
    InvalidStopOffset,
};

/// Validates that color stops are well-formed: at least 2 stops, offsets in [0,1], monotonically non-decreasing.
pub fn validateStops(stops: []const ColorStop) GradientError!void {
    if (stops.len < 2) return GradientError.TooFewStops;
    for (stops) |stop| {
        if (stop.offset < 0.0 or stop.offset > 1.0) return GradientError.InvalidStopOffset;
    }
    for (stops[1..], 0..) |stop, i| {
        if (stop.offset < stops[i].offset) return GradientError.InvalidStopOrder;
    }
}

fn colorToRgbFloats(c: Color) [3]f64 {
    const rgb = c.toRgb();
    return .{
        @as(f64, @floatFromInt(rgb.r)) / 255.0,
        @as(f64, @floatFromInt(rgb.g)) / 255.0,
        @as(f64, @floatFromInt(rgb.b)) / 255.0,
    };
}

/// Builds a PDF Type 2 (exponential interpolation) function dict for interpolating between two colors.
fn buildType2Function(allocator: Allocator, store: *ObjectStore, c0: Color, c1: Color) !Ref {
    const ref = try store.allocate();

    var dict = types.pdfDict(allocator);
    try dict.dict_obj.put(allocator, "FunctionType", types.pdfInt(2));

    // Domain [0 1]
    var domain = types.pdfArray(allocator);
    try domain.array_obj.append(types.pdfReal(0.0));
    try domain.array_obj.append(types.pdfReal(1.0));
    try dict.dict_obj.put(allocator, "Domain", domain);

    // N = 1 (linear interpolation)
    try dict.dict_obj.put(allocator, "N", types.pdfReal(1.0));

    // C0
    const rgb0 = colorToRgbFloats(c0);
    var c0_arr = types.pdfArray(allocator);
    try c0_arr.array_obj.append(types.pdfReal(rgb0[0]));
    try c0_arr.array_obj.append(types.pdfReal(rgb0[1]));
    try c0_arr.array_obj.append(types.pdfReal(rgb0[2]));
    try dict.dict_obj.put(allocator, "C0", c0_arr);

    // C1
    const rgb1 = colorToRgbFloats(c1);
    var c1_arr = types.pdfArray(allocator);
    try c1_arr.array_obj.append(types.pdfReal(rgb1[0]));
    try c1_arr.array_obj.append(types.pdfReal(rgb1[1]));
    try c1_arr.array_obj.append(types.pdfReal(rgb1[2]));
    try dict.dict_obj.put(allocator, "C1", c1_arr);

    store.put(ref, dict);
    return ref;
}

/// Builds the interpolation function for a set of color stops.
/// For 2 stops: a single Type 2 function.
/// For 3+ stops: a Type 3 stitching function combining Type 2 sub-functions.
fn buildInterpolationFunction(allocator: Allocator, store: *ObjectStore, stops: []const ColorStop) !Ref {
    if (stops.len == 2) {
        return buildType2Function(allocator, store, stops[0].color, stops[1].color);
    }

    // Build Type 2 sub-functions for each adjacent pair
    const num_segments = stops.len - 1;
    var functions = types.pdfArray(allocator);
    for (0..num_segments) |i| {
        const sub_ref = try buildType2Function(allocator, store, stops[i].color, stops[i + 1].color);
        try functions.array_obj.append(types.pdfRef(sub_ref.obj_num, sub_ref.gen_num));
    }

    // Bounds: the offsets between first and last stop
    var bounds = types.pdfArray(allocator);
    for (stops[1 .. stops.len - 1]) |stop| {
        try bounds.array_obj.append(types.pdfReal(@floatCast(stop.offset)));
    }

    // Encode: each sub-function maps [0 1]
    var encode = types.pdfArray(allocator);
    for (0..num_segments) |_| {
        try encode.array_obj.append(types.pdfReal(0.0));
        try encode.array_obj.append(types.pdfReal(1.0));
    }

    // Build the Type 3 stitching function
    const ref = try store.allocate();
    var dict = types.pdfDict(allocator);
    try dict.dict_obj.put(allocator, "FunctionType", types.pdfInt(3));

    var domain = types.pdfArray(allocator);
    try domain.array_obj.append(types.pdfReal(@floatCast(stops[0].offset)));
    try domain.array_obj.append(types.pdfReal(@floatCast(stops[stops.len - 1].offset)));
    try dict.dict_obj.put(allocator, "Domain", domain);

    try dict.dict_obj.put(allocator, "Functions", functions);
    try dict.dict_obj.put(allocator, "Bounds", bounds);
    try dict.dict_obj.put(allocator, "Encode", encode);

    store.put(ref, dict);
    return ref;
}

/// Builds a linear gradient shading + pattern in the object store. Returns a reference to the Pattern object.
pub fn buildLinearGradient(allocator: Allocator, store: *ObjectStore, gradient: LinearGradient) !Ref {
    try validateStops(gradient.stops);

    // Build the interpolation function
    const func_ref = try buildInterpolationFunction(allocator, store, gradient.stops);

    // Build Shading dictionary (Type 2 = axial)
    const shading_ref = try store.allocate();
    var shading = types.pdfDict(allocator);
    try shading.dict_obj.put(allocator, "ShadingType", types.pdfInt(2));

    try shading.dict_obj.put(allocator, "ColorSpace", types.pdfName("DeviceRGB"));

    // Coords [x0 y0 x1 y1]
    var coords = types.pdfArray(allocator);
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.x0)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.y0)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.x1)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.y1)));
    try shading.dict_obj.put(allocator, "Coords", coords);

    try shading.dict_obj.put(allocator, "Function", types.pdfRef(func_ref.obj_num, func_ref.gen_num));

    // Extend
    var extend = types.pdfArray(allocator);
    try extend.array_obj.append(types.pdfBool(gradient.extend_start));
    try extend.array_obj.append(types.pdfBool(gradient.extend_end));
    try shading.dict_obj.put(allocator, "Extend", extend);

    store.put(shading_ref, shading);

    // Build Pattern dictionary
    const pattern_ref = try store.allocate();
    var pattern = types.pdfDict(allocator);
    try pattern.dict_obj.put(allocator, "Type", types.pdfName("Pattern"));
    try pattern.dict_obj.put(allocator, "PatternType", types.pdfInt(2));
    try pattern.dict_obj.put(allocator, "Shading", types.pdfRef(shading_ref.obj_num, shading_ref.gen_num));

    store.put(pattern_ref, pattern);
    return pattern_ref;
}

/// Builds a radial gradient shading + pattern in the object store. Returns a reference to the Pattern object.
pub fn buildRadialGradient(allocator: Allocator, store: *ObjectStore, gradient: RadialGradient) !Ref {
    try validateStops(gradient.stops);

    // Build the interpolation function
    const func_ref = try buildInterpolationFunction(allocator, store, gradient.stops);

    // Build Shading dictionary (Type 3 = radial)
    const shading_ref = try store.allocate();
    var shading = types.pdfDict(allocator);
    try shading.dict_obj.put(allocator, "ShadingType", types.pdfInt(3));

    try shading.dict_obj.put(allocator, "ColorSpace", types.pdfName("DeviceRGB"));

    // Coords [cx0 cy0 r0 cx1 cy1 r1]
    var coords = types.pdfArray(allocator);
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.cx0)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.cy0)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.r0)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.cx1)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.cy1)));
    try coords.array_obj.append(types.pdfReal(@floatCast(gradient.r1)));
    try shading.dict_obj.put(allocator, "Coords", coords);

    try shading.dict_obj.put(allocator, "Function", types.pdfRef(func_ref.obj_num, func_ref.gen_num));

    // Extend
    var extend = types.pdfArray(allocator);
    try extend.array_obj.append(types.pdfBool(gradient.extend_start));
    try extend.array_obj.append(types.pdfBool(gradient.extend_end));
    try shading.dict_obj.put(allocator, "Extend", extend);

    store.put(shading_ref, shading);

    // Build Pattern dictionary
    const pattern_ref = try store.allocate();
    var pattern = types.pdfDict(allocator);
    try pattern.dict_obj.put(allocator, "Type", types.pdfName("Pattern"));
    try pattern.dict_obj.put(allocator, "PatternType", types.pdfInt(2));
    try pattern.dict_obj.put(allocator, "Shading", types.pdfRef(shading_ref.obj_num, shading_ref.gen_num));

    store.put(pattern_ref, pattern);
    return pattern_ref;
}

// -- Tests --

test "validateStops rejects fewer than 2 stops" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = .{ .named = .red } },
    };
    try std.testing.expectError(GradientError.TooFewStops, validateStops(&stops));
}

test "validateStops rejects out-of-range offset" {
    const stops = [_]ColorStop{
        .{ .offset = -0.1, .color = .{ .named = .red } },
        .{ .offset = 1.0, .color = .{ .named = .blue } },
    };
    try std.testing.expectError(GradientError.InvalidStopOffset, validateStops(&stops));
}

test "validateStops rejects non-monotonic offsets" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = .{ .named = .red } },
        .{ .offset = 0.8, .color = .{ .named = .green } },
        .{ .offset = 0.5, .color = .{ .named = .blue } },
    };
    try std.testing.expectError(GradientError.InvalidStopOrder, validateStops(&stops));
}

test "validateStops accepts valid stops" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = .{ .named = .red } },
        .{ .offset = 0.5, .color = .{ .named = .green } },
        .{ .offset = 1.0, .color = .{ .named = .blue } },
    };
    try validateStops(&stops);
}

test "buildLinearGradient with 2 stops" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = .{ .rgb = .{ .r = 0, .g = 0, .b = 255 } } },
        .{ .offset = 1.0, .color = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } } },
    };

    const pattern_ref = try buildLinearGradient(allocator, &store, .{
        .x0 = 0, .y0 = 0,
        .x1 = 100, .y1 = 100,
        .stops = &stops,
        .extend_start = true,
        .extend_end = true,
    });

    // Should have created objects: function, shading, pattern
    try std.testing.expect(store.count() >= 3);

    // The pattern object should exist and be a dict
    const pattern_obj = store.get(pattern_ref);
    try std.testing.expect(pattern_obj != null);
    try std.testing.expect(pattern_obj.?.isDict());
}

test "buildLinearGradient with multiple stops creates stitching function" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } } },
        .{ .offset = 0.5, .color = .{ .rgb = .{ .r = 0, .g = 255, .b = 0 } } },
        .{ .offset = 1.0, .color = .{ .rgb = .{ .r = 0, .g = 0, .b = 255 } } },
    };

    const pattern_ref = try buildLinearGradient(allocator, &store, .{
        .x0 = 0, .y0 = 0,
        .x1 = 200, .y1 = 0,
        .stops = &stops,
    });

    // 2 Type2 functions + 1 Type3 stitching + 1 shading + 1 pattern = 5 objects
    try std.testing.expectEqual(@as(usize, 5), store.count());

    const pattern_obj = store.get(pattern_ref);
    try std.testing.expect(pattern_obj != null);
}

test "buildRadialGradient" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } } },
        .{ .offset = 1.0, .color = .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } } },
    };

    const pattern_ref = try buildRadialGradient(allocator, &store, .{
        .cx0 = 50, .cy0 = 50, .r0 = 0,
        .cx1 = 50, .cy1 = 50, .r1 = 50,
        .stops = &stops,
    });

    // function + shading + pattern = 3 objects
    try std.testing.expectEqual(@as(usize, 3), store.count());

    const pattern_obj = store.get(pattern_ref);
    try std.testing.expect(pattern_obj != null);
    try std.testing.expect(pattern_obj.?.isDict());
}
