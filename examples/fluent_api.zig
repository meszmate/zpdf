const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build a PDF using the fluent/builder API
    var builder = zpdf.build(allocator);
    defer builder.deinit();

    const pdf = try builder
        .title("Fluent API Example")
        .author("zpdf")
        .subject("Demonstrating the fluent builder API")
        .page(.a4)
            .text("zpdf - Fluent API Example", .{
                .x = 72,
                .y = 750,
                .font = .helvetica_bold,
                .font_size = 24,
                .color = zpdf.rgb(0, 51, 102),
            })
            .text("This PDF was built using the chainable builder API.", .{
                .x = 72,
                .y = 720,
                .font = .helvetica,
                .font_size = 12,
            })
            .line(.{
                .x1 = 72,
                .y1 = 710,
                .x2 = 523,
                .y2 = 710,
                .color = zpdf.rgb(0, 51, 102),
                .line_width = 1.5,
            })
            .rect(.{
                .x = 72,
                .y = 600,
                .width = 200,
                .height = 80,
                .color = zpdf.rgb(200, 220, 255),
                .border_color = zpdf.rgb(0, 51, 102),
            })
            .text("Inside a rectangle", .{
                .x = 82,
                .y = 640,
                .font = .helvetica,
                .font_size = 11,
            })
            .circle(.{
                .cx = 400,
                .cy = 640,
                .r = 40,
                .color = zpdf.rgb(255, 200, 200),
                .border_color = zpdf.rgb(200, 0, 0),
            })
        .done()
        .page(.a4)
            .text("Page 2", .{
                .x = 72,
                .y = 750,
                .font = .helvetica_bold,
                .font_size = 18,
            })
            .text("The builder wraps the existing Document/Page APIs.", .{
                .x = 72,
                .y = 720,
                .font = .helvetica,
                .font_size = 12,
            })
        .done()
        .save();
    defer allocator.free(pdf);

    const file = try std.fs.cwd().createFile("fluent_api.pdf", .{});
    defer file.close();
    try file.writeAll(pdf);

    std.debug.print("Created fluent_api.pdf ({d} bytes, 2 pages)\n", .{pdf.len});
}
