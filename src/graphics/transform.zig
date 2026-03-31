const std = @import("std");
const Allocator = std.mem.Allocator;
pub const math = @import("../utils/math.zig");
pub const Matrix = math.Matrix;

/// Creates a skew transformation matrix from angles in radians.
/// angle_x skews along the x-axis, angle_y skews along the y-axis.
pub fn skew(angle_x: f64, angle_y: f64) Matrix {
    return .{
        .a = 1.0,
        .b = @tan(angle_y),
        .c = @tan(angle_x),
        .d = 1.0,
        .e = 0.0,
        .f = 0.0,
    };
}

/// Serializes a transformation matrix to the PDF "cm" operator string.
/// Returns "a b c d e f cm" formatted for a content stream.
/// Caller owns the returned memory.
pub fn toPdfOperator(m: Matrix, allocator: Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} cm", .{
        m.a, m.b, m.c, m.d, m.e, m.f,
    });
}

// -- Tests --

test "skew produces expected values" {
    const m = skew(0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), m.a, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), m.b, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), m.c, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), m.d, 0.001);
}

test "skew with 45 degrees" {
    const angle = std.math.pi / 4.0;
    const m = skew(angle, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), m.c, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), m.b, 0.001);
}

test "toPdfOperator identity" {
    const m = Matrix.identity();
    const result = try toPdfOperator(m, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("1.0000 0.0000 0.0000 1.0000 0.0000 0.0000 cm", result);
}

test "toPdfOperator translation" {
    const m = Matrix.translation(100.0, 200.0);
    const result = try toPdfOperator(m, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("1.0000 0.0000 0.0000 1.0000 100.0000 200.0000 cm", result);
}

test "re-exported Matrix works" {
    const m = Matrix.scaling(2.0, 3.0);
    const pt = m.transformPoint(1.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), pt.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), pt.y, 0.001);
}
