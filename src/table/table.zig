const std = @import("std");
const Allocator = std.mem.Allocator;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Specifies how a column width is determined.
pub const ColumnWidth = union(enum) {
    /// Fixed width in points.
    fixed: f32,
    /// Automatically determined width.
    auto,
    /// Width as a percentage of total available width.
    percent: f32,
};

/// Style applied to an individual cell.
pub const CellStyle = struct {
    background_color: ?Color = null,
    text_color: ?Color = null,
    font: ?StandardFont = null,
    font_size: ?f32 = null,
    alignment: ?Alignment = null,
    padding: ?f32 = null,
};

/// Text alignment within a cell.
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Style applied to the entire table.
pub const TableStyle = struct {
    border_color: Color = color_mod.rgb(0, 0, 0),
    border_width: f32 = 0.5,
    header_bg_color: ?Color = null,
    header_text_color: ?Color = null,
    alternate_row_color: ?Color = null,
    cell_padding: f32 = 4.0,
};

/// A single cell in the table.
pub const Cell = struct {
    text: []const u8,
    colspan: u8 = 1,
    rowspan: u8 = 1,
    style: ?CellStyle = null,
};

/// A table structure for building tabular layouts in PDF documents.
pub const Table = struct {
    allocator: Allocator,
    header_row: ?[]Cell,
    rows: std.ArrayListUnmanaged([]Cell),
    column_widths: ?[]const ColumnWidth,
    style: TableStyle,

    /// Initialize a new empty table.
    pub fn init(allocator: Allocator) Table {
        return .{
            .allocator = allocator,
            .header_row = null,
            .rows = .empty,
            .column_widths = null,
            .style = .{},
        };
    }

    /// Free all resources owned by this table.
    pub fn deinit(self: *Table) void {
        if (self.header_row) |header| {
            self.allocator.free(header);
        }
        for (self.rows.items) |row| {
            self.allocator.free(row);
        }
        self.rows.deinit(self.allocator);
        if (self.column_widths) |widths| {
            self.allocator.free(widths);
        }
    }

    /// Set the column width specifications for the table.
    pub fn setColumnWidths(self: *Table, widths: []const ColumnWidth) void {
        if (self.column_widths) |old| {
            self.allocator.free(old);
        }
        self.column_widths = widths;
    }

    /// Set the header row. The cells are duplicated into owned memory.
    pub fn addHeaderRow(self: *Table, cells: []const Cell) !void {
        if (self.header_row) |old| {
            self.allocator.free(old);
        }
        const owned = try self.allocator.alloc(Cell, cells.len);
        @memcpy(owned, cells);
        self.header_row = owned;
    }

    /// Add a data row. The cells are duplicated into owned memory.
    pub fn addRow(self: *Table, cells: []const Cell) !void {
        const owned = try self.allocator.alloc(Cell, cells.len);
        @memcpy(owned, cells);
        try self.rows.append(self.allocator, owned);
    }

    /// Set the table style.
    pub fn setStyle(self: *Table, style: TableStyle) void {
        self.style = style;
    }
};

// -- Tests --

test "Table: init and deinit" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    try std.testing.expect(table.header_row == null);
    try std.testing.expectEqual(@as(usize, 0), table.rows.items.len);
}

test "Table: addHeaderRow" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    const cells = [_]Cell{
        .{ .text = "Name" },
        .{ .text = "Age" },
        .{ .text = "City" },
    };
    try table.addHeaderRow(&cells);

    try std.testing.expect(table.header_row != null);
    try std.testing.expectEqual(@as(usize, 3), table.header_row.?.len);
    try std.testing.expectEqualStrings("Name", table.header_row.?[0].text);
}

test "Table: addRow" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    const row1 = [_]Cell{
        .{ .text = "Alice" },
        .{ .text = "30" },
    };
    const row2 = [_]Cell{
        .{ .text = "Bob" },
        .{ .text = "25" },
    };
    try table.addRow(&row1);
    try table.addRow(&row2);

    try std.testing.expectEqual(@as(usize, 2), table.rows.items.len);
    try std.testing.expectEqualStrings("Alice", table.rows.items[0][0].text);
    try std.testing.expectEqualStrings("Bob", table.rows.items[1][0].text);
}

test "Table: setStyle" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    table.setStyle(.{
        .border_width = 1.0,
        .cell_padding = 8.0,
        .header_bg_color = color_mod.rgb(200, 200, 200),
    });

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), table.style.border_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), table.style.cell_padding, 0.001);
    try std.testing.expect(table.style.header_bg_color != null);
}

test "Cell: colspan and rowspan defaults" {
    const cell = Cell{ .text = "test" };
    try std.testing.expectEqual(@as(u8, 1), cell.colspan);
    try std.testing.expectEqual(@as(u8, 1), cell.rowspan);
    try std.testing.expect(cell.style == null);
}
