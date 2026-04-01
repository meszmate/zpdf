const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const upca = zpdf.barcode.upca;
const ean8 = zpdf.barcode.ean8;

// -- UPC-A Tests --

test "UPC-A: check digit calculation" {
    // "03600029145" => check digit 2
    const check = upca.calculateCheckDigit("03600029145");
    try testing.expectEqual(@as(u8, 2), check);
}

test "UPC-A: check digit for another value" {
    // "01234567890" => EAN-13 check of "001234567890"
    // Weights: 0*1+0*3+1*1+2*3+3*1+4*3+5*1+6*3+7*1+8*3+9*1+0*3 = 0+0+1+6+3+12+5+18+7+24+9+0 = 85
    // 85 % 10 = 5, check = 5
    const check = upca.calculateCheckDigit("01234567890");
    try testing.expectEqual(@as(u8, 5), check);
}

test "UPC-A: encode with 11 digits produces 95 modules" {
    const result = try upca.encode(testing.allocator, "03600029145");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 95), result.len);
}

test "UPC-A: encode with 12 digits produces 95 modules" {
    const result = try upca.encode(testing.allocator, "036000291452");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 95), result.len);
}

test "UPC-A: render produces PDF operators" {
    const result = try upca.render(testing.allocator, "036000291452", 10, 20, 200, 80);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "re f\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "UPC-A: invalid length rejected" {
    try testing.expectError(error.InvalidLength, upca.encode(testing.allocator, "123"));
}

test "UPC-A: invalid characters rejected" {
    try testing.expectError(error.InvalidCharacter, upca.encode(testing.allocator, "0360002914A"));
}

// -- EAN-8 Tests --

test "EAN-8: check digit calculation" {
    const check = ean8.calculateCheckDigit("9638507");
    try testing.expectEqual(@as(u8, 4), check);
}

test "EAN-8: check digit for 1234567" {
    const check = ean8.calculateCheckDigit("1234567");
    try testing.expectEqual(@as(u8, 0), check);
}

test "EAN-8: encode with 7 digits produces 67 modules" {
    const result = try ean8.encode(testing.allocator, "9638507");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 67), result.len);
}

test "EAN-8: encode with 8 digits produces 67 modules" {
    const result = try ean8.encode(testing.allocator, "96385074");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 67), result.len);
}

test "EAN-8: encode starts with start guard" {
    const result = try ean8.encode(testing.allocator, "96385074");
    defer testing.allocator.free(result);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 1 }, result[0..3]);
}

test "EAN-8: encode ends with end guard" {
    const result = try ean8.encode(testing.allocator, "96385074");
    defer testing.allocator.free(result);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 1 }, result[64..67]);
}

test "EAN-8: render produces PDF operators" {
    const result = try ean8.render(testing.allocator, "96385074", 10, 20, 200, 80);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "re f\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "EAN-8: invalid length rejected" {
    try testing.expectError(error.InvalidLength, ean8.encode(testing.allocator, "123"));
}

test "EAN-8: invalid characters rejected" {
    try testing.expectError(error.InvalidCharacter, ean8.encode(testing.allocator, "963850A"));
}
