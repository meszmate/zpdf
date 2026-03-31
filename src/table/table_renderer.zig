const std = @import("std");
const Allocator = std.mem.Allocator;
const table_mod = @import("table.zig");
const Table = table_mod.Table;
const Cell = table_mod.Cell;
const CellStyle = table_mod.CellStyle;
const ColumnWidth = table_mod.ColumnWidth;
const Alignment = table_mod.Alignment;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Options controlling table rendering position and defaults.
pub const TableRenderOptions = struct {
    x: f32,
    y: f32,
    width: f32,
    default_font: StandardFont = .helvetica,
    default_font_size: f32 = 10.0,
};

/// Render a table to PDF content stream operators.
/// Returns an owned slice of bytes containing the PDF operators.
pub fn renderTable(allocator: Allocator, table: *const Table, options: TableRenderOptions) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);

    const writer = buf.writer(allocator);

    // Determine number of columns
    const num_cols = getNumColumns(table);
    if (num_cols == 0) return try buf.toOwnedSlice(allocator);

    // Calculate column widths
    const col_widths = try calculateColumnWidths(allocator, table, num_cols, options.width);
    defer allocator.free(col_widths);

    const padding = table.style.cell_padding;
    const row_height = options.default_font_size + padding * 2.0;
    var current_y = options.y;

    // Save graphics state
    try writer.writeAll("q\n");

    // Render header row
    if (table.header_row) |header| {
        // Header background
        if (table.style.header_bg_color) |bg| {
            try writeColorFill(writer, bg);
            try writeRect(writer, options.x, current_y - row_height, options.width, row_height);
            try writer.writeAll("f\n");
        }

        // Header borders and text
        try renderRow(writer, header, col_widths, options.x, current_y, row_height, padding, table, options, true);
        current_y -= row_height;
    }

    // Render data rows
    for (table.rows.items, 0..) |row, row_idx| {
        // Alternate row coloring
        if (table.style.alternate_row_color) |alt_color| {
            if (row_idx % 2 == 1) {
                try writeColorFill(writer, alt_color);
                try writeRect(writer, options.x, current_y - row_height, options.width, row_height);
                try writer.writeAll("f\n");
            }
        }

        try renderRow(writer, row, col_widths, options.x, current_y, row_height, padding, table, options, false);
        current_y -= row_height;
    }

    // Draw outer border
    try writeStrokeColor(writer, table.style.border_color);
    try writeLineWidth(writer, table.style.border_width);

    const total_rows = (if (table.header_row != null) @as(usize, 1) else @as(usize, 0)) + table.rows.items.len;
    const total_height = row_height * @as(f32, @floatFromInt(total_rows));
    try writeRect(writer, options.x, options.y - total_height, options.width, total_height);
    try writer.writeAll("S\n");

    // Restore graphics state
    try writer.writeAll("Q\n");

    return try buf.toOwnedSlice(allocator);
}

/// Render a single row (header or data).
fn renderRow(
    writer: anytype,
    cells: []const Cell,
    col_widths: []const f32,
    start_x: f32,
    top_y: f32,
    row_height: f32,
    padding: f32,
    table: *const Table,
    options: TableRenderOptions,
    is_header: bool,
) !void {
    var cell_x = start_x;
    const border_width = table.style.border_width;

    for (cells, 0..) |cell, col_idx| {
        if (col_idx >= col_widths.len) break;

        // Calculate cell width (accounting for colspan)
        var cell_width: f32 = 0;
        var span: usize = 0;
        while (span < cell.colspan and (col_idx + span) < col_widths.len) : (span += 1) {
            cell_width += col_widths[col_idx + span];
        }

        // Cell background
        const cell_style = cell.style;
        const bg_color = if (cell_style) |cs| cs.background_color else null;
        if (bg_color) |bg| {
            try writeColorFill(writer, bg);
            try writeRect(writer, cell_x, top_y - row_height, cell_width, row_height);
            try writer.writeAll("f\n");
        }

        // Cell border
        try writeStrokeColor(writer, table.style.border_color);
        try writeLineWidth(writer, border_width);
        try writeRect(writer, cell_x, top_y - row_height, cell_width, row_height);
        try writer.writeAll("S\n");

        // Text color
        const text_color = blk: {
            if (cell_style) |cs| {
                if (cs.text_color) |tc| break :blk tc;
            }
            if (is_header) {
                if (table.style.header_text_color) |htc| break :blk htc;
            }
            break :blk color_mod.rgb(0, 0, 0);
        };

        // Font and size
        const font = blk: {
            if (cell_style) |cs| {
                if (cs.font) |f| break :blk f;
            }
            break :blk options.default_font;
        };
        const font_size = blk: {
            if (cell_style) |cs| {
                if (cs.font_size) |fs| break :blk fs;
            }
            break :blk options.default_font_size;
        };

        // Alignment
        const alignment = blk: {
            if (cell_style) |cs| {
                if (cs.alignment) |a| break :blk a;
            }
            break :blk Alignment.left;
        };

        // Calculate text position
        const cell_padding = if (cell_style) |cs| cs.padding orelse padding else padding;
        const text_y = top_y - row_height + cell_padding;

        const text_width = font.textWidth(cell.text, font_size);
        const text_x = switch (alignment) {
            .left => cell_x + cell_padding,
            .center => cell_x + (cell_width - text_width) / 2.0,
            .right => cell_x + cell_width - cell_padding - text_width,
        };

        // Write text
        try writer.writeAll("BT\n");
        try writeColorFill(writer, text_color);
        try std.fmt.format(writer, "/{s} {d:.1} Tf\n", .{ font.pdfName(), font_size });
        try std.fmt.format(writer, "{d:.2} {d:.2} Td\n", .{ text_x, text_y });
        try std.fmt.format(writer, "({s}) Tj\n", .{cell.text});
        try writer.writeAll("ET\n");

        cell_x += cell_width;
    }
}

/// Calculate actual column widths from specifications.
fn calculateColumnWidths(allocator: Allocator, table: *const Table, num_cols: usize, available_width: f32) ![]f32 {
    var widths = try allocator.alloc(f32, num_cols);

    if (table.column_widths) |specs| {
        var remaining_width = available_width;
        var auto_count: usize = 0;

        // First pass: handle fixed and percent widths
        for (0..num_cols) |i| {
            if (i < specs.len) {
                switch (specs[i]) {
                    .fixed => |w| {
                        widths[i] = w;
                        remaining_width -= w;
                    },
                    .percent => |p| {
                        widths[i] = available_width * p / 100.0;
                        remaining_width -= widths[i];
                    },
                    .auto => {
                        widths[i] = 0;
                        auto_count += 1;
                    },
                }
            } else {
                widths[i] = 0;
                auto_count += 1;
            }
        }

        // Second pass: distribute remaining width among auto columns
        if (auto_count > 0) {
            const auto_width = if (remaining_width > 0) remaining_width / @as(f32, @floatFromInt(auto_count)) else 0;
            for (0..num_cols) |i| {
                const is_auto = if (i < specs.len) specs[i] == .auto else true;
                if (is_auto) {
                    widths[i] = auto_width;
                }
            }
        }
    } else {
        // Default: equal widths
        const col_width = available_width / @as(f32, @floatFromInt(num_cols));
        for (0..num_cols) |i| {
            widths[i] = col_width;
        }
    }

    return widths;
}

/// Determine the number of columns from header or first data row.
fn getNumColumns(table: *const Table) usize {
    if (table.header_row) |header| return header.len;
    if (table.rows.items.len > 0) return table.rows.items[0].len;
    return 0;
}

// -- Helper functions for writing PDF operators --

fn writeColorFill(writer: anytype, c: Color) !void {
    try c.writeColorOps(writer, true);
}

fn writeStrokeColor(writer: anytype, c: Color) !void {
    try c.writeColorOps(writer, false);
}

fn writeLineWidth(writer: anytype, width: f32) !void {
    try std.fmt.format(writer, "{d:.2} w\n", .{width});
}

fn writeRect(writer: anytype, x: f32, y: f32, w: f32, h: f32) !void {
    try std.fmt.format(writer, "{d:.2} {d:.2} {d:.2} {d:.2} re\n", .{ x, y, w, h });
}

// -- Tests --

test "renderTable: empty table" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    const result = try renderTable(std.testing.allocator, &table, .{
        .x = 50,
        .y = 700,
        .width = 500,
    });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "renderTable: simple table" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    const header = [_]Cell{
        .{ .text = "A" },
        .{ .text = "B" },
    };
    try table.addHeaderRow(&header);

    const row = [_]Cell{
        .{ .text = "1" },
        .{ .text = "2" },
    };
    try table.addRow(&row);

    const result = try renderTable(std.testing.allocator, &table, .{
        .x = 50,
        .y = 700,
        .width = 500,
    });
    defer std.testing.allocator.free(result);

    // Should contain PDF operators
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "BT") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ET") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "q") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q") != null);
}

test "calculateColumnWidths: equal distribution" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    const header = [_]Cell{
        .{ .text = "A" },
        .{ .text = "B" },
        .{ .text = "C" },
    };
    try table.addHeaderRow(&header);

    const widths = try calculateColumnWidths(std.testing.allocator, &table, 3, 300.0);
    defer std.testing.allocator.free(widths);

    try std.testing.expectApproxEqAbs(@as(f32, 100.0), widths[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), widths[1], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), widths[2], 0.01);
}
