const std = @import("std");
const Allocator = std.mem.Allocator;

/// PNG filter types as used in PDF predictor filters.
pub const PngFilter = enum(u8) {
    none = 0,
    sub = 1,
    up = 2,
    average = 3,
    paeth = 4,
};

/// PDF predictor values.
/// - 1: No prediction
/// - 2: TIFF Predictor 2
/// - 10: PNG None
/// - 11: PNG Sub
/// - 12: PNG Up
/// - 13: PNG Average
/// - 14: PNG Paeth
/// - 15: PNG Optimum (per-row optimal filter)
pub const Predictor = enum(u8) {
    none = 1,
    tiff = 2,
    png_none = 10,
    png_sub = 11,
    png_up = 12,
    png_average = 13,
    png_paeth = 14,
    png_optimum = 15,
};

/// Applies a predictor filter to data for improved compression.
///
/// Parameters:
/// - allocator: Memory allocator for the result buffer.
/// - data: Raw pixel/sample data organized in rows of `columns * bytes_per_pixel` bytes.
/// - predictor: The predictor type to apply.
/// - columns: Number of samples per row.
/// - colors: Number of color components per sample.
/// - bits_per_component: Bits per color component (1, 2, 4, 8, or 16).
///
/// Returns filtered data. For PNG predictors, each row is prefixed with a
/// filter-type byte. The caller owns the returned slice.
pub fn applyPredictor(
    allocator: Allocator,
    data: []const u8,
    predictor: u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
) ![]u8 {
    const pred = toPredictor(predictor) orelse return error.InvalidPredictor;

    switch (pred) {
        .none => {
            const result = try allocator.alloc(u8, data.len);
            @memcpy(result, data);
            return result;
        },
        .tiff => return applyTiffPredictor(allocator, data, columns, colors, bits_per_component),
        .png_none, .png_sub, .png_up, .png_average, .png_paeth => {
            const filter: PngFilter = switch (pred) {
                .png_none => .none,
                .png_sub => .sub,
                .png_up => .up,
                .png_average => .average,
                .png_paeth => .paeth,
                else => unreachable,
            };
            return applyPngFilter(allocator, data, columns, colors, bits_per_component, filter);
        },
        .png_optimum => return applyPngOptimum(allocator, data, columns, colors, bits_per_component),
    }
}

/// Removes a predictor filter from data after decompression.
///
/// Parameters:
/// - allocator: Memory allocator for the result buffer.
/// - data: Filtered data. For PNG predictors, each row must be prefixed with
///   a filter-type byte.
/// - predictor: The predictor type to remove.
/// - columns: Number of samples per row.
/// - colors: Number of color components per sample.
/// - bits_per_component: Bits per color component (1, 2, 4, 8, or 16).
///
/// Returns the original unfiltered data. The caller owns the returned slice.
pub fn removePredictor(
    allocator: Allocator,
    data: []const u8,
    predictor: u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
) ![]u8 {
    const pred = toPredictor(predictor) orelse return error.InvalidPredictor;

    switch (pred) {
        .none => {
            const result = try allocator.alloc(u8, data.len);
            @memcpy(result, data);
            return result;
        },
        .tiff => return removeTiffPredictor(allocator, data, columns, colors, bits_per_component),
        .png_none, .png_sub, .png_up, .png_average, .png_paeth, .png_optimum => {
            return removePngFilter(allocator, data, columns, colors, bits_per_component);
        },
    }
}

fn toPredictor(value: u8) ?Predictor {
    return switch (value) {
        1 => .none,
        2 => .tiff,
        10 => .png_none,
        11 => .png_sub,
        12 => .png_up,
        13 => .png_average,
        14 => .png_paeth,
        15 => .png_optimum,
        else => null,
    };
}

/// Bytes per pixel, rounded up (minimum 1).
fn bytesPerPixel(colors: u8, bits_per_component: u8) usize {
    const bits: usize = @as(usize, colors) * @as(usize, bits_per_component);
    return @max(1, bits / 8);
}

/// Row stride in bytes.
fn rowStride(columns: u32, colors: u8, bits_per_component: u8) usize {
    const total_bits: usize = @as(usize, columns) * @as(usize, colors) * @as(usize, bits_per_component);
    return (total_bits + 7) / 8;
}

// ── PNG filter application ──────────────────────────────────────────────

fn applyPngFilter(
    allocator: Allocator,
    data: []const u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
    filter: PngFilter,
) ![]u8 {
    const stride = rowStride(columns, colors, bits_per_component);
    const bpp = bytesPerPixel(colors, bits_per_component);

    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const num_rows = data.len / stride;
    if (num_rows * stride != data.len) return error.InvalidDataLength;

    // Output has filter byte + row data for each row
    const out_len = num_rows * (1 + stride);
    var result = try allocator.alloc(u8, out_len);
    errdefer allocator.free(result);

    var row: usize = 0;
    while (row < num_rows) : (row += 1) {
        const src_row = data[row * stride ..][0..stride];
        const prev_row: ?[]const u8 = if (row > 0) data[(row - 1) * stride ..][0..stride] else null;
        const dst_offset = row * (1 + stride);

        result[dst_offset] = @intFromEnum(filter);
        const dst_row = result[dst_offset + 1 ..][0..stride];

        switch (filter) {
            .none => @memcpy(dst_row, src_row),
            .sub => filterSub(dst_row, src_row, bpp),
            .up => filterUp(dst_row, src_row, prev_row),
            .average => filterAverage(dst_row, src_row, prev_row, bpp),
            .paeth => filterPaeth(dst_row, src_row, prev_row, bpp),
        }
    }

    return result;
}

fn applyPngOptimum(
    allocator: Allocator,
    data: []const u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
) ![]u8 {
    const stride = rowStride(columns, colors, bits_per_component);
    const bpp = bytesPerPixel(colors, bits_per_component);

    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const num_rows = data.len / stride;
    if (num_rows * stride != data.len) return error.InvalidDataLength;

    const out_len = num_rows * (1 + stride);
    var result = try allocator.alloc(u8, out_len);
    errdefer allocator.free(result);

    // Temporary buffers for trying each filter
    var candidates: [5][]u8 = undefined;
    for (&candidates) |*c| {
        c.* = try allocator.alloc(u8, stride);
    }
    defer for (&candidates) |c| allocator.free(c);

    var row: usize = 0;
    while (row < num_rows) : (row += 1) {
        const src_row = data[row * stride ..][0..stride];
        const prev_row: ?[]const u8 = if (row > 0) data[(row - 1) * stride ..][0..stride] else null;
        const dst_offset = row * (1 + stride);

        // Try all five filters and pick the one with minimum absolute sum
        filterNone(candidates[0], src_row);
        filterSub(candidates[1], src_row, bpp);
        filterUp(candidates[2], src_row, prev_row);
        filterAverage(candidates[3], src_row, prev_row, bpp);
        filterPaeth(candidates[4], src_row, prev_row, bpp);

        var best_filter: u8 = 0;
        var best_sum: u64 = absoluteSum(candidates[0]);

        for (1..5) |f| {
            const s = absoluteSum(candidates[f]);
            if (s < best_sum) {
                best_sum = s;
                best_filter = @intCast(f);
            }
        }

        result[dst_offset] = best_filter;
        @memcpy(result[dst_offset + 1 ..][0..stride], candidates[best_filter]);
    }

    return result;
}

fn absoluteSum(data: []const u8) u64 {
    var sum: u64 = 0;
    for (data) |b| {
        // Interpret as signed for better heuristic
        const signed: i8 = @bitCast(b);
        sum += @abs(signed);
    }
    return sum;
}

fn filterNone(dst: []u8, src: []const u8) void {
    @memcpy(dst, src);
}

fn filterSub(dst: []u8, src: []const u8, bpp: usize) void {
    for (dst, 0..) |*d, i| {
        const a: u8 = if (i >= bpp) src[i - bpp] else 0;
        d.* = src[i] -% a;
    }
}

fn filterUp(dst: []u8, src: []const u8, prev: ?[]const u8) void {
    for (dst, 0..) |*d, i| {
        const b: u8 = if (prev) |p| p[i] else 0;
        d.* = src[i] -% b;
    }
}

fn filterAverage(dst: []u8, src: []const u8, prev: ?[]const u8, bpp: usize) void {
    for (dst, 0..) |*d, i| {
        const a: u16 = if (i >= bpp) src[i - bpp] else 0;
        const b: u16 = if (prev) |p| p[i] else 0;
        d.* = src[i] -% @as(u8, @intCast((a + b) / 2));
    }
}

fn filterPaeth(dst: []u8, src: []const u8, prev: ?[]const u8, bpp: usize) void {
    for (dst, 0..) |*d, i| {
        const a: u8 = if (i >= bpp) src[i - bpp] else 0;
        const b: u8 = if (prev) |p| p[i] else 0;
        const c: u8 = if (prev) |p| (if (i >= bpp) p[i - bpp] else 0) else 0;
        d.* = src[i] -% paethPredictor(a, b, c);
    }
}

/// The Paeth predictor function (RFC 2083).
///
/// Returns the value among a, b, c that is closest to p = a + b - c.
fn paethPredictor(a: u8, b: u8, c: u8) u8 {
    const p: i16 = @as(i16, a) + @as(i16, b) - @as(i16, c);
    const pa = @abs(p - @as(i16, a));
    const pb = @abs(p - @as(i16, b));
    const pc = @abs(p - @as(i16, c));

    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

// ── PNG filter removal (decompression) ──────────────────────────────────

fn removePngFilter(
    allocator: Allocator,
    data: []const u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
) ![]u8 {
    const stride = rowStride(columns, colors, bits_per_component);
    const bpp = bytesPerPixel(colors, bits_per_component);

    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    // Each input row has a filter byte + stride data bytes
    const in_row_len = 1 + stride;
    const num_rows = data.len / in_row_len;
    if (num_rows * in_row_len != data.len) return error.InvalidDataLength;

    var result = try allocator.alloc(u8, num_rows * stride);
    errdefer allocator.free(result);

    var row: usize = 0;
    while (row < num_rows) : (row += 1) {
        const in_offset = row * in_row_len;
        const filter_byte = data[in_offset];
        const src_row = data[in_offset + 1 ..][0..stride];
        const prev_row: ?[]const u8 = if (row > 0) result[(row - 1) * stride ..][0..stride] else null;
        const dst_row = result[row * stride ..][0..stride];

        const filter: PngFilter = std.meta.intToEnum(PngFilter, filter_byte) catch
            return error.InvalidPngFilter;

        switch (filter) {
            .none => @memcpy(dst_row, src_row),
            .sub => unfilterSub(dst_row, src_row, bpp),
            .up => unfilterUp(dst_row, src_row, prev_row),
            .average => unfilterAverage(dst_row, src_row, prev_row, bpp),
            .paeth => unfilterPaeth(dst_row, src_row, prev_row, bpp),
        }
    }

    return result;
}

fn unfilterSub(dst: []u8, src: []const u8, bpp: usize) void {
    for (dst, 0..) |*d, i| {
        const a: u8 = if (i >= bpp) dst[i - bpp] else 0;
        d.* = src[i] +% a;
    }
}

fn unfilterUp(dst: []u8, src: []const u8, prev: ?[]const u8) void {
    for (dst, 0..) |*d, i| {
        const b: u8 = if (prev) |p| p[i] else 0;
        d.* = src[i] +% b;
    }
}

fn unfilterAverage(dst: []u8, src: []const u8, prev: ?[]const u8, bpp: usize) void {
    for (dst, 0..) |*d, i| {
        const a: u16 = if (i >= bpp) dst[i - bpp] else 0;
        const b: u16 = if (prev) |p| p[i] else 0;
        d.* = src[i] +% @as(u8, @intCast((a + b) / 2));
    }
}

fn unfilterPaeth(dst: []u8, src: []const u8, prev: ?[]const u8, bpp: usize) void {
    for (dst, 0..) |*d, i| {
        const a: u8 = if (i >= bpp) dst[i - bpp] else 0;
        const b: u8 = if (prev) |p| p[i] else 0;
        const c: u8 = if (prev) |p| (if (i >= bpp) p[i - bpp] else 0) else 0;
        d.* = src[i] +% paethPredictor(a, b, c);
    }
}

// ── TIFF Predictor 2 ────────────────────────────────────────────────────

fn applyTiffPredictor(
    allocator: Allocator,
    data: []const u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
) ![]u8 {
    if (bits_per_component != 8) return error.UnsupportedBitsPerComponent;

    const stride = rowStride(columns, colors, bits_per_component);
    const bpp = bytesPerPixel(colors, bits_per_component);

    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const num_rows = data.len / stride;
    if (num_rows * stride != data.len) return error.InvalidDataLength;

    var result = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result);

    var row: usize = 0;
    while (row < num_rows) : (row += 1) {
        const src_row = data[row * stride ..][0..stride];
        const dst_row = result[row * stride ..][0..stride];

        for (dst_row, 0..) |*d, i| {
            if (i >= bpp) {
                d.* = src_row[i] -% src_row[i - bpp];
            } else {
                d.* = src_row[i];
            }
        }
    }

    return result;
}

fn removeTiffPredictor(
    allocator: Allocator,
    data: []const u8,
    columns: u32,
    colors: u8,
    bits_per_component: u8,
) ![]u8 {
    if (bits_per_component != 8) return error.UnsupportedBitsPerComponent;

    const stride = rowStride(columns, colors, bits_per_component);
    const bpp = bytesPerPixel(colors, bits_per_component);

    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const num_rows = data.len / stride;
    if (num_rows * stride != data.len) return error.InvalidDataLength;

    var result = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result);

    var row: usize = 0;
    while (row < num_rows) : (row += 1) {
        const src_row = data[row * stride ..][0..stride];
        const dst_row = result[row * stride ..][0..stride];

        for (dst_row, 0..) |*d, i| {
            if (i >= bpp) {
                d.* = src_row[i] +% dst_row[i - bpp];
            } else {
                d.* = src_row[i];
            }
        }
    }

    return result;
}

// ── Error types ─────────────────────────────────────────────────────────

pub const Error = error{
    InvalidPredictor,
    InvalidDataLength,
    InvalidPngFilter,
    UnsupportedBitsPerComponent,
};

// ── Tests ───────────────────────────────────────────────────────────────

test "png none filter round-trip" {
    const allocator = std.testing.allocator;
    // 2 rows of 4 bytes each (1 color, 8 bpc, 4 columns)
    const data = [_]u8{
        10, 20, 30, 40,
        50, 60, 70, 80,
    };

    const filtered = try applyPredictor(allocator, &data, 10, 4, 1, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 10, 4, 1, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "png sub filter round-trip" {
    const allocator = std.testing.allocator;
    const data = [_]u8{
        10, 20, 30, 40,
        50, 60, 70, 80,
    };

    const filtered = try applyPredictor(allocator, &data, 11, 4, 1, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 11, 4, 1, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "png up filter round-trip" {
    const allocator = std.testing.allocator;
    const data = [_]u8{
        10, 20, 30, 40,
        50, 60, 70, 80,
    };

    const filtered = try applyPredictor(allocator, &data, 12, 4, 1, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 12, 4, 1, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "png average filter round-trip" {
    const allocator = std.testing.allocator;
    const data = [_]u8{
        10, 20, 30, 40,
        50, 60, 70, 80,
    };

    const filtered = try applyPredictor(allocator, &data, 13, 4, 1, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 13, 4, 1, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "png paeth filter round-trip" {
    const allocator = std.testing.allocator;
    const data = [_]u8{
        10, 20, 30, 40,
        50, 60, 70, 80,
    };

    const filtered = try applyPredictor(allocator, &data, 14, 4, 1, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 14, 4, 1, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "png optimum filter round-trip" {
    const allocator = std.testing.allocator;
    const data = [_]u8{
        10, 20, 30, 40,
        50, 60, 70, 80,
        15, 25, 35, 45,
    };

    const filtered = try applyPredictor(allocator, &data, 15, 4, 1, 8);
    defer allocator.free(filtered);

    // Optimum uses per-row filter type bytes, so any PNG predictor can remove it
    const unfiltered = try removePredictor(allocator, filtered, 15, 4, 1, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "paeth predictor function" {
    // When a=0, b=0, c=0, result should be 0
    try std.testing.expectEqual(@as(u8, 0), paethPredictor(0, 0, 0));

    // When a=10, b=20, c=10: p=20, pa=10, pb=0, pc=10 -> b wins
    try std.testing.expectEqual(@as(u8, 20), paethPredictor(10, 20, 10));

    // When a=100, b=50, c=50: p=100, pa=0, pb=50, pc=50 -> a wins
    try std.testing.expectEqual(@as(u8, 100), paethPredictor(100, 50, 50));
}

test "no predictor passthrough" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 1, 2, 3, 4, 5 };

    const result = try applyPredictor(allocator, &data, 1, 5, 1, 8);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u8, &data, result);
}

test "tiff predictor 2 round-trip" {
    const allocator = std.testing.allocator;
    // 2 rows, 3 columns, 3 colors (RGB), 8 bpc
    const data = [_]u8{
        100, 150, 200, 110, 160, 210, 120, 170, 220,
        50,  80,  110, 55,  85,  115, 60,  90,  120,
    };

    const filtered = try applyPredictor(allocator, &data, 2, 3, 3, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 2, 3, 3, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}

test "rgb image with sub filter" {
    const allocator = std.testing.allocator;
    // 2x2 RGB image: 2 columns, 3 colors, 8bpc -> 6 bytes per row
    const data = [_]u8{
        255, 0, 0, 0, 255, 0, // row 0: red, green
        0, 0, 255, 255, 255, 0, // row 1: blue, yellow
    };

    const filtered = try applyPredictor(allocator, &data, 11, 2, 3, 8);
    defer allocator.free(filtered);

    const unfiltered = try removePredictor(allocator, filtered, 11, 2, 3, 8);
    defer allocator.free(unfiltered);

    try std.testing.expectEqualSlices(u8, &data, unfiltered);
}
