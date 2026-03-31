const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const ByteBuffer = zpdf.utils.buffer.ByteBuffer;
const string_utils = zpdf.utils.string_utils;
const Matrix = zpdf.utils.math.Matrix;

test "ByteBuffer: write and read back" {
    var buf = ByteBuffer.init(testing.allocator);
    defer buf.deinit();

    try buf.write("hello");
    try testing.expectEqualSlices(u8, "hello", buf.items());
    try testing.expectEqual(@as(usize, 5), buf.len());
}

test "ByteBuffer: writeInt big-endian" {
    var buf = ByteBuffer.init(testing.allocator);
    defer buf.deinit();

    try buf.writeInt(u32, 0x01020304);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03, 0x04 }, buf.items());
}

test "ByteBuffer: toOwnedSlice resets buffer" {
    var buf = ByteBuffer.init(testing.allocator);
    defer buf.deinit();

    try buf.write("data");
    const slice = try buf.toOwnedSlice();
    defer testing.allocator.free(slice);
    try testing.expectEqualSlices(u8, "data", slice);
    try testing.expectEqual(@as(usize, 0), buf.len());
}

test "escapePdfString escapes parens and backslash" {
    const result = try string_utils.escapePdfString(testing.allocator, "hello (world) \\ end");
    defer testing.allocator.free(result);
    try testing.expectEqualSlices(u8, "hello \\(world\\) \\\\ end", result);
}

test "toHexString" {
    const result = try string_utils.toHexString(testing.allocator, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF });
    defer testing.allocator.free(result);
    try testing.expectEqualSlices(u8, "deadbeef", result);
}

test "CRC32: known values" {
    const crc32 = zpdf.utils.crc32;
    try testing.expectEqual(@as(u32, 0x00000000), crc32.compute(""));
    try testing.expectEqual(@as(u32, 0xCBF43926), crc32.compute("123456789"));
    try testing.expectEqual(@as(u32, 0xF7D18982), crc32.compute("Hello"));
}

test "Matrix: identity transforms point unchanged" {
    const m = Matrix.identity();
    const p = m.transformPoint(3.0, 4.0);
    try testing.expectApproxEqAbs(@as(f64, 3.0), p.x, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 4.0), p.y, 0.001);
}

test "Matrix: scale and invert roundtrip" {
    const m = Matrix.scale(2.0, 4.0);
    const inv = m.invert() orelse unreachable;
    const p = inv.transformPoint(6.0, 12.0);
    try testing.expectApproxEqAbs(@as(f64, 3.0), p.x, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 3.0), p.y, 0.001);
}

test "Matrix: singular matrix returns null on invert" {
    const m = Matrix{ .a = 0, .b = 0, .c = 0, .d = 0, .e = 0, .f = 0 };
    try testing.expect(m.invert() == null);
}
