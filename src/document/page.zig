const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const StringHashMap = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const Ref = types.Ref;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const rich_text = @import("../text/rich_text.zig");

/// A 2D point.
pub const Point = struct {
    x: f32,
    y: f32,
};

/// Handle to an image resource that has been added to the document.
pub const ImageHandle = struct {
    ref: Ref,
    width: u32,
    height: u32,
};

/// A font resource registered on a page.
pub const FontResource = struct {
    ref: Ref,
    name: []const u8,
};

/// An image resource registered on a page.
pub const ImageResource = struct {
    ref: Ref,
    name: []const u8,
};

/// A pattern resource registered on a page.
pub const PatternResource = struct {
    ref: Ref,
    name: []const u8,
};

/// Page-level resources (fonts, images, patterns, etc.).
pub const Resources = struct {
    fonts: StringHashMap(FontResource),
    images: ArrayList(ImageResource),
    patterns: StringHashMap(PatternResource),
    allocator: Allocator,
    font_count: u32,
    image_count: u32,
    pattern_count: u32,

    pub fn init(allocator: Allocator) Resources {
        return .{
            .fonts = .{},
            .images = .{},
            .patterns = .{},
            .allocator = allocator,
            .font_count = 0,
            .image_count = 0,
            .pattern_count = 0,
        };
    }

    pub fn deinit(self: *Resources) void {
        var it = self.fonts.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
        }
        self.fonts.deinit(self.allocator);
        self.images.deinit(self.allocator);
        var pit = self.patterns.iterator();
        while (pit.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
        }
        self.patterns.deinit(self.allocator);
    }
};

/// An annotation on a page (link, etc.).
pub const Annotation = struct {
    rect: [4]f32,
    uri: ?[]const u8 = null,
    dest_page: ?usize = null,
};

/// Text alignment options.
pub const TextAlignment = enum {
    left,
    center,
    right,
};

/// Options for drawing text.
pub const TextOptions = struct {
    x: f32 = 0,
    y: f32 = 0,
    font: StandardFont = .helvetica,
    font_size: f32 = 12,
    color: Color = .{ .named = .black },
    alignment: TextAlignment = .left,
    max_width: ?f32 = null,
    line_height: ?f32 = null,
};

/// Options for drawing a rectangle.
pub const RectOptions = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 100,
    height: f32 = 50,
    color: ?Color = null,
    border_color: ?Color = null,
    border_width: f32 = 1.0,
    corner_radius: f32 = 0,
};

/// Options for drawing a circle.
pub const CircleOptions = struct {
    cx: f32 = 0,
    cy: f32 = 0,
    r: f32 = 50,
    color: ?Color = null,
    border_color: ?Color = null,
    border_width: f32 = 1.0,
};

/// Options for drawing an ellipse.
pub const EllipseOptions = struct {
    cx: f32 = 0,
    cy: f32 = 0,
    rx: f32 = 50,
    ry: f32 = 30,
    color: ?Color = null,
    border_color: ?Color = null,
    border_width: f32 = 1.0,
};

/// Options for drawing a line.
pub const LineOptions = struct {
    x1: f32 = 0,
    y1: f32 = 0,
    x2: f32 = 100,
    y2: f32 = 100,
    color: Color = .{ .named = .black },
    line_width: f32 = 1.0,
    dash_pattern: ?[]const f32 = null,
};

/// Options for drawing a polygon.
pub const PolygonOptions = struct {
    points: []const Point = &[_]Point{},
    color: ?Color = null,
    border_color: ?Color = null,
    border_width: f32 = 1.0,
};

/// Options for drawing a path.
pub const PathOptions = struct {
    color: ?Color = null,
    border_color: ?Color = null,
    border_width: f32 = 1.0,
};

/// Options for drawing an image.
pub const ImageOptions = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 100,
    height: f32 = 100,
};

/// A simple path builder for constructing arbitrary paths.
pub const PathBuilder = struct {
    commands: ArrayList(u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PathBuilder {
        return .{
            .commands = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PathBuilder) void {
        self.commands.deinit(self.allocator);
    }

    pub fn moveTo(self: *PathBuilder, x: f32, y: f32) !void {
        try self.commands.writer(self.allocator).print("{d:.2} {d:.2} m ", .{ x, y });
    }

    pub fn lineTo(self: *PathBuilder, x: f32, y: f32) !void {
        try self.commands.writer(self.allocator).print("{d:.2} {d:.2} l ", .{ x, y });
    }

    pub fn curveTo(self: *PathBuilder, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) !void {
        try self.commands.writer(self.allocator).print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c ", .{ x1, y1, x2, y2, x3, y3 });
    }

    pub fn closePath(self: *PathBuilder) !void {
        try self.commands.writer(self.allocator).print("h ", .{});
    }

    pub fn getCommands(self: *const PathBuilder) []const u8 {
        return self.commands.items;
    }
};

/// Writes the RGB components of a Color as PDF fill color operator.
fn writeColorFill(writer: anytype, c: Color) !void {
    const rgb = c.toRgb();
    try writer.print("{d:.4} {d:.4} {d:.4} rg\n", .{
        @as(f32, @floatFromInt(rgb.r)) / 255.0,
        @as(f32, @floatFromInt(rgb.g)) / 255.0,
        @as(f32, @floatFromInt(rgb.b)) / 255.0,
    });
}

/// Writes the RGB components of a Color as PDF stroke color operator.
fn writeColorStroke(writer: anytype, c: Color) !void {
    const rgb = c.toRgb();
    try writer.print("{d:.4} {d:.4} {d:.4} RG\n", .{
        @as(f32, @floatFromInt(rgb.r)) / 255.0,
        @as(f32, @floatFromInt(rgb.g)) / 255.0,
        @as(f32, @floatFromInt(rgb.b)) / 255.0,
    });
}

/// Represents a single page in a PDF document.
pub const Page = struct {
    allocator: Allocator,
    width: f32,
    height: f32,
    content: ArrayList(u8),
    resources: Resources,
    annotations: ArrayList(Annotation),
    rotation: u16,

    /// Creates a new page with the given dimensions in points.
    pub fn init(allocator: Allocator, width: f32, height: f32) Page {
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .content = .{},
            .resources = Resources.init(allocator),
            .annotations = .{},
            .rotation = 0,
        };
    }

    /// Frees all page resources.
    pub fn deinit(self: *Page) void {
        self.content.deinit(self.allocator);
        self.resources.deinit();
        self.annotations.deinit(self.allocator);
    }

    /// Returns the page width in points.
    pub fn getWidth(self: *const Page) f32 {
        return self.width;
    }

    /// Returns the page height in points.
    pub fn getHeight(self: *const Page) f32 {
        return self.height;
    }

    /// Sets the page rotation in degrees (must be a multiple of 90).
    pub fn setRotation(self: *Page, angle: u16) void {
        self.rotation = angle;
    }

    /// Registers a font on this page and returns the resource name (e.g. "F1").
    pub fn addFont(self: *Page, font_name: []const u8, ref: Ref) ![]const u8 {
        if (self.resources.fonts.get(font_name)) |existing| {
            return existing.name;
        }
        self.resources.font_count += 1;
        const name = try std.fmt.allocPrint(self.allocator, "F{d}", .{self.resources.font_count});
        try self.resources.fonts.put(self.allocator, font_name, .{ .ref = ref, .name = name });
        return name;
    }

    /// Registers a pattern on this page and returns the resource name (e.g. "P1").
    pub fn addPattern(self: *Page, pattern_name: []const u8, ref: Ref) ![]const u8 {
        if (self.resources.patterns.get(pattern_name)) |existing| {
            return existing.name;
        }
        self.resources.pattern_count += 1;
        const name = try std.fmt.allocPrint(self.allocator, "P{d}", .{self.resources.pattern_count});
        try self.resources.patterns.put(self.allocator, pattern_name, .{ .ref = ref, .name = name });
        return name;
    }

    /// Sets the fill color to a pattern (gradient). Writes `/Pattern cs /name scn` to the content stream.
    pub fn setGradientFill(self: *Page, pattern_name: []const u8) !void {
        const writer = self.contentWriter();
        try writer.writeAll("/Pattern cs\n");
        try writer.print("/{s} scn\n", .{pattern_name});
    }

    fn contentWriter(self: *Page) ArrayList(u8).Writer {
        return self.content.writer(self.allocator);
    }

    // -- Drawing methods --

    /// Draws text at the specified position.
    pub fn drawText(self: *Page, text: []const u8, options: TextOptions) !void {
        const writer = self.contentWriter();

        // Save graphics state
        try writer.writeAll("q\n");

        // Set fill color
        try writeColorFill(writer, options.color);

        // Look up font resource name, or use a default
        const font_pdf_name = options.font.pdfName();
        const res_name = if (self.resources.fonts.get(font_pdf_name)) |fr|
            fr.name
        else
            "F1";

        try writer.writeAll("BT\n");
        try writer.print("/{s} {d:.2} Tf\n", .{ res_name, options.font_size });

        if (options.max_width != null and options.line_height != null) {
            // Simple word-wrapping
            const max_w = options.max_width.?;
            const lh = options.line_height.?;
            const avg_cw = options.font.avgCharWidth() * options.font_size;

            const start_x = options.x;
            var cur_y = options.y;
            var line_start: usize = 0;
            var last_space: ?usize = null;
            var line_width: f32 = 0;

            for (text, 0..) |ch, i| {
                if (ch == ' ') last_space = i;
                line_width += avg_cw;
                if (line_width > max_w and last_space != null) {
                    const line = text[line_start..last_space.?];
                    try writeTextLine(writer, line, start_x, cur_y, options.alignment, max_w);
                    cur_y -= lh;
                    line_start = last_space.? + 1;
                    last_space = null;
                    line_width = 0;
                }
            }
            // Remaining text
            if (line_start < text.len) {
                const line = text[line_start..];
                try writeTextLine(writer, line, start_x, cur_y, options.alignment, max_w);
            }
        } else {
            try writeTextLine(writer, text, options.x, options.y, options.alignment, options.max_width);
        }

        try writer.writeAll("ET\n");
        // Restore graphics state
        try writer.writeAll("Q\n");
    }

    fn writeTextLine(writer: anytype, text: []const u8, x: f32, y: f32, alignment: TextAlignment, max_width: ?f32) !void {
        var actual_x = x;
        if (alignment != .left and max_width != null) {
            // Rough text width estimation for alignment
            const est_width = @as(f32, @floatFromInt(text.len)) * 6.0; // approximate
            switch (alignment) {
                .center => actual_x = x + (max_width.? - est_width) / 2.0,
                .right => actual_x = x + max_width.? - est_width,
                .left => {},
            }
        }
        try writer.print("{d:.2} {d:.2} Td\n", .{ actual_x, y });
        try writer.writeAll("(");
        // Escape special characters in PDF string
        for (text) |ch| {
            switch (ch) {
                '(' => try writer.writeAll("\\("),
                ')' => try writer.writeAll("\\)"),
                '\\' => try writer.writeAll("\\\\"),
                else => try writer.print("{c}", .{ch}),
            }
        }
        try writer.writeAll(") Tj\n");
    }

    /// Draws rich text with mixed fonts, sizes, colors and styles.
    /// Returns the total height consumed by the text block.
    pub fn drawRichText(self: *Page, spans: []const rich_text.TextSpan, options: rich_text.RichTextOptions) !f32 {
        return rich_text.drawRichText(self, spans, options);
    }

    /// Draws a rectangle.
    pub fn drawRect(self: *Page, options: RectOptions) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        if (options.border_color) |bc| {
            try writeColorStroke(writer, bc);
            try writer.print("{d:.2} w\n", .{options.border_width});
        }
        if (options.color) |c| {
            try writeColorFill(writer, c);
        }

        if (options.corner_radius > 0) {
            // Rounded rectangle using bezier curves
            const r = options.corner_radius;
            const x = options.x;
            const y = options.y;
            const w = options.width;
            const h = options.height;
            // kappa for circle approximation
            const k: f32 = 0.5522847498;
            const kr = k * r;

            try writer.print("{d:.2} {d:.2} m\n", .{ x + r, y });
            try writer.print("{d:.2} {d:.2} l\n", .{ x + w - r, y });
            try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ x + w - r + kr, y, x + w, y + r - kr, x + w, y + r });
            try writer.print("{d:.2} {d:.2} l\n", .{ x + w, y + h - r });
            try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ x + w, y + h - r + kr, x + w - r + kr, y + h, x + w - r, y + h });
            try writer.print("{d:.2} {d:.2} l\n", .{ x + r, y + h });
            try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ x + r - kr, y + h, x, y + h - r + kr, x, y + h - r });
            try writer.print("{d:.2} {d:.2} l\n", .{ x, y + r });
            try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ x, y + r - kr, x + r - kr, y, x + r, y });
            try writer.writeAll("h\n");
        } else {
            try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} re\n", .{ options.x, options.y, options.width, options.height });
        }

        try writeFillStroke(writer, options.color != null, options.border_color != null);
        try writer.writeAll("Q\n");
    }

    /// Draws a circle approximated with 4 bezier curves.
    pub fn drawCircle(self: *Page, options: CircleOptions) !void {
        try self.drawEllipse(.{
            .cx = options.cx,
            .cy = options.cy,
            .rx = options.r,
            .ry = options.r,
            .color = options.color,
            .border_color = options.border_color,
            .border_width = options.border_width,
        });
    }

    /// Draws an ellipse approximated with 4 bezier curves.
    pub fn drawEllipse(self: *Page, options: EllipseOptions) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        if (options.border_color) |bc| {
            try writeColorStroke(writer, bc);
            try writer.print("{d:.2} w\n", .{options.border_width});
        }
        if (options.color) |c| {
            try writeColorFill(writer, c);
        }

        // Kappa constant for bezier circle approximation
        const k: f32 = 0.5522847498;
        const cx = options.cx;
        const cy = options.cy;
        const rx = options.rx;
        const ry = options.ry;
        const kx = k * rx;
        const ky = k * ry;

        // Start at right point of ellipse
        try writer.print("{d:.2} {d:.2} m\n", .{ cx + rx, cy });
        // Top-right quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry });
        // Top-left quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy });
        // Bottom-left quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry });
        // Bottom-right quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy });
        try writer.writeAll("h\n");

        try writeFillStroke(writer, options.color != null, options.border_color != null);
        try writer.writeAll("Q\n");
    }

    /// Draws a straight line.
    pub fn drawLine(self: *Page, options: LineOptions) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        try writeColorStroke(writer, options.color);
        try writer.print("{d:.2} w\n", .{options.line_width});

        if (options.dash_pattern) |dash| {
            try writer.writeAll("[");
            for (dash, 0..) |d, i| {
                if (i > 0) try writer.writeAll(" ");
                try writer.print("{d:.2}", .{d});
            }
            try writer.writeAll("] 0 d\n");
        }

        try writer.print("{d:.2} {d:.2} m\n", .{ options.x1, options.y1 });
        try writer.print("{d:.2} {d:.2} l\n", .{ options.x2, options.y2 });
        try writer.writeAll("S\n");
        try writer.writeAll("Q\n");
    }

    /// Draws a polygon from a list of points.
    pub fn drawPolygon(self: *Page, options: PolygonOptions) !void {
        if (options.points.len < 2) return;

        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        if (options.border_color) |bc| {
            try writeColorStroke(writer, bc);
            try writer.print("{d:.2} w\n", .{options.border_width});
        }
        if (options.color) |c| {
            try writeColorFill(writer, c);
        }

        try writer.print("{d:.2} {d:.2} m\n", .{ options.points[0].x, options.points[0].y });
        for (options.points[1..]) |pt| {
            try writer.print("{d:.2} {d:.2} l\n", .{ pt.x, pt.y });
        }
        try writer.writeAll("h\n");

        try writeFillStroke(writer, options.color != null, options.border_color != null);
        try writer.writeAll("Q\n");
    }

    /// Draws an arbitrary path.
    pub fn drawPath(self: *Page, path: *const PathBuilder, options: PathOptions) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        if (options.border_color) |bc| {
            try writeColorStroke(writer, bc);
            try writer.print("{d:.2} w\n", .{options.border_width});
        }
        if (options.color) |c| {
            try writeColorFill(writer, c);
        }

        try writer.writeAll(path.getCommands());
        try writer.writeAll("\n");

        try writeFillStroke(writer, options.color != null, options.border_color != null);
        try writer.writeAll("Q\n");
    }

    // -- Clipping methods --

    /// Clip mode for clipping paths.
    pub const ClipMode = @import("../graphics/state.zig").ClipMode;

    /// Options for clipping.
    pub const ClipOptions = struct {
        mode: ClipMode = .non_zero,
    };

    /// Begin a clipping region using a rectangle.
    pub fn beginClipRect(self: *Page, x: f32, y: f32, width: f32, height: f32, mode: ClipMode) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} re\n", .{ x, y, width, height });
        switch (mode) {
            .non_zero => try writer.writeAll("W n\n"),
            .even_odd => try writer.writeAll("W* n\n"),
        }
    }

    /// Begin a clipping region using a circle.
    pub fn beginClipCircle(self: *Page, cx: f32, cy: f32, r: f32, mode: ClipMode) !void {
        try self.beginClipEllipse(cx, cy, r, r, mode);
    }

    /// Begin a clipping region using an ellipse.
    pub fn beginClipEllipse(self: *Page, cx: f32, cy: f32, rx: f32, ry: f32, mode: ClipMode) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        const k: f32 = 0.5522847498;
        const kx = k * rx;
        const ky = k * ry;

        // Start at right point of ellipse
        try writer.print("{d:.2} {d:.2} m\n", .{ cx + rx, cy });
        // Top-right quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry });
        // Top-left quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy });
        // Bottom-left quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry });
        // Bottom-right quadrant
        try writer.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy });
        try writer.writeAll("h\n");

        switch (mode) {
            .non_zero => try writer.writeAll("W n\n"),
            .even_odd => try writer.writeAll("W* n\n"),
        }
    }

    /// Begin a clipping region using a custom path (from PathBuilder).
    pub fn beginClipPath(self: *Page, path: *const PathBuilder, mode: ClipMode) !void {
        const writer = self.contentWriter();
        try writer.writeAll("q\n");
        try writer.writeAll(path.getCommands());
        try writer.writeAll("\n");
        switch (mode) {
            .non_zero => try writer.writeAll("W n\n"),
            .even_odd => try writer.writeAll("W* n\n"),
        }
    }

    /// End the current clipping region (restores graphics state).
    pub fn endClip(self: *Page) !void {
        const writer = self.contentWriter();
        try writer.writeAll("Q\n");
    }

    /// Draws an image on the page using a previously registered image handle.
    pub fn drawImage(self: *Page, image: ImageHandle, options: ImageOptions) !void {
        _ = image;
        const writer = self.contentWriter();
        try writer.writeAll("q\n");

        // Set image transformation matrix: scale and translate
        try writer.print("{d:.2} 0 0 {d:.2} {d:.2} {d:.2} cm\n", .{ options.width, options.height, options.x, options.y });

        // Reference the image XObject - use next image resource
        self.resources.image_count += 1;
        const img_name = try std.fmt.allocPrint(self.allocator, "Im{d}", .{self.resources.image_count});
        defer self.allocator.free(img_name);
        try writer.print("/{s} Do\n", .{img_name});

        try writer.writeAll("Q\n");
    }

    /// Writes the appropriate fill/stroke operator based on what colors are set.
    fn writeFillStroke(writer: anytype, has_fill: bool, has_stroke: bool) !void {
        if (has_fill and has_stroke) {
            try writer.writeAll("B\n");
        } else if (has_fill) {
            try writer.writeAll("f\n");
        } else if (has_stroke) {
            try writer.writeAll("S\n");
        } else {
            try writer.writeAll("n\n");
        }
    }
};

// -- Tests --

test "page init and deinit" {
    var page = Page.init(std.testing.allocator, 595.28, 841.89);
    defer page.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 595.28), page.getWidth(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 841.89), page.getHeight(), 0.01);
}

test "page set rotation" {
    var page = Page.init(std.testing.allocator, 612, 792);
    defer page.deinit();

    page.setRotation(90);
    try std.testing.expectEqual(@as(u16, 90), page.rotation);
}

test "page add font" {
    var page = Page.init(std.testing.allocator, 612, 792);
    defer page.deinit();

    const name = try page.addFont("Helvetica", .{ .obj_num = 5, .gen_num = 0 });
    try std.testing.expectEqualStrings("F1", name);

    // Adding same font again returns same name
    const name2 = try page.addFont("Helvetica", .{ .obj_num = 5, .gen_num = 0 });
    try std.testing.expectEqualStrings("F1", name2);
}

test "draw line produces content" {
    var page = Page.init(std.testing.allocator, 612, 792);
    defer page.deinit();

    try page.drawLine(.{ .x1 = 10, .y1 = 20, .x2 = 100, .y2 = 200 });
    try std.testing.expect(page.content.items.len > 0);
    // Should contain moveto and lineto operators
    try std.testing.expect(std.mem.indexOf(u8, page.content.items, " m\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, page.content.items, " l\n") != null);
}

test "draw rect produces content" {
    var page = Page.init(std.testing.allocator, 612, 792);
    defer page.deinit();

    try page.drawRect(.{ .x = 10, .y = 20, .width = 100, .height = 50, .color = color_mod.rgb(255, 0, 0) });
    try std.testing.expect(page.content.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, page.content.items, " re\n") != null);
}

test "path builder" {
    var pb = PathBuilder.init(std.testing.allocator);
    defer pb.deinit();

    try pb.moveTo(0, 0);
    try pb.lineTo(100, 100);
    try pb.closePath();

    const cmds = pb.getCommands();
    try std.testing.expect(cmds.len > 0);
}
