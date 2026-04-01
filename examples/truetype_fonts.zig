const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Attempt to load a system TrueType font.
    // On macOS: /System/Library/Fonts/Helvetica.ttc (TTC, not TTF)
    // On Linux: /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
    // On Windows: C:\Windows\Fonts\arial.ttf
    // Fall back to a demonstration without an actual font file.
    const font_paths = [_][]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "C:\\Windows\\Fonts\\arial.ttf",
    };

    var font_data: ?[]u8 = null;
    defer if (font_data) |fd| allocator.free(fd);

    for (font_paths) |path| {
        if (std.fs.cwd().openFile(path, .{})) |file| {
            defer file.close();
            const stat = try file.stat();
            font_data = try allocator.alloc(u8, stat.size);
            _ = try file.readAll(font_data.?);
            std.debug.print("Loaded font: {s}\n", .{path});
            break;
        } else |_| {
            continue;
        }
    }

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("TrueType Font Example");
    doc.setCreator("zpdf TrueType example");

    var page = try doc.addPage(.a4);

    if (font_data) |fd| {
        const tt_handle = doc.loadTrueTypeFont(fd) catch |err| {
            std.debug.print("Failed to load TrueType font: {}\n", .{err});
            return;
        };

        // Register the font on the page
        const res_name = try page.addFont(tt_handle.font.postscript_name, tt_handle.ref);

        // Draw text using the TrueType font
        // Note: for TrueType fonts with Identity-H encoding, text must be
        // encoded as glyph IDs. This example uses the standard drawText
        // for demonstration - a production app would encode text properly.
        _ = res_name;

        // Measure text width
        const width = tt_handle.font.textWidth("Hello, TrueType!", 24.0);
        std.debug.print("Text width at 24pt: {d:.2} points\n", .{width});

        std.debug.print("Font info:\n", .{});
        std.debug.print("  Family: {s}\n", .{tt_handle.font.font_family});
        std.debug.print("  Glyphs: {d}\n", .{tt_handle.font.num_glyphs});
        std.debug.print("  Units/em: {d}\n", .{tt_handle.font.units_per_em});
        std.debug.print("  Ascent: {d}\n", .{tt_handle.font.ascent});
        std.debug.print("  Descent: {d}\n", .{tt_handle.font.descent});
    } else {
        std.debug.print("No TrueType font file found on this system.\n", .{});
        std.debug.print("To use this example, place a .ttf file in one of these paths:\n", .{});
        for (font_paths) |path| {
            std.debug.print("  {s}\n", .{path});
        }
    }

    // Always add some standard font content
    _ = try doc.getStandardFont(.helvetica);
    _ = try page.addFont("Helvetica", (try doc.getStandardFont(.helvetica)).ref);

    try page.drawText("TrueType Font Embedding Example", .{
        .x = 50,
        .y = 750,
        .font = .helvetica,
        .font_size = 20,
        .color = zpdf.rgb(0, 0, 0),
    });

    try page.drawText("This document demonstrates TrueType font support in zpdf.", .{
        .x = 50,
        .y = 700,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.rgb(80, 80, 80),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("truetype_fonts.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Wrote truetype_fonts.pdf ({d} bytes)\n", .{bytes.len});
}
