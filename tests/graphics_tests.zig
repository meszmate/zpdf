const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const PathBuilder = zpdf.graphics.path_builder.PathBuilder;
const Matrix = zpdf.graphics.transform.Matrix;
const toPdfOperator = zpdf.graphics.transform.toPdfOperator;
const skew = zpdf.graphics.transform.skew;

test "PathBuilder: moveTo and lineTo produce operators" {
    var pb = PathBuilder.init(testing.allocator);
    defer pb.deinit();

    _ = pb.moveTo(10, 20);
    _ = pb.lineTo(30, 40);

    const result = try pb.toOperators(testing.allocator);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "10.0000 20.0000 m\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "30.0000 40.0000 l\n") != null);
}

test "PathBuilder: rect produces 5 operations" {
    var pb = PathBuilder.init(testing.allocator);
    defer pb.deinit();

    _ = pb.rect(0, 0, 100, 50);
    try testing.expectEqual(@as(usize, 5), pb.operations.items.len);
}

test "PathBuilder: circle produces 6 operations" {
    var pb = PathBuilder.init(testing.allocator);
    defer pb.deinit();

    _ = pb.circle(50, 50, 25);
    try testing.expectEqual(@as(usize, 6), pb.operations.items.len);
}

test "PathBuilder: chaining" {
    var pb = PathBuilder.init(testing.allocator);
    defer pb.deinit();

    _ = pb.moveTo(0, 0).lineTo(10, 0).lineTo(10, 10).close();
    try testing.expectEqual(@as(usize, 4), pb.operations.items.len);
}

test "Matrix: identity and transformPoint" {
    const m = Matrix.identity();
    try testing.expectApproxEqAbs(@as(f64, 1.0), m.a, 0.001);
    const p = m.transformPoint(3.0, 4.0);
    try testing.expectApproxEqAbs(@as(f64, 3.0), p.x, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 4.0), p.y, 0.001);
}

test "Matrix: translate and multiply" {
    const t = Matrix.translate(10.0, 20.0);
    const p = t.transformPoint(1.0, 2.0);
    try testing.expectApproxEqAbs(@as(f64, 11.0), p.x, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 22.0), p.y, 0.001);

    const s = Matrix.scale(2.0, 3.0);
    const m = t.multiply(s);
    const p2 = m.transformPoint(1.0, 1.0);
    try testing.expectApproxEqAbs(@as(f64, 22.0), p2.x, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 63.0), p2.y, 0.001);
}

test "Matrix: rotate 90 degrees" {
    const m = Matrix.rotate(std.math.pi / 2.0);
    const p = m.transformPoint(1.0, 0.0);
    try testing.expectApproxEqAbs(@as(f64, 0.0), p.x, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), p.y, 0.001);
}

test "toPdfOperator identity" {
    const m = Matrix.identity();
    const result = try toPdfOperator(m, testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("1.0000 0.0000 0.0000 1.0000 0.0000 0.0000 cm", result);
}

test "skew with zero angles is identity-like" {
    const m = skew(0.0, 0.0);
    try testing.expectApproxEqAbs(@as(f64, 1.0), m.a, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), m.b, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), m.c, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), m.d, 0.001);
}
