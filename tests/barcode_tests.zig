const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const code39 = zpdf.barcode.code39;
const code128 = zpdf.barcode.code128;
const ean13 = zpdf.barcode.ean13;

test "Code39: encode produces output" {
    const result = try code39.encode(testing.allocator, "HELLO");
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
}

test "Code39: lowercase converted to uppercase" {
    const lower = try code39.encode(testing.allocator, "abc");
    defer testing.allocator.free(lower);
    const upper = try code39.encode(testing.allocator, "ABC");
    defer testing.allocator.free(upper);
    try testing.expectEqualSlices(u8, upper, lower);
}

test "Code39: render produces PDF operators" {
    const result = try code39.render(testing.allocator, "123", 0, 0, 200, 50);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "Code128: encode produces output with start/stop" {
    const result = try code128.encode(testing.allocator, "Hello");
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
    // Ends with stop pattern (7 elements: 2,3,3,1,1,1,2)
    try testing.expectEqualSlices(u8, &[_]u8{ 2, 3, 3, 1, 1, 1, 2 }, result[result.len - 7 ..]);
}

test "Code128: render produces PDF operators" {
    const result = try code128.render(testing.allocator, "123", 10, 20, 200, 50);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "re f\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "EAN13: check digit calculation" {
    const check = ean13.calculateCheckDigit("590123412345");
    try testing.expectEqual(@as(u8, 7), check);
}

test "EAN13: check digit for zeros" {
    const check = ean13.calculateCheckDigit("000000000000");
    try testing.expectEqual(@as(u8, 0), check);
}

test "EAN13: encode produces 95 modules" {
    const result = try ean13.encode(testing.allocator, "5901234123457");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 95), result.len);
}

test "EAN13: short input rejected" {
    try testing.expectError(error.InvalidLength, ean13.encode(testing.allocator, "123"));
}
