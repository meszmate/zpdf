const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const Table = zpdf.table.Table.Table;
    const Cell = zpdf.table.Table.Cell;
    const ColumnWidth = zpdf.table.Table.ColumnWidth;
    const renderTable = zpdf.table.table_renderer.renderTable;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Table Example");
    const page = try doc.addPage(PageSize.a4);

    // Register font for the page
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    // Title
    try page.drawText("Employee Directory", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 0, 0),
    });

    // Build a table
    var table = Table.init(allocator);
    defer table.deinit();

    // Column widths: Name (40%), Role (30%), Location (30%)
    const widths = try allocator.alloc(ColumnWidth, 3);
    widths[0] = .{ .percent = 40 };
    widths[1] = .{ .percent = 30 };
    widths[2] = .{ .percent = 30 };
    table.setColumnWidths(widths);

    // Style
    table.setStyle(.{
        .border_color = color.rgb(80, 80, 80),
        .border_width = 0.5,
        .header_bg_color = color.rgb(41, 65, 122),
        .header_text_color = color.rgb(255, 255, 255),
        .alternate_row_color = color.rgb(235, 241, 250),
        .cell_padding = 6.0,
    });

    // Header
    const header = [_]Cell{
        .{ .text = "Name", .style = .{ .font = .helvetica_bold } },
        .{ .text = "Role", .style = .{ .font = .helvetica_bold } },
        .{ .text = "Location", .style = .{ .font = .helvetica_bold } },
    };
    try table.addHeaderRow(&header);

    // Data rows
    const rows = [_][3]Cell{
        .{ .{ .text = "Alice Johnson" }, .{ .text = "Engineer" }, .{ .text = "San Francisco" } },
        .{ .{ .text = "Bob Smith" }, .{ .text = "Designer" }, .{ .text = "New York" } },
        .{ .{ .text = "Carol White" }, .{ .text = "Manager" }, .{ .text = "London" } },
        .{ .{ .text = "David Brown" }, .{ .text = "Analyst" }, .{ .text = "Berlin" } },
        .{ .{ .text = "Eva Martinez" }, .{ .text = "Developer" }, .{ .text = "Tokyo" } },
    };
    for (&rows) |*row| {
        try table.addRow(row);
    }

    // Render the table into PDF content stream operators
    const table_ops = try renderTable(allocator, &table, .{
        .x = 72,
        .y = 750,
        .width = 451,
        .default_font = .helvetica,
        .default_font_size = 10.0,
    });
    defer allocator.free(table_ops);

    // Append table content to the page
    try page.content.appendSlice(page.allocator, table_ops);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("tables.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created tables.pdf ({d} bytes)\n", .{bytes.len});
}
