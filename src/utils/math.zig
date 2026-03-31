const std = @import("std");

/// A 2D affine transformation matrix represented in PDF form as [a, b, c, d, e, f].
/// The full matrix is:
///   | a  b  0 |
///   | c  d  0 |
///   | e  f  1 |
///
/// A point (x, y) is transformed as:
///   x' = a*x + c*y + e
///   y' = b*x + d*y + f
pub const Matrix = struct {
    a: f64 = 1.0,
    b: f64 = 0.0,
    c: f64 = 0.0,
    d: f64 = 1.0,
    e: f64 = 0.0,
    f: f64 = 0.0,

    /// Returns the identity matrix.
    pub fn identity() Matrix {
        return .{};
    }

    /// Creates a translation matrix.
    pub fn translate(tx: f64, ty: f64) Matrix {
        return .{ .e = tx, .f = ty };
    }

    /// Alias for translate, for backward compatibility.
    pub const translation = translate;

    /// Creates a scaling matrix.
    pub fn scale(sx: f64, sy: f64) Matrix {
        return .{ .a = sx, .d = sy };
    }

    /// Alias for scale, for backward compatibility.
    pub const scaling = scale;

    /// Creates a rotation matrix for the given angle in radians.
    pub fn rotate(angle: f64) Matrix {
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        return .{ .a = cos_a, .b = sin_a, .c = -sin_a, .d = cos_a };
    }

    /// Alias for rotate, for backward compatibility.
    pub const rotation = rotate;

    /// Multiplies two matrices: self * other.
    pub fn multiply(self: Matrix, other: Matrix) Matrix {
        return .{
            .a = self.a * other.a + self.b * other.c,
            .b = self.a * other.b + self.b * other.d,
            .c = self.c * other.a + self.d * other.c,
            .d = self.c * other.b + self.d * other.d,
            .e = self.e * other.a + self.f * other.c + other.e,
            .f = self.e * other.b + self.f * other.d + other.f,
        };
    }

    /// Transforms a point (x, y) by this matrix.
    /// Returns a struct with named x and y fields.
    pub fn transformPoint(self: Matrix, x: f64, y: f64) struct { x: f64, y: f64 } {
        return .{
            .x = self.a * x + self.c * y + self.e,
            .y = self.b * x + self.d * y + self.f,
        };
    }

    /// Compute the inverse of this matrix. Returns null if the matrix is singular
    /// (i.e., the determinant is effectively zero).
    pub fn invert(self: Matrix) ?Matrix {
        const det = self.a * self.d - self.b * self.c;
        if (@abs(det) < 1e-12) return null;

        const inv_det = 1.0 / det;
        return .{
            .a = self.d * inv_det,
            .b = -self.b * inv_det,
            .c = -self.c * inv_det,
            .d = self.a * inv_det,
            .e = (self.c * self.f - self.d * self.e) * inv_det,
            .f = (self.b * self.e - self.a * self.f) * inv_det,
        };
    }
};

fn expectApprox(expected: f64, actual: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 1e-9);
}

test "Matrix: identity" {
    const m = Matrix.identity();
    try expectApprox(1.0, m.a);
    try expectApprox(0.0, m.b);
    try expectApprox(0.0, m.c);
    try expectApprox(1.0, m.d);
    try expectApprox(0.0, m.e);
    try expectApprox(0.0, m.f);
}

test "Matrix: identity transforms point unchanged" {
    const m = Matrix.identity();
    const p = m.transformPoint(3.0, 4.0);
    try expectApprox(3.0, p.x);
    try expectApprox(4.0, p.y);
}

test "Matrix: translate" {
    const m = Matrix.translate(10.0, 20.0);
    const p = m.transformPoint(1.0, 2.0);
    try expectApprox(11.0, p.x);
    try expectApprox(22.0, p.y);
}

test "Matrix: translate origin" {
    const m = Matrix.translate(10.0, 20.0);
    const p = m.transformPoint(0.0, 0.0);
    try expectApprox(10.0, p.x);
    try expectApprox(20.0, p.y);
}

test "Matrix: scale" {
    const m = Matrix.scale(2.0, 3.0);
    const p = m.transformPoint(5.0, 7.0);
    try expectApprox(10.0, p.x);
    try expectApprox(21.0, p.y);
}

test "Matrix: rotate 90 degrees" {
    const m = Matrix.rotate(std.math.pi / 2.0);
    const p = m.transformPoint(1.0, 0.0);
    try expectApprox(0.0, p.x);
    try expectApprox(1.0, p.y);
}

test "Matrix: multiply identity" {
    const a = Matrix.identity();
    const b = Matrix.translate(5.0, 10.0);
    const c = a.multiply(b);
    try expectApprox(5.0, c.e);
    try expectApprox(10.0, c.f);
}

test "Matrix: multiply translate then scale" {
    const t = Matrix.translate(5.0, 10.0);
    const s = Matrix.scale(2.0, 3.0);
    const m = t.multiply(s);
    // translate(5,10) then scale(2,3): (1,1) -> (6,11) -> (12,33)
    const p = m.transformPoint(1.0, 1.0);
    try expectApprox(12.0, p.x);
    try expectApprox(33.0, p.y);
}

test "Matrix: multiply scale then translate" {
    const s = Matrix.scale(2.0, 3.0);
    const t = Matrix.translate(10.0, 20.0);
    const m = s.multiply(t);
    const p = m.transformPoint(1.0, 1.0);
    try expectApprox(12.0, p.x);
    try expectApprox(23.0, p.y);
}

test "Matrix: invert identity" {
    const inv = Matrix.identity().invert() orelse unreachable;
    try expectApprox(1.0, inv.a);
    try expectApprox(0.0, inv.b);
    try expectApprox(0.0, inv.c);
    try expectApprox(1.0, inv.d);
}

test "Matrix: invert translation" {
    const m = Matrix.translate(5.0, 10.0);
    const inv = m.invert() orelse unreachable;
    const p = inv.transformPoint(5.0, 10.0);
    try expectApprox(0.0, p.x);
    try expectApprox(0.0, p.y);
}

test "Matrix: invert scale" {
    const m = Matrix.scale(2.0, 4.0);
    const inv = m.invert() orelse unreachable;
    const p = inv.transformPoint(6.0, 12.0);
    try expectApprox(3.0, p.x);
    try expectApprox(3.0, p.y);
}

test "Matrix: invert singular returns null" {
    const m = Matrix{ .a = 0, .b = 0, .c = 0, .d = 0, .e = 0, .f = 0 };
    try std.testing.expect(m.invert() == null);
}

test "Matrix: multiply then invert roundtrip" {
    const s = Matrix.scale(2.0, 3.0);
    const t = Matrix.translate(10.0, 20.0);
    const m = s.multiply(t);
    const inv = m.invert() orelse unreachable;
    const combined = m.multiply(inv);
    try expectApprox(1.0, combined.a);
    try expectApprox(0.0, combined.b);
    try expectApprox(0.0, combined.c);
    try expectApprox(1.0, combined.d);
    try expectApprox(0.0, combined.e);
    try expectApprox(0.0, combined.f);
}

test "Matrix: backward compatibility aliases" {
    // Ensure the old names still work
    const t = Matrix.translation(10.0, 20.0);
    const s = Matrix.scaling(2.0, 3.0);
    const r = Matrix.rotation(0.0);
    _ = t;
    _ = s;
    _ = r;
}
