const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// A 2D point in PDF coordinate space.
pub const Point = struct {
    x: f64,
    y: f64,
};

/// Control points for a cubic Bezier curve.
pub const CubicBezier = struct {
    cp1: Point,
    cp2: Point,
    end: Point,
};

/// Control point for a quadratic Bezier curve.
pub const QuadBezier = struct {
    cp: Point,
    end: Point,
};

/// A single path construction operation.
pub const PathOp = union(enum) {
    move_to: Point,
    line_to: Point,
    curve_to: CubicBezier,
    quad_curve_to: QuadBezier,
    close,
};

/// Builds a vector path from a sequence of drawing operations.
/// Supports method chaining via pointer returns.
pub const PathBuilder = struct {
    operations: ArrayList(PathOp),
    allocator: Allocator,

    /// Initializes a new empty path builder.
    pub fn init(allocator: Allocator) PathBuilder {
        return .{
            .operations = .{},
            .allocator = allocator,
        };
    }

    /// Frees all path operations.
    pub fn deinit(self: *PathBuilder) void {
        self.operations.deinit(self.allocator);
    }

    /// Moves the current point to (x, y) without drawing.
    pub fn moveTo(self: *PathBuilder, x: f64, y: f64) *PathBuilder {
        self.operations.append(self.allocator, .{ .move_to = .{ .x = x, .y = y } }) catch {};
        return self;
    }

    /// Draws a straight line from the current point to (x, y).
    pub fn lineTo(self: *PathBuilder, x: f64, y: f64) *PathBuilder {
        self.operations.append(self.allocator, .{ .line_to = .{ .x = x, .y = y } }) catch {};
        return self;
    }

    /// Draws a cubic Bezier curve with control points (x1,y1), (x2,y2) and endpoint (x3,y3).
    pub fn curveTo(self: *PathBuilder, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) *PathBuilder {
        self.operations.append(self.allocator, .{ .curve_to = .{
            .cp1 = .{ .x = x1, .y = y1 },
            .cp2 = .{ .x = x2, .y = y2 },
            .end = .{ .x = x3, .y = y3 },
        } }) catch {};
        return self;
    }

    /// Draws a quadratic Bezier curve with control point (x1,y1) and endpoint (x2,y2).
    /// Internally converts to a cubic Bezier for PDF output.
    pub fn quadraticCurveTo(self: *PathBuilder, x1: f64, y1: f64, x2: f64, y2: f64) *PathBuilder {
        self.operations.append(self.allocator, .{ .quad_curve_to = .{
            .cp = .{ .x = x1, .y = y1 },
            .end = .{ .x = x2, .y = y2 },
        } }) catch {};
        return self;
    }

    /// Adds a rectangle subpath at (x, y) with dimensions w x h.
    pub fn rect(self: *PathBuilder, x: f64, y: f64, w: f64, h: f64) *PathBuilder {
        _ = self.moveTo(x, y);
        _ = self.lineTo(x + w, y);
        _ = self.lineTo(x + w, y + h);
        _ = self.lineTo(x, y + h);
        _ = self.close();
        return self;
    }

    /// Adds a rounded rectangle subpath at (x, y) with dimensions w x h and corner radius.
    pub fn roundRect(self: *PathBuilder, x: f64, y: f64, w: f64, h: f64, radius: f64) *PathBuilder {
        // Clamp radius to half the smaller dimension.
        const r = @min(radius, @min(w / 2.0, h / 2.0));
        // kappa for quarter-circle Bezier approximation
        const k: f64 = 0.5522847498;
        const kr = k * r;

        _ = self.moveTo(x + r, y);
        _ = self.lineTo(x + w - r, y);
        _ = self.curveTo(x + w - r + kr, y, x + w, y + r - kr, x + w, y + r);
        _ = self.lineTo(x + w, y + h - r);
        _ = self.curveTo(x + w, y + h - r + kr, x + w - r + kr, y + h, x + w - r, y + h);
        _ = self.lineTo(x + r, y + h);
        _ = self.curveTo(x + r - kr, y + h, x, y + h - r + kr, x, y + h - r);
        _ = self.lineTo(x, y + r);
        _ = self.curveTo(x, y + r - kr, x + r - kr, y, x + r, y);
        _ = self.close();
        return self;
    }

    /// Adds a circle subpath centered at (cx, cy) with radius r.
    /// Approximated using four cubic Bezier curves.
    pub fn circle(self: *PathBuilder, cx: f64, cy: f64, r: f64) *PathBuilder {
        return self.ellipse(cx, cy, r, r);
    }

    /// Adds an ellipse subpath centered at (cx, cy) with radii rx and ry.
    /// Approximated using four cubic Bezier curves.
    pub fn ellipse(self: *PathBuilder, cx: f64, cy: f64, rx: f64, ry: f64) *PathBuilder {
        const k: f64 = 0.5522847498;
        const kx = k * rx;
        const ky = k * ry;

        _ = self.moveTo(cx + rx, cy);
        _ = self.curveTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
        _ = self.curveTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
        _ = self.curveTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
        _ = self.curveTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
        _ = self.close();
        return self;
    }

    /// Closes the current subpath by drawing a straight line back to the starting point.
    pub fn close(self: *PathBuilder) *PathBuilder {
        self.operations.append(self.allocator, .close) catch {};
        return self;
    }

    /// Serializes all path operations to PDF content stream operators.
    /// Caller owns the returned memory.
    pub fn toOperators(self: *const PathBuilder, allocator: Allocator) ![]u8 {
        var buf: ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);

        for (self.operations.items, 0..) |op, op_idx| {
            switch (op) {
                .move_to => |p| {
                    try buf.writer(allocator).print("{d:.4} {d:.4} m\n", .{ p.x, p.y });
                },
                .line_to => |p| {
                    try buf.writer(allocator).print("{d:.4} {d:.4} l\n", .{ p.x, p.y });
                },
                .curve_to => |c| {
                    try buf.writer(allocator).print("{d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} c\n", .{
                        c.cp1.x, c.cp1.y, c.cp2.x, c.cp2.y, c.end.x, c.end.y,
                    });
                },
                .quad_curve_to => |q| {
                    // Convert quadratic Bezier to cubic.
                    // Find the current point by scanning backwards.
                    const cur = findCurrentPoint(self.operations.items, op_idx);
                    const cp1_x = cur.x + (2.0 / 3.0) * (q.cp.x - cur.x);
                    const cp1_y = cur.y + (2.0 / 3.0) * (q.cp.y - cur.y);
                    const cp2_x = q.end.x + (2.0 / 3.0) * (q.cp.x - q.end.x);
                    const cp2_y = q.end.y + (2.0 / 3.0) * (q.cp.y - q.end.y);
                    try buf.writer(allocator).print("{d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} c\n", .{
                        cp1_x, cp1_y, cp2_x, cp2_y, q.end.x, q.end.y,
                    });
                },
                .close => {
                    try buf.writer(allocator).print("h\n", .{});
                },
            }
        }

        return buf.toOwnedSlice(allocator);
    }
};

/// Finds the current point before the operation at the given index.
fn findCurrentPoint(ops: []const PathOp, target_idx: usize) Point {
    var current = Point{ .x = 0, .y = 0 };
    for (ops[0..target_idx]) |op| {
        switch (op) {
            .move_to => |p| current = p,
            .line_to => |p| current = p,
            .curve_to => |c| current = c.end,
            .quad_curve_to => |q| current = q.end,
            .close => {},
        }
    }
    return current;
}

// -- Tests --

test "path builder: line" {
    var pb = PathBuilder.init(std.testing.allocator);
    defer pb.deinit();

    _ = pb.moveTo(10, 20);
    _ = pb.lineTo(30, 40);

    const result = try pb.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "10.0000 20.0000 m\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "30.0000 40.0000 l\n") != null);
}

test "path builder: rect" {
    var pb = PathBuilder.init(std.testing.allocator);
    defer pb.deinit();

    _ = pb.rect(0, 0, 100, 50);

    // moveTo + 3 lineTo + close = 5
    try std.testing.expectEqual(@as(usize, 5), pb.operations.items.len);
}

test "path builder: circle" {
    var pb = PathBuilder.init(std.testing.allocator);
    defer pb.deinit();

    _ = pb.circle(50, 50, 25);

    // 1 moveTo + 4 curveTo + 1 close = 6
    try std.testing.expectEqual(@as(usize, 6), pb.operations.items.len);
}

test "path builder: chaining" {
    var pb = PathBuilder.init(std.testing.allocator);
    defer pb.deinit();

    _ = pb.moveTo(0, 0).lineTo(10, 0).lineTo(10, 10).close();

    try std.testing.expectEqual(@as(usize, 4), pb.operations.items.len);
}

test "path builder: close operator" {
    var pb = PathBuilder.init(std.testing.allocator);
    defer pb.deinit();

    _ = pb.moveTo(0, 0).lineTo(10, 0).close();

    const result = try pb.toOperators(std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "h\n") != null);
}
