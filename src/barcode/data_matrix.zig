const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Data Matrix ECC 200 symbol size configuration.
/// Each entry defines: rows, cols, data_codewords, ecc_codewords, block_count, data_per_block.
const SymbolSize = struct {
    rows: u16,
    cols: u16,
    data_capacity: u16,
    ecc_codewords: u16,
    block_count: u8,
    /// Number of data region rows (rows minus finder/alignment)
    data_rows: u16,
    /// Number of data region cols
    data_cols: u16,
};

/// ECC 200 symbol size table (square symbols only, most common).
const symbol_sizes = [_]SymbolSize{
    .{ .rows = 10, .cols = 10, .data_capacity = 3, .ecc_codewords = 5, .block_count = 1, .data_rows = 8, .data_cols = 8 },
    .{ .rows = 12, .cols = 12, .data_capacity = 5, .ecc_codewords = 7, .block_count = 1, .data_rows = 10, .data_cols = 10 },
    .{ .rows = 14, .cols = 14, .data_capacity = 8, .ecc_codewords = 10, .block_count = 1, .data_rows = 12, .data_cols = 12 },
    .{ .rows = 16, .cols = 16, .data_capacity = 12, .ecc_codewords = 12, .block_count = 1, .data_rows = 14, .data_cols = 14 },
    .{ .rows = 18, .cols = 18, .data_capacity = 18, .ecc_codewords = 14, .block_count = 1, .data_rows = 16, .data_cols = 16 },
    .{ .rows = 20, .cols = 20, .data_capacity = 22, .ecc_codewords = 18, .block_count = 1, .data_rows = 18, .data_cols = 18 },
    .{ .rows = 22, .cols = 22, .data_capacity = 30, .ecc_codewords = 20, .block_count = 1, .data_rows = 20, .data_cols = 20 },
    .{ .rows = 24, .cols = 24, .data_capacity = 36, .ecc_codewords = 24, .block_count = 1, .data_rows = 22, .data_cols = 22 },
    .{ .rows = 26, .cols = 26, .data_capacity = 44, .ecc_codewords = 28, .block_count = 1, .data_rows = 24, .data_cols = 24 },
    .{ .rows = 32, .cols = 32, .data_capacity = 62, .ecc_codewords = 36, .block_count = 1, .data_rows = 14, .data_cols = 14 },
    .{ .rows = 36, .cols = 36, .data_capacity = 86, .ecc_codewords = 42, .block_count = 1, .data_rows = 16, .data_cols = 16 },
    .{ .rows = 40, .cols = 40, .data_capacity = 114, .ecc_codewords = 48, .block_count = 1, .data_rows = 18, .data_cols = 18 },
    .{ .rows = 44, .cols = 44, .data_capacity = 144, .ecc_codewords = 56, .block_count = 1, .data_rows = 20, .data_cols = 20 },
    .{ .rows = 48, .cols = 48, .data_capacity = 174, .ecc_codewords = 68, .block_count = 1, .data_rows = 22, .data_cols = 22 },
    .{ .rows = 52, .cols = 52, .data_capacity = 204, .ecc_codewords = 84, .block_count = 2, .data_rows = 24, .data_cols = 24 },
    .{ .rows = 64, .cols = 64, .data_capacity = 280, .ecc_codewords = 112, .block_count = 2, .data_rows = 14, .data_cols = 14 },
    .{ .rows = 72, .cols = 72, .data_capacity = 368, .ecc_codewords = 144, .block_count = 4, .data_rows = 16, .data_cols = 16 },
    .{ .rows = 80, .cols = 80, .data_capacity = 456, .ecc_codewords = 192, .block_count = 4, .data_rows = 18, .data_cols = 18 },
    .{ .rows = 88, .cols = 88, .data_capacity = 576, .ecc_codewords = 224, .block_count = 4, .data_rows = 20, .data_cols = 20 },
    .{ .rows = 96, .cols = 96, .data_capacity = 696, .ecc_codewords = 272, .block_count = 4, .data_rows = 22, .data_cols = 22 },
    .{ .rows = 104, .cols = 104, .data_capacity = 816, .ecc_codewords = 336, .block_count = 4, .data_rows = 24, .data_cols = 24 },
    .{ .rows = 120, .cols = 120, .data_capacity = 1050, .ecc_codewords = 408, .block_count = 6, .data_rows = 18, .data_cols = 18 },
    .{ .rows = 132, .cols = 132, .data_capacity = 1304, .ecc_codewords = 496, .block_count = 8, .data_rows = 20, .data_cols = 20 },
    .{ .rows = 144, .cols = 144, .data_capacity = 1558, .ecc_codewords = 620, .block_count = 10, .data_rows = 22, .data_cols = 22 },
};

/// GF(256) field with polynomial x^8 + x^5 + x^3 + x^2 + 1 (0x12D / 301).
const GF256 = struct {
    const POLY: u16 = 301; // x^8 + x^5 + x^3 + x^2 + 1

    /// Exponent table: exp_table[i] = alpha^i
    var exp_table: [256]u8 = undefined;
    /// Log table: log_table[value] = i where alpha^i = value
    var log_table: [256]u8 = undefined;

    var initialized: bool = false;

    fn init() void {
        if (initialized) return;

        var val: u16 = 1;
        for (0..255) |i| {
            exp_table[i] = @intCast(val);
            log_table[@intCast(val)] = @intCast(i);
            val <<= 1;
            if (val >= 256) {
                val ^= POLY;
            }
        }
        exp_table[255] = exp_table[0];
        log_table[0] = 0; // Convention: log(0) is undefined, but we set to 0
        initialized = true;
    }

    fn multiply(a: u8, b: u8) u8 {
        if (a == 0 or b == 0) return 0;
        init();
        const log_sum = @as(u16, log_table[a]) + @as(u16, log_table[b]);
        return exp_table[@intCast(log_sum % 255)];
    }
};

/// Encode ASCII data into Data Matrix codewords.
/// Returns the encoded codewords (caller owns).
pub fn encodeAscii(allocator: Allocator, data: []const u8) ![]u8 {
    var codewords: ArrayList(u8) = .{};
    errdefer codewords.deinit(allocator);

    var i: usize = 0;
    while (i < data.len) {
        // Check for digit pair optimization
        if (i + 1 < data.len and data[i] >= '0' and data[i] <= '9' and data[i + 1] >= '0' and data[i + 1] <= '9') {
            const val = (data[i] - '0') * 10 + (data[i + 1] - '0') + 130;
            try codewords.append(allocator, val);
            i += 2;
        } else if (data[i] <= 127) {
            try codewords.append(allocator, data[i] + 1);
            i += 1;
        } else {
            // Extended ASCII: Upper Shift + value
            try codewords.append(allocator, 235); // Upper Shift
            try codewords.append(allocator, data[i] - 127);
            i += 1;
        }
    }

    return codewords.toOwnedSlice(allocator);
}

/// Select the smallest symbol size that can hold the given number of data codewords.
pub fn selectSymbolSize(data_codeword_count: usize) ?*const SymbolSize {
    for (&symbol_sizes) |*size| {
        if (size.data_capacity >= data_codeword_count) {
            return size;
        }
    }
    return null;
}

/// Calculate Reed-Solomon ECC codewords for a data block.
/// Uses GF(256) with polynomial 301.
fn calculateEcc(allocator: Allocator, data: []const u8, ecc_count: u16) ![]u8 {
    GF256.init();

    // Build generator polynomial: product of (x - alpha^i) for i = 0..ecc_count-1
    const gen = try allocator.alloc(u8, ecc_count + 1);
    defer allocator.free(gen);
    @memset(gen, 0);
    gen[0] = 1;

    for (0..ecc_count) |i| {
        // Multiply gen by (x - alpha^i)
        var j: usize = @min(i + 1, ecc_count);
        while (j > 0) : (j -= 1) {
            gen[j] = gen[j] ^ GF256.multiply(gen[j - 1], GF256.exp_table[@intCast(i)]);
        }
    }

    // Calculate remainder of data polynomial / generator polynomial
    const ecc = try allocator.alloc(u8, ecc_count);
    @memset(ecc, 0);

    for (data) |d| {
        const feedback = d ^ ecc[0];
        // Shift ecc left by 1
        for (0..ecc_count - 1) |j| {
            ecc[j] = ecc[j + 1] ^ GF256.multiply(feedback, gen[ecc_count - 1 - j]);
        }
        ecc[ecc_count - 1] = GF256.multiply(feedback, gen[0]);
    }

    return ecc;
}

/// Build a complete Data Matrix codeword sequence: data + padding + ECC.
fn buildCodewords(allocator: Allocator, data: []const u8, symbol: *const SymbolSize) ![]u8 {
    const total = symbol.data_capacity + symbol.ecc_codewords;
    const result = try allocator.alloc(u8, total);
    errdefer allocator.free(result);

    // Copy data
    @memcpy(result[0..data.len], data);

    // Add padding
    if (data.len < symbol.data_capacity) {
        result[data.len] = 129; // Pad codeword
        for (data.len + 1..symbol.data_capacity) |i| {
            // Randomized padding per spec
            const pad: u16 = @as(u16, 129) + (((@as(u16, @intCast(i)) + 1) * 149) % 253) + 1;
            result[i] = @intCast(pad % 256);
        }
    }

    // Calculate ECC
    const data_slice = result[0..symbol.data_capacity];

    if (symbol.block_count <= 1) {
        const ecc = try calculateEcc(allocator, data_slice, symbol.ecc_codewords);
        defer allocator.free(ecc);
        @memcpy(result[symbol.data_capacity..total], ecc);
    } else {
        // Interleaved blocks
        const block_count = symbol.block_count;
        const data_per_block = symbol.data_capacity / block_count;
        const ecc_per_block = symbol.ecc_codewords / block_count;

        // De-interleave data into blocks, compute ECC per block, then interleave ECC
        const block_data = try allocator.alloc(u8, data_per_block);
        defer allocator.free(block_data);

        for (0..block_count) |b| {
            // Extract block data (interleaved)
            for (0..data_per_block) |j| {
                block_data[j] = data_slice[j * block_count + b];
            }
            const block_ecc = try calculateEcc(allocator, block_data, ecc_per_block);
            defer allocator.free(block_ecc);

            // Interleave ECC back
            for (0..ecc_per_block) |j| {
                result[symbol.data_capacity + j * block_count + b] = block_ecc[j];
            }
        }
    }

    return result;
}

/// Place modules in the Data Matrix grid using the standard placement algorithm.
/// Returns a 2D boolean grid (rows x cols) where true = dark module.
fn placeModules(allocator: Allocator, codewords: []const u8, symbol: *const SymbolSize) ![][]bool {
    const nrow = symbol.data_rows;
    const ncol = symbol.data_cols;

    // Allocate the placement grid
    const grid = try allocator.alloc([]bool, nrow);
    errdefer {
        for (grid) |row| {
            allocator.free(row);
        }
        allocator.free(grid);
    }
    for (grid) |*row| {
        row.* = try allocator.alloc(bool, ncol);
        @memset(row.*, false);
    }

    // Track which cells have been placed
    const placed = try allocator.alloc([]bool, nrow);
    defer {
        for (placed) |row| {
            allocator.free(row);
        }
        allocator.free(placed);
    }
    for (placed) |*row| {
        row.* = try allocator.alloc(bool, ncol);
        @memset(row.*, false);
    }

    // Place modules using Utah-shaped placement
    var cw_idx: usize = 0;
    var row: i32 = 4;
    var col: i32 = 0;

    const nr: i32 = @intCast(nrow);
    const nc: i32 = @intCast(ncol);

    while (row < nr or col < nc) {
        // Check for corner cases
        if (row == nr and col == 0) {
            placeCorner1(grid, placed, codewords, &cw_idx, nrow, ncol);
        }
        if (row == nr - 2 and col == 0 and @mod(nc, 4) != 0) {
            placeCorner2(grid, placed, codewords, &cw_idx, nrow, ncol);
        }
        if (row == nr - 2 and col == 0 and @mod(nc, 8) == 4) {
            placeCorner3(grid, placed, codewords, &cw_idx, nrow, ncol);
        }
        if (row == nr + 4 and col == 2 and @mod(nc, 8) == 0) {
            placeCorner4(grid, placed, codewords, &cw_idx, nrow, ncol);
        }

        // Move up-right
        while (row >= 0 and col < nc) {
            if (row < nr and col >= 0) {
                if (!placed[@intCast(row)][@intCast(col)]) {
                    placeUtah(grid, placed, codewords, &cw_idx, row, col, nrow, ncol);
                }
            }
            row -= 2;
            col += 2;
        }
        row += 1;
        col += 3;

        // Move down-left
        while (row < nr and col >= 0) {
            if (row >= 0 and col < nc) {
                if (!placed[@intCast(row)][@intCast(col)]) {
                    placeUtah(grid, placed, codewords, &cw_idx, row, col, nrow, ncol);
                }
            }
            row += 2;
            col -= 2;
        }
        row += 3;
        col += 1;
    }

    return grid;
}

/// Place a single bit from a codeword into the grid, handling wrapping.
fn placeBit(grid: [][]bool, placed: [][]bool, codewords: []const u8, cw_idx: *usize, bit: u3, row: i32, col: i32, nrow: u16, ncol: u16) void {
    var r = row;
    var c = col;
    const nr: i32 = @intCast(nrow);
    const nc: i32 = @intCast(ncol);

    // Wrap around
    if (r < 0) {
        r += nr;
        c += 4 - @mod(nr + 4, 8);
    }
    if (c < 0) {
        c += nc;
        r += 4 - @mod(nc + 4, 8);
    }

    if (r >= 0 and r < nr and c >= 0 and c < nc) {
        const ur: usize = @intCast(r);
        const uc: usize = @intCast(c);
        if (!placed[ur][uc]) {
            placed[ur][uc] = true;
            if (cw_idx.* < codewords.len) {
                grid[ur][uc] = (codewords[cw_idx.*] & (@as(u8, 1) << (7 - bit))) != 0;
            }
        }
    }
}

/// Place a standard "Utah" shaped module (8 bits of one codeword).
fn placeUtah(grid: [][]bool, placed: [][]bool, codewords: []const u8, cw_idx: *usize, row: i32, col: i32, nrow: u16, ncol: u16) void {
    placeBit(grid, placed, codewords, cw_idx, 0, row - 2, col - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 1, row - 2, col - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 2, row - 1, col - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 3, row - 1, col - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 4, row - 1, col, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 5, row, col - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 6, row, col - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 7, row, col, nrow, ncol);
    cw_idx.* += 1;
}

/// Corner case 1 placement.
fn placeCorner1(grid: [][]bool, placed: [][]bool, codewords: []const u8, cw_idx: *usize, nrow: u16, ncol: u16) void {
    const nr: i32 = @intCast(nrow);
    const nc: i32 = @intCast(ncol);
    placeBit(grid, placed, codewords, cw_idx, 0, nr - 1, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 1, nr - 1, 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 2, nr - 1, 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 3, 0, nc - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 4, 0, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 5, 1, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 6, 2, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 7, 3, nc - 1, nrow, ncol);
    cw_idx.* += 1;
}

/// Corner case 2 placement.
fn placeCorner2(grid: [][]bool, placed: [][]bool, codewords: []const u8, cw_idx: *usize, nrow: u16, ncol: u16) void {
    const nr: i32 = @intCast(nrow);
    const nc: i32 = @intCast(ncol);
    placeBit(grid, placed, codewords, cw_idx, 0, nr - 3, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 1, nr - 2, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 2, nr - 1, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 3, 0, nc - 4, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 4, 0, nc - 3, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 5, 0, nc - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 6, 0, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 7, 1, nc - 1, nrow, ncol);
    cw_idx.* += 1;
}

/// Corner case 3 placement.
fn placeCorner3(grid: [][]bool, placed: [][]bool, codewords: []const u8, cw_idx: *usize, nrow: u16, ncol: u16) void {
    const nr: i32 = @intCast(nrow);
    const nc: i32 = @intCast(ncol);
    placeBit(grid, placed, codewords, cw_idx, 0, nr - 3, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 1, nr - 2, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 2, nr - 1, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 3, 0, nc - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 4, 0, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 5, 1, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 6, 2, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 7, 3, nc - 1, nrow, ncol);
    cw_idx.* += 1;
}

/// Corner case 4 placement.
fn placeCorner4(grid: [][]bool, placed: [][]bool, codewords: []const u8, cw_idx: *usize, nrow: u16, ncol: u16) void {
    const nr: i32 = @intCast(nrow);
    const nc: i32 = @intCast(ncol);
    placeBit(grid, placed, codewords, cw_idx, 0, nr - 1, 0, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 1, nr - 1, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 2, 0, nc - 3, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 3, 0, nc - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 4, 0, nc - 1, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 5, 1, nc - 3, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 6, 1, nc - 2, nrow, ncol);
    placeBit(grid, placed, codewords, cw_idx, 7, 1, nc - 1, nrow, ncol);
    cw_idx.* += 1;
}

/// Build the full symbol matrix including finder pattern and alignment patterns.
fn buildMatrix(allocator: Allocator, data_grid: [][]bool, symbol: *const SymbolSize) ![][]bool {
    const rows = symbol.rows;
    const cols = symbol.cols;

    const matrix = try allocator.alloc([]bool, rows);
    errdefer {
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);
    }
    for (matrix) |*row| {
        row.* = try allocator.alloc(bool, cols);
        @memset(row.*, false);
    }

    // Determine how many data regions there are
    // For symbols <= 26x26, there's 1 data region
    // For larger symbols, there are multiple data regions separated by alignment patterns
    const regions_h: u16 = if (rows <= 26) 1 else if (rows <= 52) 2 else if (rows <= 80) 3 else if (rows <= 108) 4 else if (rows <= 132) 5 else 6;
    const regions_v: u16 = regions_h; // Square symbols have equal horizontal/vertical regions

    // Size of each mapping region (data area within a region)
    const region_data_rows = symbol.data_rows;
    const region_data_cols = symbol.data_cols;

    // Draw finder patterns and alignment patterns for each region
    for (0..regions_v) |rv| {
        for (0..regions_h) |rh| {
            const base_row: u16 = @intCast(rv * (region_data_rows + 2));
            const base_col: u16 = @intCast(rh * (region_data_cols + 2));

            // Bottom edge: solid line (finder)
            for (0..region_data_cols + 2) |c| {
                matrix[base_row][@intCast(base_col + @as(u16, @intCast(c)))] = true;
            }

            // Left edge: solid line (finder)
            for (0..region_data_rows + 2) |r| {
                matrix[@intCast(base_row + @as(u16, @intCast(r)))][base_col] = true;
            }

            // Top edge: alternating (clock track)
            for (0..region_data_cols + 2) |c| {
                matrix[@intCast(base_row + region_data_rows + 1)][@intCast(base_col + @as(u16, @intCast(c)))] = (c % 2 == 0);
            }

            // Right edge: alternating (clock track)
            for (0..region_data_rows + 2) |r| {
                matrix[@intCast(base_row + @as(u16, @intCast(r)))][@intCast(base_col + region_data_cols + 1)] = (r % 2 == 0);
            }
        }
    }

    // Place data modules from the data grid into the matrix
    for (0..symbol.data_rows * regions_v) |dr| {
        for (0..symbol.data_cols * regions_h) |dc| {
            // Determine which region this data cell belongs to
            const region_r = dr / region_data_rows;
            const region_c = dc / region_data_cols;
            const local_r = dr % region_data_rows;
            const local_c = dc % region_data_cols;

            // Map to matrix position (accounting for finder/alignment patterns)
            const matrix_r = region_r * (region_data_rows + 2) + 1 + local_r;
            const matrix_c = region_c * (region_data_cols + 2) + 1 + local_c;

            if (dr < data_grid.len and dc < data_grid[0].len) {
                matrix[matrix_r][matrix_c] = data_grid[dr][dc];
            }
        }
    }

    return matrix;
}

/// Render a Data Matrix barcode as PDF content stream operators.
/// Matches the API of other barcode modules: render(allocator, value, x, y, width, height).
pub fn render(allocator: Allocator, value: []const u8, x: f32, y: f32, width: f32, height: f32) ![]u8 {
    // Encode the data
    const encoded = try encodeAscii(allocator, value);
    defer allocator.free(encoded);

    // Select symbol size
    const symbol = selectSymbolSize(encoded.len) orelse return error.DataTooLong;

    // Build codewords (data + padding + ECC)
    const codewords = try buildCodewords(allocator, encoded, symbol);
    defer allocator.free(codewords);

    // Place data modules
    const data_grid = try placeModules(allocator, codewords, symbol);
    defer {
        for (data_grid) |row| {
            allocator.free(row);
        }
        allocator.free(data_grid);
    }

    // Build full matrix with finder patterns
    const matrix = try buildMatrix(allocator, data_grid, symbol);
    defer {
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);
    }

    const rows = symbol.rows;
    const cols = symbol.cols;

    // Use the smaller of width/height to keep it square
    const size = @min(width, height);
    const module_w = size / @as(f32, @floatFromInt(cols));
    const module_h = size / @as(f32, @floatFromInt(rows));

    var buf: ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("q\n");

    // Draw dark modules as filled rectangles, batching consecutive modules per row
    for (0..rows) |row| {
        var col: usize = 0;
        while (col < cols) {
            if (matrix[row][col]) {
                var run_len: usize = 1;
                while (col + run_len < cols and matrix[row][col + run_len]) {
                    run_len += 1;
                }
                const mx = x + @as(f32, @floatFromInt(col)) * module_w;
                // PDF y-axis is bottom-up, so invert the row
                const my = y + size - @as(f32, @floatFromInt(row + 1)) * module_h;
                const mw = @as(f32, @floatFromInt(run_len)) * module_w;
                try writer.print("{d:.4} {d:.4} {d:.4} {d:.4} re f\n", .{ mx, my, mw, module_h });
                col += run_len;
            } else {
                col += 1;
            }
        }
    }

    try writer.writeAll("Q\n");

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "data_matrix: ascii encoding basic" {
    const allocator = std.testing.allocator;
    const result = try encodeAscii(allocator, "A");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(u8, 66), result[0]); // 'A' (65) + 1 = 66
}

test "data_matrix: ascii encoding digit pairs" {
    const allocator = std.testing.allocator;
    const result = try encodeAscii(allocator, "12");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    // "12" -> 1*10 + 2 + 130 = 142
    try std.testing.expectEqual(@as(u8, 142), result[0]);
}

test "data_matrix: symbol size selection" {
    // 1 codeword should fit in 10x10 (capacity 3)
    const s1 = selectSymbolSize(1);
    try std.testing.expect(s1 != null);
    try std.testing.expectEqual(@as(u16, 10), s1.?.rows);

    // 5 codewords should fit in 12x12 (capacity 5)
    const s2 = selectSymbolSize(5);
    try std.testing.expect(s2 != null);
    try std.testing.expectEqual(@as(u16, 12), s2.?.rows);

    // 12 codewords should fit in 16x16 (capacity 12)
    const s3 = selectSymbolSize(12);
    try std.testing.expect(s3 != null);
    try std.testing.expectEqual(@as(u16, 16), s3.?.rows);
}

test "data_matrix: render produces PDF operators" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "Hello", 10, 20, 100, 100);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "re f\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "data_matrix: render with numeric data" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "1234567890", 0, 0, 50, 50);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "data_matrix: ecc calculation" {
    GF256.init();
    const allocator = std.testing.allocator;
    // Simple test: calculate ECC for a small data block
    const data = [_]u8{ 66, 129, 129 }; // 'A' encoded + padding for 10x10
    const ecc = try calculateEcc(allocator, &data, 5);
    defer allocator.free(ecc);
    try std.testing.expectEqual(@as(usize, 5), ecc.len);
}
