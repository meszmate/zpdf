const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const data_matrix = zpdf.barcode.data_matrix;

test "DataMatrix: ASCII encoding single character" {
    const result = try data_matrix.encodeAscii(testing.allocator, "A");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    // 'A' = 65, encoded as 65 + 1 = 66
    try testing.expectEqual(@as(u8, 66), result[0]);
}

test "DataMatrix: ASCII encoding digit pair" {
    const result = try data_matrix.encodeAscii(testing.allocator, "42");
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    // digit pair "42" -> 4*10 + 2 + 130 = 172
    try testing.expectEqual(@as(u8, 172), result[0]);
}

test "DataMatrix: ASCII encoding mixed" {
    const result = try data_matrix.encodeAscii(testing.allocator, "A1");
    defer testing.allocator.free(result);
    // 'A' is not a digit, so no digit pair: 'A'+1=66, '1'+1=50
    try testing.expectEqual(@as(usize, 2), result.len);
    try testing.expectEqual(@as(u8, 66), result[0]);
    try testing.expectEqual(@as(u8, 50), result[1]);
}

test "DataMatrix: symbol size selection small" {
    const s = data_matrix.selectSymbolSize(1);
    try testing.expect(s != null);
    try testing.expectEqual(@as(u16, 10), s.?.rows);
    try testing.expectEqual(@as(u16, 10), s.?.cols);
}

test "DataMatrix: symbol size selection medium" {
    const s = data_matrix.selectSymbolSize(20);
    try testing.expect(s != null);
    try testing.expectEqual(@as(u16, 20), s.?.rows);
}

test "DataMatrix: symbol size selection too large" {
    const s = data_matrix.selectSymbolSize(2000);
    try testing.expect(s == null);
}

test "DataMatrix: render produces content" {
    const result = try data_matrix.render(testing.allocator, "Hello zpdf!", 0, 0, 100, 100);
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "re f\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "DataMatrix: render short data" {
    const result = try data_matrix.render(testing.allocator, "Z", 10, 20, 50, 50);
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
}

test "DataMatrix: render numeric data" {
    const result = try data_matrix.render(testing.allocator, "0123456789", 0, 0, 80, 80);
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
}

test "DataMatrix: render longer data" {
    const result = try data_matrix.render(testing.allocator, "The quick brown fox jumps over the lazy dog", 0, 0, 200, 200);
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
}

test "DataMatrix: drawBarcode dispatch" {
    const drawBarcode = zpdf.drawBarcode;
    const BarcodeOptions = zpdf.barcode.barcode_api.BarcodeOptions;

    const result = try drawBarcode(testing.allocator, BarcodeOptions{
        .barcode_type = .data_matrix,
        .value = "TEST",
        .x = 0,
        .y = 0,
        .width = 100,
        .height = 100,
    });
    defer testing.allocator.free(result);
    try testing.expect(result.len > 0);
}
