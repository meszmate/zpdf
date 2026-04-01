const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Lists Example");
    doc.setAuthor("zpdf");

    const helv = try doc.getStandardFont(.helvetica);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);

    const page = try doc.addPage(.a4);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    var cur_y: f32 = 780;

    // Title
    try page.drawText("List Rendering Examples", .{
        .x = 50,
        .y = cur_y,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = zpdf.rgb(0, 51, 102),
    });
    cur_y -= 40;

    // Section 1: Bulleted list
    try page.drawText("Bulleted List", .{
        .x = 50,
        .y = cur_y,
        .font = .helvetica_bold,
        .font_size = 14,
    });
    cur_y -= 20;

    const bullet_items = [_]zpdf.ListItem{
        .{ .text = "Apples are a great source of fiber and vitamins" },
        .{ .text = "Bananas provide potassium and natural energy" },
        .{ .text = "Cherries contain antioxidants and anti-inflammatory compounds" },
        .{ .text = "Dates are rich in minerals and natural sweetness" },
    };

    const h1 = try page.drawList(&bullet_items, .{
        .x = 50,
        .y = cur_y,
        .max_width = 450,
        .style = .bullet,
        .font_size = 11,
    });
    cur_y -= h1 + 20;

    // Section 2: Numbered list
    try page.drawText("Numbered List", .{
        .x = 50,
        .y = cur_y,
        .font = .helvetica_bold,
        .font_size = 14,
    });
    cur_y -= 20;

    const numbered_items = [_]zpdf.ListItem{
        .{ .text = "Preheat the oven to 350 degrees Fahrenheit" },
        .{ .text = "Mix flour, sugar, and baking powder in a bowl" },
        .{ .text = "Add eggs, milk, and melted butter" },
        .{ .text = "Pour batter into a greased pan" },
        .{ .text = "Bake for 25 minutes until golden brown" },
    };

    const h2 = try page.drawList(&numbered_items, .{
        .x = 50,
        .y = cur_y,
        .max_width = 450,
        .style = .numbered,
        .font_size = 11,
    });
    cur_y -= h2 + 20;

    // Section 3: Nested list with mixed styles
    try page.drawText("Nested List (Mixed Styles)", .{
        .x = 50,
        .y = cur_y,
        .font = .helvetica_bold,
        .font_size = 14,
    });
    cur_y -= 20;

    const frontend_children = [_]zpdf.ListItem{
        .{ .text = "HTML and CSS" },
        .{ .text = "JavaScript" },
        .{ .text = "React or Vue" },
    };

    const backend_children = [_]zpdf.ListItem{
        .{ .text = "Zig" },
        .{ .text = "Rust" },
        .{ .text = "Go" },
    };

    const db_children = [_]zpdf.ListItem{
        .{ .text = "PostgreSQL" },
        .{ .text = "SQLite" },
    };

    const nested_items = [_]zpdf.ListItem{
        .{ .text = "Frontend", .children = &frontend_children, .child_style = .lettered },
        .{ .text = "Backend", .children = &backend_children, .child_style = .lettered },
        .{ .text = "Databases", .children = &db_children, .child_style = .lettered },
    };

    _ = try page.drawList(&nested_items, .{
        .x = 50,
        .y = cur_y,
        .max_width = 450,
        .style = .numbered,
        .font_size = 11,
        .item_spacing = 6,
    });

    // Save
    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    const file = try std.fs.cwd().createFile("lists.pdf", .{});
    defer file.close();
    try file.writeAll(pdf_bytes);
}
