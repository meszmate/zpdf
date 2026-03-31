const std = @import("std");
const Allocator = std.mem.Allocator;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;

/// PDF line cap style.
pub const LineCap = enum(u8) {
    butt = 0,
    round = 1,
    projecting_square = 2,
};

/// PDF line join style.
pub const LineJoin = enum(u8) {
    miter = 0,
    round = 1,
    bevel = 2,
};

/// A dash pattern for stroked lines.
pub const DashPattern = struct {
    array: []const f64,
    phase: f64,
};

/// Holds the current graphics state for PDF content stream rendering.
pub const GraphicsState = struct {
    line_width: f64 = 1.0,
    line_cap: LineCap = .butt,
    line_join: LineJoin = .miter,
    miter_limit: f64 = 10.0,
    dash_pattern: ?DashPattern = null,
    fill_color: ?Color = null,
    stroke_color: ?Color = null,
    fill_opacity: f64 = 1.0,
    stroke_opacity: f64 = 1.0,

    /// Serializes the graphics state to PDF content stream operators.
    /// Only emits operators for non-default values.
    /// Caller owns the returned memory.
    pub fn toOperators(self: *const GraphicsState, allocator: Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        const writer = buf.writer(allocator);

        // Line width
        if (self.line_width != 1.0) {
            try writer.print("{d:.4} w\n", .{self.line_width});
        }

        // Line cap
        if (self.line_cap != .butt) {
            try writer.print("{d} J\n", .{@intFromEnum(self.line_cap)});
        }

        // Line join
        if (self.line_join != .miter) {
            try writer.print("{d} j\n", .{@intFromEnum(self.line_join)});
        }

        // Miter limit
        if (self.miter_limit != 10.0) {
            try writer.print("{d:.4} M\n", .{self.miter_limit});
        }

        // Dash pattern
        if (self.dash_pattern) |dash| {
            try writer.print("[", .{});
            for (dash.array, 0..) |val, i| {
                if (i > 0) try writer.print(" ", .{});
                try writer.print("{d:.4}", .{val});
            }
            try writer.print("] {d:.4} d\n", .{dash.phase});
        }

        // Fill color
        if (self.fill_color) |fc| {
            try fc.writeColorOps(writer, true);
        }

        // Stroke color
        if (self.stroke_color) |sc| {
            try sc.writeColorOps(writer, false);
        }

        return buf.toOwnedSlice(allocator);
    }
};

// -- Tests --

test "default state produces empty output" {
    const state = GraphicsState{};
    const result = try state.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "line width operator" {
    const state = GraphicsState{ .line_width = 2.5 };
    const result = try state.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "2.5000 w\n") != null);
}

test "fill color operator" {
    const state = GraphicsState{
        .fill_color = color_mod.rgb(255, 0, 0),
    };
    const result = try state.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "rg\n") != null);
}

test "stroke color operator" {
    const state = GraphicsState{
        .stroke_color = color_mod.rgb(0, 0, 255),
    };
    const result = try state.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "RG\n") != null);
}

test "line cap operator" {
    const state = GraphicsState{ .line_cap = .round };
    const result = try state.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "1 J\n") != null);
}

test "dash pattern operator" {
    const dash_array = [_]f64{ 5.0, 3.0 };
    const state = GraphicsState{
        .dash_pattern = .{ .array = &dash_array, .phase = 0.0 },
    };
    const result = try state.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[5.0000 3.0000] 0.0000 d\n") != null);
}
