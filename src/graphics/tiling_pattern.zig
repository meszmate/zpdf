const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Color = @import("../color/color.zig").Color;

/// How the pattern cell is tiled (PDF spec Table 75).
pub const TilingType = enum(u8) {
    /// Constant spacing: pattern cells are spaced consistently.
    constant_spacing = 1,
    /// No distortion: the pattern cell is not distorted, spacing may vary slightly.
    no_distortion = 2,
    /// Constant spacing and faster tiling (implementation-dependent).
    constant_spacing_faster = 3,
};

/// Whether the pattern cell carries its own color or is uncolored (PDF spec Table 75).
pub const PaintType = enum(u8) {
    /// Colored tiling pattern: the pattern content stream specifies colors.
    colored = 1,
    /// Uncolored tiling pattern: color is supplied when the pattern is used.
    uncolored = 2,
};

/// Describes a tiling pattern to be embedded into a PDF.
pub const TilingPattern = struct {
    /// Width of the pattern cell bounding box.
    bbox_width: f32,
    /// Height of the pattern cell bounding box.
    bbox_height: f32,
    /// Horizontal spacing between pattern cell origins.
    x_step: f32,
    /// Vertical spacing between pattern cell origins.
    y_step: f32,
    /// The raw PDF content stream that draws the pattern cell.
    content: []const u8,
    /// Paint type (colored vs uncolored).
    paint_type: PaintType = .colored,
    /// Tiling type (spacing behavior).
    tiling_type: TilingType = .constant_spacing,
};

/// A builder for constructing custom tiling pattern content streams.
pub const PatternBuilder = struct {
    commands: std.ArrayListUnmanaged(u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PatternBuilder {
        return .{
            .commands = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PatternBuilder) void {
        self.commands.deinit(self.allocator);
    }

    fn writer(self: *PatternBuilder) std.ArrayListUnmanaged(u8).Writer {
        return self.commands.writer(self.allocator);
    }

    /// Set the fill color (RGB, 0-255 per channel).
    pub fn setFillColor(self: *PatternBuilder, c: Color) !void {
        const rgb = c.toRgb();
        try self.writer().print("{d:.4} {d:.4} {d:.4} rg\n", .{
            @as(f32, @floatFromInt(rgb.r)) / 255.0,
            @as(f32, @floatFromInt(rgb.g)) / 255.0,
            @as(f32, @floatFromInt(rgb.b)) / 255.0,
        });
    }

    /// Set the stroke color (RGB, 0-255 per channel).
    pub fn setStrokeColor(self: *PatternBuilder, c: Color) !void {
        const rgb = c.toRgb();
        try self.writer().print("{d:.4} {d:.4} {d:.4} RG\n", .{
            @as(f32, @floatFromInt(rgb.r)) / 255.0,
            @as(f32, @floatFromInt(rgb.g)) / 255.0,
            @as(f32, @floatFromInt(rgb.b)) / 255.0,
        });
    }

    /// Set the line width.
    pub fn setLineWidth(self: *PatternBuilder, w: f32) !void {
        try self.writer().print("{d:.2} w\n", .{w});
    }

    /// Append a rectangle to the path.
    pub fn rect(self: *PatternBuilder, x: f32, y: f32, w: f32, h: f32) !void {
        try self.writer().print("{d:.2} {d:.2} {d:.2} {d:.2} re\n", .{ x, y, w, h });
    }

    /// Move to a point.
    pub fn moveTo(self: *PatternBuilder, x: f32, y: f32) !void {
        try self.writer().print("{d:.2} {d:.2} m\n", .{ x, y });
    }

    /// Line to a point.
    pub fn lineTo(self: *PatternBuilder, x: f32, y: f32) !void {
        try self.writer().print("{d:.2} {d:.2} l\n", .{ x, y });
    }

    /// Draw a circle approximated with bezier curves.
    pub fn circle(self: *PatternBuilder, cx: f32, cy: f32, r: f32) !void {
        const k: f32 = 0.5522847498;
        const kr = k * r;
        const w = self.writer();
        try w.print("{d:.2} {d:.2} m\n", .{ cx + r, cy });
        try w.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx + r, cy + kr, cx + kr, cy + r, cx, cy + r });
        try w.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx - kr, cy + r, cx - r, cy + kr, cx - r, cy });
        try w.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx - r, cy - kr, cx - kr, cy - r, cx, cy - r });
        try w.print("{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} c\n", .{ cx + kr, cy - r, cx + r, cy - kr, cx + r, cy });
        try w.print("h\n", .{});
    }

    /// Fill the current path.
    pub fn fill(self: *PatternBuilder) !void {
        try self.writer().print("f\n", .{});
    }

    /// Stroke the current path.
    pub fn stroke(self: *PatternBuilder) !void {
        try self.writer().print("S\n", .{});
    }

    /// Close path.
    pub fn closePath(self: *PatternBuilder) !void {
        try self.writer().print("h\n", .{});
    }

    /// Returns the accumulated content stream bytes.
    pub fn getContent(self: *const PatternBuilder) []const u8 {
        return self.commands.items;
    }
};

// ── Preset pattern generators ──────────────────────────────────────

/// Creates a horizontal stripes pattern.
/// `stripe_width` is the height of one stripe, `spacing` is the gap between stripes.
pub fn stripes(allocator: Allocator, fg: Color, bg: Color, stripe_width: f32, spacing: f32) !TilingPattern {
    var pb = PatternBuilder.init(allocator);
    defer pb.deinit();

    const cell_h = stripe_width + spacing;
    const cell_w = stripe_width + spacing;

    // Background
    try pb.setFillColor(bg);
    try pb.rect(0, 0, cell_w, cell_h);
    try pb.fill();

    // Foreground stripe
    try pb.setFillColor(fg);
    try pb.rect(0, 0, cell_w, stripe_width);
    try pb.fill();

    const content = try allocator.dupe(u8, pb.getContent());
    return .{
        .bbox_width = cell_w,
        .bbox_height = cell_h,
        .x_step = cell_w,
        .y_step = cell_h,
        .content = content,
    };
}

/// Creates a dot pattern (circles on a background).
/// `dot_radius` is the radius of each dot, `spacing` is the cell size.
pub fn dots(allocator: Allocator, fg: Color, bg: Color, dot_radius: f32, spacing: f32) !TilingPattern {
    var pb = PatternBuilder.init(allocator);
    defer pb.deinit();

    // Background
    try pb.setFillColor(bg);
    try pb.rect(0, 0, spacing, spacing);
    try pb.fill();

    // Dot in center
    try pb.setFillColor(fg);
    try pb.circle(spacing / 2.0, spacing / 2.0, dot_radius);
    try pb.fill();

    const content = try allocator.dupe(u8, pb.getContent());
    return .{
        .bbox_width = spacing,
        .bbox_height = spacing,
        .x_step = spacing,
        .y_step = spacing,
        .content = content,
    };
}

/// Creates a grid pattern (horizontal + vertical lines).
/// `line_width` is the width of grid lines, `cell_size` is the size of each grid cell.
pub fn grid(allocator: Allocator, fg: Color, bg: Color, line_width: f32, cell_size: f32) !TilingPattern {
    var pb = PatternBuilder.init(allocator);
    defer pb.deinit();

    // Background
    try pb.setFillColor(bg);
    try pb.rect(0, 0, cell_size, cell_size);
    try pb.fill();

    // Vertical line
    try pb.setFillColor(fg);
    try pb.rect(0, 0, line_width, cell_size);
    try pb.fill();

    // Horizontal line
    try pb.rect(0, 0, cell_size, line_width);
    try pb.fill();

    const content = try allocator.dupe(u8, pb.getContent());
    return .{
        .bbox_width = cell_size,
        .bbox_height = cell_size,
        .x_step = cell_size,
        .y_step = cell_size,
        .content = content,
    };
}

/// Creates a checkerboard pattern.
/// `cell_size` is the size of each square in the checkerboard.
pub fn checkerboard(allocator: Allocator, fg: Color, bg: Color, cell_size: f32) !TilingPattern {
    var pb = PatternBuilder.init(allocator);
    defer pb.deinit();

    const double = cell_size * 2.0;

    // Background covers full 2x2 cell
    try pb.setFillColor(bg);
    try pb.rect(0, 0, double, double);
    try pb.fill();

    // Two foreground squares in a checkerboard arrangement
    try pb.setFillColor(fg);
    try pb.rect(0, 0, cell_size, cell_size);
    try pb.fill();
    try pb.rect(cell_size, cell_size, cell_size, cell_size);
    try pb.fill();

    const content = try allocator.dupe(u8, pb.getContent());
    return .{
        .bbox_width = double,
        .bbox_height = double,
        .x_step = double,
        .y_step = double,
        .content = content,
    };
}

/// Creates a diagonal stripes pattern.
/// `stripe_width` is the width of each stripe, `spacing` is the gap.
pub fn diagonalStripes(allocator: Allocator, fg: Color, bg: Color, stripe_width: f32, spacing: f32) !TilingPattern {
    var pb = PatternBuilder.init(allocator);
    defer pb.deinit();

    const cell = stripe_width + spacing;

    // Background
    try pb.setFillColor(bg);
    try pb.rect(0, 0, cell, cell);
    try pb.fill();

    // Diagonal stripe as a filled triangle/parallelogram
    try pb.setFillColor(fg);
    try pb.moveTo(0, 0);
    try pb.lineTo(stripe_width, 0);
    try pb.lineTo(cell, cell - stripe_width);
    try pb.lineTo(cell, cell);
    try pb.closePath();
    try pb.fill();

    // Second part to complete the diagonal across the tile boundary
    try pb.moveTo(0, cell - stripe_width);
    try pb.lineTo(0, cell);
    try pb.lineTo(stripe_width, cell);
    try pb.closePath();
    try pb.fill();

    const content = try allocator.dupe(u8, pb.getContent());
    return .{
        .bbox_width = cell,
        .bbox_height = cell,
        .x_step = cell,
        .y_step = cell,
        .content = content,
    };
}

/// Builds a PDF tiling pattern object in the object store.
/// Returns a reference to the Pattern object (PatternType 1).
pub fn buildTilingPattern(allocator: Allocator, store: *ObjectStore, pattern: TilingPattern) !Ref {
    const ref = try store.allocate();

    // Build BBox array
    var bbox = types.pdfArray(allocator);
    try bbox.array_obj.append(types.pdfReal(0.0));
    try bbox.array_obj.append(types.pdfReal(0.0));
    try bbox.array_obj.append(types.pdfReal(@floatCast(pattern.bbox_width)));
    try bbox.array_obj.append(types.pdfReal(@floatCast(pattern.bbox_height)));

    // Build the stream dict
    var dict: std.StringHashMapUnmanaged(PdfObject) = .{};
    try dict.put(allocator, "Type", types.pdfName("Pattern"));
    try dict.put(allocator, "PatternType", types.pdfInt(1));
    try dict.put(allocator, "PaintType", types.pdfInt(@intFromEnum(pattern.paint_type)));
    try dict.put(allocator, "TilingType", types.pdfInt(@intFromEnum(pattern.tiling_type)));
    try dict.put(allocator, "BBox", bbox);
    try dict.put(allocator, "XStep", types.pdfReal(@floatCast(pattern.x_step)));
    try dict.put(allocator, "YStep", types.pdfReal(@floatCast(pattern.y_step)));

    // Resources (empty dict, pattern draws with direct operators)
    try dict.put(allocator, "Resources", types.pdfDict(allocator));

    try dict.put(allocator, "Length", types.pdfInt(@intCast(pattern.content.len)));

    store.put(ref, .{ .stream_obj = .{
        .dict = dict,
        .data = pattern.content,
    } });

    return ref;
}

// ── Tests ───────────────────────────────────────────────────────────

test "PatternBuilder basic operations" {
    const allocator = std.testing.allocator;
    var pb = PatternBuilder.init(allocator);
    defer pb.deinit();

    try pb.setFillColor(.{ .rgb = .{ .r = 255, .g = 0, .b = 0 } });
    try pb.rect(0, 0, 10, 10);
    try pb.fill();

    const content = pb.getContent();
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "rg") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "re") != null);
}

test "stripes preset" {
    const allocator = std.testing.allocator;
    const fg = Color{ .named = .blue };
    const bg = Color{ .named = .white };
    const pat = try stripes(allocator, fg, bg, 5.0, 5.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pat.bbox_width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pat.bbox_height, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "dots preset" {
    const allocator = std.testing.allocator;
    const fg = Color{ .named = .red };
    const bg = Color{ .named = .white };
    const pat = try dots(allocator, fg, bg, 3.0, 12.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 12.0), pat.x_step, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "grid preset" {
    const allocator = std.testing.allocator;
    const fg = Color{ .named = .black };
    const bg = Color{ .named = .white };
    const pat = try grid(allocator, fg, bg, 1.0, 20.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pat.bbox_width, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "checkerboard preset" {
    const allocator = std.testing.allocator;
    const fg = Color{ .named = .black };
    const bg = Color{ .named = .white };
    const pat = try checkerboard(allocator, fg, bg, 10.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pat.bbox_width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pat.bbox_height, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "diagonalStripes preset" {
    const allocator = std.testing.allocator;
    const fg = Color{ .named = .red };
    const bg = Color{ .named = .white };
    const pat = try diagonalStripes(allocator, fg, bg, 4.0, 8.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 12.0), pat.x_step, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "buildTilingPattern creates stream object" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const content = "1 0 0 rg 0 0 10 10 re f";
    const pattern = TilingPattern{
        .bbox_width = 10,
        .bbox_height = 10,
        .x_step = 10,
        .y_step = 10,
        .content = content,
    };

    const ref = try buildTilingPattern(allocator, &store, pattern);
    try std.testing.expect(store.count() >= 1);

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isStream());
}
