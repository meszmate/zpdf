const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const Table = zpdf.table.Table.Table;
const Cell = zpdf.table.Table.Cell;
const ColumnWidth = zpdf.table.Table.ColumnWidth;
const color = zpdf.color;

test "Table: init and deinit" {
    var table = Table.init(testing.allocator);
    defer table.deinit();

    try testing.expect(table.header_row == null);
    try testing.expectEqual(@as(usize, 0), table.rows.items.len);
}

test "Table: addHeaderRow" {
    var table = Table.init(testing.allocator);
    defer table.deinit();

    const cells = [_]Cell{
        .{ .text = "Name" },
        .{ .text = "Age" },
        .{ .text = "City" },
    };
    try table.addHeaderRow(&cells);

    try testing.expect(table.header_row != null);
    try testing.expectEqual(@as(usize, 3), table.header_row.?.len);
    try testing.expectEqualStrings("Name", table.header_row.?[0].text);
}

test "Table: addRow" {
    var table = Table.init(testing.allocator);
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

    try testing.expectEqual(@as(usize, 2), table.rows.items.len);
    try testing.expectEqualStrings("Alice", table.rows.items[0][0].text);
    try testing.expectEqualStrings("Bob", table.rows.items[1][0].text);
}

test "Table: setColumnWidths" {
    var table = Table.init(testing.allocator);
    defer table.deinit();

    const widths = try testing.allocator.alloc(ColumnWidth, 3);
    widths[0] = .{ .fixed = 100.0 };
    widths[1] = .{ .fixed = 200.0 };
    widths[2] = .auto;
    table.setColumnWidths(widths);
    try testing.expect(table.column_widths != null);
}

test "Cell: defaults" {
    const cell = Cell{ .text = "test" };
    try testing.expectEqual(@as(u8, 1), cell.colspan);
    try testing.expectEqual(@as(u8, 1), cell.rowspan);
    try testing.expect(cell.style == null);
}

test "Table: setStyle" {
    var table = Table.init(testing.allocator);
    defer table.deinit();

    table.setStyle(.{
        .border_width = 1.0,
        .cell_padding = 8.0,
        .header_bg_color = color.rgb(200, 200, 200),
    });

    try testing.expectApproxEqAbs(@as(f32, 1.0), table.style.border_width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 8.0), table.style.cell_padding, 0.001);
}
