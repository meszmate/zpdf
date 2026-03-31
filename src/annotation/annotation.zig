const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;

/// Supported annotation types.
pub const AnnotationType = enum {
    text,
    link,
    highlight,
    underline,
    strikeout,
    stamp,
    free_text,
    ink,

    /// Returns the PDF annotation subtype name.
    pub fn subtypeName(self: AnnotationType) []const u8 {
        return switch (self) {
            .text => "Text",
            .link => "Link",
            .highlight => "Highlight",
            .underline => "Underline",
            .strikeout => "StrikeOut",
            .stamp => "Stamp",
            .free_text => "FreeText",
            .ink => "Ink",
        };
    }
};

/// Color represented as RGB components (0.0 to 1.0).
pub const Color = struct {
    r: f64 = 0.0,
    g: f64 = 0.0,
    b: f64 = 0.0,
};

/// Rectangle in PDF coordinate space.
pub const Rect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

/// An annotation to be placed on a PDF page.
pub const Annotation = struct {
    ann_type: AnnotationType,
    rect: Rect,
    contents: ?[]const u8 = null,
    color: ?Color = null,
    uri: ?[]const u8 = null,
    border_width: f64 = 0,
    opacity: f64 = 1.0,
    title: ?[]const u8 = null,
    stamp_name: ?[]const u8 = null,
    quad_points: ?[]const f64 = null,
    font_size: f64 = 12.0,
};

/// Build a PDF annotation dictionary object from an Annotation struct.
pub fn buildAnnotation(allocator: Allocator, ann: Annotation) !PdfObject {
    var dict = types.pdfDict(allocator);
    errdefer dict.deinit(allocator);

    try dict.dict_obj.put(allocator, "Type", types.pdfName("Annot"));
    try dict.dict_obj.put(allocator, "Subtype", types.pdfName(ann.ann_type.subtypeName()));

    // Rect array: [x, y, x+w, y+h]
    var rect_arr = types.pdfArray(allocator);
    try rect_arr.array_obj.append(types.pdfReal(ann.rect.x));
    try rect_arr.array_obj.append(types.pdfReal(ann.rect.y));
    try rect_arr.array_obj.append(types.pdfReal(ann.rect.x + ann.rect.width));
    try rect_arr.array_obj.append(types.pdfReal(ann.rect.y + ann.rect.height));
    try dict.dict_obj.put(allocator, "Rect", rect_arr);

    // Contents
    if (ann.contents) |contents| {
        try dict.dict_obj.put(allocator, "Contents", types.pdfString(contents));
    }

    // Color
    if (ann.color) |color| {
        var color_arr = types.pdfArray(allocator);
        try color_arr.array_obj.append(types.pdfReal(color.r));
        try color_arr.array_obj.append(types.pdfReal(color.g));
        try color_arr.array_obj.append(types.pdfReal(color.b));
        try dict.dict_obj.put(allocator, "C", color_arr);
    }

    // Border
    var border_arr = types.pdfArray(allocator);
    try border_arr.array_obj.append(types.pdfReal(0));
    try border_arr.array_obj.append(types.pdfReal(0));
    try border_arr.array_obj.append(types.pdfReal(ann.border_width));
    try dict.dict_obj.put(allocator, "Border", border_arr);

    // Opacity (CA)
    if (ann.opacity < 1.0) {
        try dict.dict_obj.put(allocator, "CA", types.pdfReal(ann.opacity));
    }

    // Title (T)
    if (ann.title) |title| {
        try dict.dict_obj.put(allocator, "T", types.pdfString(title));
    }

    // Link-specific: URI action
    if (ann.ann_type == .link) {
        if (ann.uri) |uri| {
            var action = types.pdfDict(allocator);
            try action.dict_obj.put(allocator, "S", types.pdfName("URI"));
            try action.dict_obj.put(allocator, "URI", types.pdfString(uri));
            try dict.dict_obj.put(allocator, "A", action);
        }
    }

    // Stamp-specific: stamp name
    if (ann.ann_type == .stamp) {
        if (ann.stamp_name) |name| {
            try dict.dict_obj.put(allocator, "Name", types.pdfName(name));
        }
    }

    // FreeText-specific: default appearance
    if (ann.ann_type == .free_text) {
        var da_buf: std.ArrayListUnmanaged(u8) = .{};
        defer da_buf.deinit(allocator);
        try da_buf.writer(allocator).print("0 0 0 rg /Helvetica {d:.1} Tf", .{ann.font_size});
        try dict.dict_obj.put(allocator, "DA", types.pdfString(try da_buf.toOwnedSlice(allocator)));
    }

    // Highlight/underline/strikeout-specific: QuadPoints
    if (ann.ann_type == .highlight or ann.ann_type == .underline or ann.ann_type == .strikeout) {
        if (ann.quad_points) |qp| {
            var qp_arr = types.pdfArray(allocator);
            for (qp) |val| {
                try qp_arr.array_obj.append(types.pdfReal(val));
            }
            try dict.dict_obj.put(allocator, "QuadPoints", qp_arr);
        } else {
            // Default quad points from rect
            var qp_arr = types.pdfArray(allocator);
            const x1 = ann.rect.x;
            const y1 = ann.rect.y;
            const x2 = ann.rect.x + ann.rect.width;
            const y2 = ann.rect.y + ann.rect.height;
            try qp_arr.array_obj.append(types.pdfReal(x1));
            try qp_arr.array_obj.append(types.pdfReal(y2));
            try qp_arr.array_obj.append(types.pdfReal(x2));
            try qp_arr.array_obj.append(types.pdfReal(y2));
            try qp_arr.array_obj.append(types.pdfReal(x1));
            try qp_arr.array_obj.append(types.pdfReal(y1));
            try qp_arr.array_obj.append(types.pdfReal(x2));
            try qp_arr.array_obj.append(types.pdfReal(y1));
            try dict.dict_obj.put(allocator, "QuadPoints", qp_arr);
        }
    }

    // Annotation flags: Print (bit 3)
    try dict.dict_obj.put(allocator, "F", types.pdfInt(4));

    return dict;
}

// -- Tests --

test "annotation: build text annotation" {
    const allocator = std.testing.allocator;
    var ann_obj = try buildAnnotation(allocator, .{
        .ann_type = .text,
        .rect = .{ .x = 100, .y = 200, .width = 50, .height = 50 },
        .contents = "A note",
        .title = "Author",
    });
    defer ann_obj.deinit(allocator);

    try std.testing.expect(ann_obj.isDict());
}

test "annotation: build link annotation" {
    const allocator = std.testing.allocator;
    var ann_obj = try buildAnnotation(allocator, .{
        .ann_type = .link,
        .rect = .{ .x = 10, .y = 20, .width = 100, .height = 15 },
        .uri = "https://example.com",
    });
    defer ann_obj.deinit(allocator);

    try std.testing.expect(ann_obj.isDict());
    // Should have an action dict
    const action = ann_obj.dict_obj.get("A");
    try std.testing.expect(action != null);
}

test "annotation: build highlight annotation" {
    const allocator = std.testing.allocator;
    var ann_obj = try buildAnnotation(allocator, .{
        .ann_type = .highlight,
        .rect = .{ .x = 10, .y = 20, .width = 200, .height = 12 },
        .color = .{ .r = 1.0, .g = 1.0, .b = 0.0 },
    });
    defer ann_obj.deinit(allocator);

    try std.testing.expect(ann_obj.isDict());
    // Should have QuadPoints
    const qp = ann_obj.dict_obj.get("QuadPoints");
    try std.testing.expect(qp != null);
}

test "annotation: subtype names" {
    try std.testing.expectEqualStrings("Text", AnnotationType.text.subtypeName());
    try std.testing.expectEqualStrings("Link", AnnotationType.link.subtypeName());
    try std.testing.expectEqualStrings("Highlight", AnnotationType.highlight.subtypeName());
    try std.testing.expectEqualStrings("StrikeOut", AnnotationType.strikeout.subtypeName());
    try std.testing.expectEqualStrings("FreeText", AnnotationType.free_text.subtypeName());
}
