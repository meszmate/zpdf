const std = @import("std");
const Allocator = std.mem.Allocator;

/// QR code error correction level.
pub const ErrorLevel = enum {
    low,
    medium,
    quartile,
    high,

    /// Returns the format bits for this error level.
    fn formatBits(self: ErrorLevel) u2 {
        return switch (self) {
            .low => 1,
            .medium => 0,
            .quartile => 3,
            .high => 2,
        };
    }
};

/// A generated QR code represented as a 2D grid of modules.
pub const QrCode = struct {
    modules: [][]bool,
    size: usize,
    allocator: Allocator,

    /// Free all allocated memory.
    pub fn deinit(self: *QrCode) void {
        for (self.modules) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.modules);
    }

    /// Get the module value at (x, y). Returns false if out of bounds.
    pub fn getModule(self: *const QrCode, x: usize, y: usize) bool {
        if (x >= self.size or y >= self.size) return false;
        return self.modules[y][x];
    }

    /// Render the QR code as PDF content stream operators (filled rectangles).
    /// Each dark module becomes a small filled rectangle.
    pub fn render(self: *const QrCode, allocator: Allocator, x: f32, y: f32, size: f32) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        const module_size = size / @as(f32, @floatFromInt(self.size));

        try writer.writeAll("q\n");

        for (0..self.size) |row| {
            // Find consecutive dark modules in this row and batch them
            var col: usize = 0;
            while (col < self.size) {
                if (self.modules[row][col]) {
                    var run_len: usize = 1;
                    while (col + run_len < self.size and self.modules[row][col + run_len]) {
                        run_len += 1;
                    }
                    const mx = x + @as(f32, @floatFromInt(col)) * module_size;
                    // PDF y-axis is bottom-up, so invert the row
                    const my = y + size - @as(f32, @floatFromInt(row + 1)) * module_size;
                    const mw = @as(f32, @floatFromInt(run_len)) * module_size;
                    try writer.print("{d:.4} {d:.4} {d:.4} {d:.4} re f\n", .{ mx, my, mw, module_size });
                    col += run_len;
                } else {
                    col += 1;
                }
            }
        }

        try writer.writeAll("Q\n");

        return buf.toOwnedSlice(allocator);
    }

    /// Generate a QR code for the given data.
    /// This is a simplified implementation supporting byte mode encoding
    /// for Version 1-4 QR codes (up to ~78 bytes at medium EC level).
    pub fn generate(allocator: Allocator, data: []const u8, error_level: ErrorLevel) !QrCode {
        // Determine version based on data capacity
        const version = try selectVersion(data.len, error_level);
        const qr_size = version * 4 + 17;

        // Allocate the module grid
        var modules = try allocator.alloc([]bool, qr_size);
        errdefer {
            for (modules) |row| {
                allocator.free(row);
            }
            allocator.free(modules);
        }
        for (0..qr_size) |i| {
            modules[i] = try allocator.alloc(bool, qr_size);
            @memset(modules[i], false);
        }

        // Track which modules are function patterns (not to be masked)
        var is_function = try allocator.alloc([]bool, qr_size);
        defer {
            for (is_function) |row| {
                allocator.free(row);
            }
            allocator.free(is_function);
        }
        for (0..qr_size) |i| {
            is_function[i] = try allocator.alloc(bool, qr_size);
            @memset(is_function[i], false);
        }

        // Place function patterns
        placeFunctionPatterns(modules, is_function, qr_size, version);

        // Encode data in byte mode
        const data_bits = try encodeData(allocator, data, version, error_level);
        defer allocator.free(data_bits);

        // Place data bits
        placeDataBits(modules, is_function, qr_size, data_bits);

        // Apply mask pattern 0 (checkerboard: (row + col) % 2 == 0)
        applyMask(modules, is_function, qr_size);

        // Place format information
        placeFormatInfo(modules, qr_size, error_level);

        // Place version information for version >= 7
        if (version >= 7) {
            placeVersionInfo(modules, qr_size, version);
        }

        return QrCode{
            .modules = modules,
            .size = qr_size,
            .allocator = allocator,
        };
    }
};

/// Data capacity table: [version-1][error_level] = max bytes in byte mode.
const data_capacity = [4][4]usize{
    // L, M, Q, H
    .{ 17, 14, 11, 7 }, // Version 1 (21x21)
    .{ 32, 26, 20, 14 }, // Version 2 (25x25)
    .{ 53, 42, 32, 24 }, // Version 3 (29x29)
    .{ 78, 62, 46, 34 }, // Version 4 (33x33)
};

fn selectVersion(data_len: usize, error_level: ErrorLevel) !u8 {
    const ec_idx: usize = switch (error_level) {
        .low => 0,
        .medium => 1,
        .quartile => 2,
        .high => 3,
    };
    for (0..4) |v| {
        if (data_len <= data_capacity[v][ec_idx]) {
            return @intCast(v + 1);
        }
    }
    return error.DataTooLong;
}

/// Total codeword counts per version (total data + EC codewords).
const total_codewords = [4]usize{ 26, 44, 70, 100 };

/// Data codeword counts per version and EC level.
const data_codewords_table = [4][4]usize{
    .{ 19, 16, 13, 9 }, // Version 1
    .{ 34, 28, 22, 16 }, // Version 2
    .{ 55, 44, 34, 26 }, // Version 3
    .{ 80, 64, 48, 36 }, // Version 4
};

fn encodeData(allocator: Allocator, data: []const u8, version: u8, error_level: ErrorLevel) ![]u1 {
    const ec_idx: usize = switch (error_level) {
        .low => 0,
        .medium => 1,
        .quartile => 2,
        .high => 3,
    };
    const total_data_codewords = data_codewords_table[version - 1][ec_idx];
    const total_bits = total_codewords[version - 1] * 8;

    var bits: std.ArrayListUnmanaged(u1) = .{};
    errdefer bits.deinit(allocator);

    // Mode indicator: byte mode = 0100
    try bits.appendSlice(allocator, &[_]u1{ 0, 1, 0, 0 });

    // Character count indicator (8 bits for version 1-9 in byte mode)
    const count: u8 = @intCast(data.len);
    for (0..8) |i| {
        try bits.append(allocator, @intCast((count >> @intCast(7 - i)) & 1));
    }

    // Data bytes
    for (data) |byte| {
        for (0..8) |i| {
            try bits.append(allocator, @intCast((byte >> @intCast(7 - i)) & 1));
        }
    }

    // Terminator (up to 4 zero bits)
    const terminator_len = @min(4, total_data_codewords * 8 -| bits.items.len);
    for (0..terminator_len) |_| {
        try bits.append(allocator, 0);
    }

    // Pad to byte boundary
    while (bits.items.len % 8 != 0) {
        try bits.append(allocator, 0);
    }

    // Pad with alternating bytes 0xEC, 0x11
    const pad_bytes = [_]u8{ 0xEC, 0x11 };
    var pad_idx: usize = 0;
    while (bits.items.len < total_data_codewords * 8) {
        const pb = pad_bytes[pad_idx % 2];
        for (0..8) |i| {
            try bits.append(allocator, @intCast((pb >> @intCast(7 - i)) & 1));
        }
        pad_idx += 1;
    }

    // Generate error correction codewords (simplified Reed-Solomon)
    const ec_codewords_count = total_codewords[version - 1] - total_data_codewords;

    // Convert bits to codewords for EC calculation
    var data_cw = try allocator.alloc(u8, total_data_codewords);
    defer allocator.free(data_cw);
    for (0..total_data_codewords) |i| {
        var byte: u8 = 0;
        for (0..8) |b| {
            byte = (byte << 1) | bits.items[i * 8 + b];
        }
        data_cw[i] = byte;
    }

    const ec_cw = try generateECC(allocator, data_cw, ec_codewords_count);
    defer allocator.free(ec_cw);

    // Append EC bits
    for (ec_cw) |byte| {
        for (0..8) |i| {
            try bits.append(allocator, @intCast((byte >> @intCast(7 - i)) & 1));
        }
    }

    // Pad to total bits if needed
    while (bits.items.len < total_bits) {
        try bits.append(allocator, 0);
    }

    return bits.toOwnedSlice(allocator);
}

/// GF(256) multiplication.
fn gfMul(a: u8, b: u8) u8 {
    if (a == 0 or b == 0) return 0;
    return gf_exp[(@as(u16, gf_log[a]) + gf_log[b]) % 255];
}

/// GF(256) log and exp tables.
const gf_exp: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    var val: u16 = 1;
    for (0..256) |i| {
        table[i] = @intCast(val);
        val <<= 1;
        if (val >= 256) val ^= 0x11d;
    }
    break :blk table;
};

const gf_log: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    table[0] = 0;
    for (0..255) |i| {
        table[gf_exp[i]] = @intCast(i);
    }
    break :blk table;
};

/// Generate error correction codewords using Reed-Solomon.
fn generateECC(allocator: Allocator, data: []const u8, ec_count: usize) ![]u8 {
    // Generate generator polynomial
    var gen = try allocator.alloc(u8, ec_count + 1);
    defer allocator.free(gen);
    @memset(gen, 0);
    gen[0] = 1;

    for (0..ec_count) |i| {
        // Multiply gen by (x - alpha^i)
        var j: usize = ec_count;
        while (j > 0) : (j -= 1) {
            gen[j] = gen[j - 1] ^ gfMul(gen[j], gf_exp[i]);
        }
        gen[0] = gfMul(gen[0], gf_exp[i]);
    }

    // Polynomial division
    var remainder = try allocator.alloc(u8, ec_count);
    @memset(remainder, 0);

    for (data) |byte| {
        const factor = byte ^ remainder[0];
        // Shift remainder left
        for (0..ec_count - 1) |i| {
            remainder[i] = remainder[i + 1];
        }
        remainder[ec_count - 1] = 0;
        // Add gen * factor
        for (0..ec_count) |i| {
            remainder[i] ^= gfMul(gen[i + 1], factor);
        }
    }

    return remainder;
}

fn placeFunctionPatterns(modules: [][]bool, is_function: [][]bool, size: usize, version: u8) void {
    // Finder patterns (top-left, top-right, bottom-left)
    placeFinderPattern(modules, is_function, size, 0, 0);
    placeFinderPattern(modules, is_function, size, size - 7, 0);
    placeFinderPattern(modules, is_function, size, 0, size - 7);

    // Separators
    for (0..8) |i| {
        // Top-left
        setFunction(modules, is_function, size, 7, i, false);
        setFunction(modules, is_function, size, i, 7, false);
        // Top-right
        setFunction(modules, is_function, size, size - 8, i, false);
        setFunction(modules, is_function, size, size - 1 - i, 7, false);
        // Bottom-left
        setFunction(modules, is_function, size, 7, size - 1 - i, false);
        setFunction(modules, is_function, size, i, size - 8, false);
    }

    // Timing patterns
    for (8..size - 8) |i| {
        const val = i % 2 == 0;
        setFunction(modules, is_function, size, i, 6, val);
        setFunction(modules, is_function, size, 6, i, val);
    }

    // Dark module
    setFunction(modules, is_function, size, 8, size - 8, true);

    // Alignment patterns for version >= 2
    if (version >= 2) {
        const pos = switch (version) {
            2 => [_]usize{ 6, 18 },
            3 => [_]usize{ 6, 22 },
            4 => [_]usize{ 6, 26 },
            else => [_]usize{ 6, 18 },
        };
        for (pos[0..]) |py| {
            for (pos[0..]) |px| {
                // Skip if overlapping finder patterns
                if ((px <= 8 and py <= 8) or
                    (px <= 8 and py >= size - 8) or
                    (px >= size - 8 and py <= 8))
                    continue;
                placeAlignmentPattern(modules, is_function, size, px, py);
            }
        }
    }

    // Reserve format info areas
    for (0..9) |i| {
        setFunction(modules, is_function, size, i, 8, false);
        setFunction(modules, is_function, size, 8, i, false);
    }
    for (0..8) |i| {
        setFunction(modules, is_function, size, size - 1 - i, 8, false);
        setFunction(modules, is_function, size, 8, size - 1 - i, false);
    }
}

fn setFunction(modules: [][]bool, is_function: [][]bool, size: usize, x: usize, y: usize, val: bool) void {
    if (x < size and y < size) {
        modules[y][x] = val;
        is_function[y][x] = true;
    }
}

fn placeFinderPattern(modules: [][]bool, is_function: [][]bool, size: usize, ox: usize, oy: usize) void {
    for (0..7) |dy| {
        for (0..7) |dx| {
            const x = ox + dx;
            const y = oy + dy;
            // Finder pattern: outer ring is dark, then light ring, then dark center
            const is_dark = (dx == 0 or dx == 6 or dy == 0 or dy == 6) or
                (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4);
            setFunction(modules, is_function, size, x, y, is_dark);
        }
    }
}

fn placeAlignmentPattern(modules: [][]bool, is_function: [][]bool, size: usize, cx: usize, cy: usize) void {
    for (0..5) |dy| {
        for (0..5) |dx| {
            const x = cx - 2 + dx;
            const y = cy - 2 + dy;
            const is_dark = (dx == 0 or dx == 4 or dy == 0 or dy == 4 or (dx == 2 and dy == 2));
            setFunction(modules, is_function, size, x, y, is_dark);
        }
    }
}

fn placeDataBits(modules: [][]bool, is_function: [][]bool, size: usize, data_bits: []u1) void {
    var bit_idx: usize = 0;
    var right: usize = size - 1;

    while (right < size) { // Using wrapping underflow to detect < 0
        // Skip the vertical timing pattern column
        var actual_right = right;
        if (actual_right == 6) {
            if (actual_right == 0) break;
            actual_right -= 1;
        }

        // Process two columns at a time (right and right-1)
        var col_pair: usize = 0;
        while (col_pair < 2) : (col_pair += 1) {
            const cur_col = if (col_pair == 0) actual_right else if (actual_right > 0) actual_right - 1 else break;

            // Alternate direction: upward for even pairs, downward for odd
            const going_up = ((size - 1 - actual_right) / 2) % 2 == 0;

            for (0..size) |row_i| {
                const row = if (going_up) size - 1 - row_i else row_i;
                if (!is_function[row][cur_col]) {
                    if (bit_idx < data_bits.len) {
                        modules[row][cur_col] = data_bits[bit_idx] == 1;
                        bit_idx += 1;
                    }
                }
            }
        }

        // Move to next column pair
        if (actual_right < 2) break;
        right = actual_right - 2;
        if (right == 6) {
            if (right == 0) break;
            right -= 1;
        }
    }
}

fn applyMask(modules: [][]bool, is_function: [][]bool, size: usize) void {
    // Mask pattern 0: (row + col) % 2 == 0
    for (0..size) |row| {
        for (0..size) |col| {
            if (!is_function[row][col] and (row + col) % 2 == 0) {
                modules[row][col] = !modules[row][col];
            }
        }
    }
}

fn placeFormatInfo(modules: [][]bool, size: usize, error_level: ErrorLevel) void {
    // Format information: 5 data bits + 10 EC bits
    const ec_bits: u15 = @as(u15, error_level.formatBits()) << 13;
    const mask_pattern: u15 = 0; // Mask 0

    var format_data: u15 = ec_bits | (mask_pattern << 10);

    // BCH error correction for format info
    var data: u32 = @as(u32, format_data) << 10;
    var gen: u32 = 0b10100110111 << 4; // Generator polynomial

    var shift: u5 = 14;
    while (shift >= 10) : (shift -= 1) {
        if (data & (@as(u32, 1) << shift) != 0) {
            data ^= gen;
        }
        gen >>= 1;
        if (shift == 10) break;
    }

    format_data |= @intCast(data & 0x3FF);
    format_data ^= 0b101010000010010; // XOR with mask

    // Place format bits around finder patterns
    const format_positions_h = [15]usize{ 0, 1, 2, 3, 4, 5, 7, 8, size - 8, size - 7, size - 6, size - 5, size - 4, size - 3, size - 2 };
    const format_positions_v = [15]usize{ size - 1, size - 2, size - 3, size - 4, size - 5, size - 6, size - 7, size - 8, 7, 5, 4, 3, 2, 1, 0 };

    for (0..15) |i| {
        const bit = (format_data >> @intCast(i)) & 1 == 1;
        modules[8][format_positions_h[i]] = bit;
        modules[format_positions_v[i]][8] = bit;
    }
}

fn placeVersionInfo(modules: [][]bool, size: usize, version: u8) void {
    if (version < 7) return;

    // Version info is 18 bits (6 data + 12 EC)
    var data: u32 = @as(u32, version) << 12;
    var gen: u32 = 0b1111100100101 << 5;

    var shift: u5 = 17;
    while (shift >= 12) : (shift -= 1) {
        if (data & (@as(u32, 1) << shift) != 0) {
            data ^= gen;
        }
        gen >>= 1;
        if (shift == 12) break;
    }

    const version_info: u18 = @intCast((@as(u32, version) << 12) | (data & 0xFFF));

    for (0..18) |i| {
        const bit = (version_info >> @intCast(i)) & 1 == 1;
        const row = i / 3;
        const col = i % 3;
        // Bottom-left
        modules[size - 11 + col][row] = bit;
        // Top-right
        modules[row][size - 11 + col] = bit;
    }
}

// -- Tests --

test "qr: generate version 1" {
    const allocator = std.testing.allocator;
    var qr = try QrCode.generate(allocator, "Hi", .medium);
    defer qr.deinit();

    try std.testing.expectEqual(@as(usize, 21), qr.size);
    try std.testing.expectEqual(@as(usize, 21), qr.modules.len);
}

test "qr: generate longer data" {
    const allocator = std.testing.allocator;
    var qr = try QrCode.generate(allocator, "Hello, World!!", .medium);
    defer qr.deinit();

    // Version 1 (21x21) can hold this data at medium EC
    try std.testing.expect(qr.size >= 21);
    try std.testing.expectEqual(qr.size, qr.modules.len);
}

test "qr: finder pattern present" {
    const allocator = std.testing.allocator;
    var qr = try QrCode.generate(allocator, "A", .low);
    defer qr.deinit();

    // Top-left finder pattern: top-left corner should be dark
    try std.testing.expect(qr.getModule(0, 0));
    try std.testing.expect(qr.getModule(6, 0));
    try std.testing.expect(qr.getModule(0, 6));
    try std.testing.expect(qr.getModule(6, 6));
}

test "qr: render produces PDF operators" {
    const allocator = std.testing.allocator;
    var qr = try QrCode.generate(allocator, "Test", .low);
    defer qr.deinit();

    const pdf = try qr.render(allocator, 10, 20, 100);
    defer allocator.free(pdf);

    try std.testing.expect(std.mem.indexOf(u8, pdf, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "re f\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "Q\n") != null);
}

test "qr: data too long" {
    const allocator = std.testing.allocator;
    // 100 bytes exceeds version 4 capacity for any EC level
    const long_data = [_]u8{'A'} ** 100;
    const result = QrCode.generate(allocator, &long_data, .high);
    try std.testing.expectError(error.DataTooLong, result);
}

test "qr: getModule out of bounds" {
    const allocator = std.testing.allocator;
    var qr = try QrCode.generate(allocator, "X", .low);
    defer qr.deinit();

    try std.testing.expect(!qr.getModule(999, 999));
}
