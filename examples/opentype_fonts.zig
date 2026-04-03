const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Attempt to load a system OpenType CFF font.
    // Common locations for OTF fonts:
    const font_paths = [_][]const u8{
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/OTF/SourceCodePro-Regular.otf",
        "/System/Library/Fonts/Supplemental/Courier New.ttf",
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

    doc.setTitle("OpenType Font Example");
    doc.setCreator("zpdf OpenType example");

    var page = try doc.addPage(.a4);

    if (font_data) |fd| {
        // Use auto-detection to load the font
        if (zpdf.opentype.isCffFont(fd)) {
            const ot_handle = doc.loadOpenTypeFont(fd) catch |err| {
                std.debug.print("Failed to load OpenType font: {}\n", .{err});
                return;
            };

            const res_name = try page.addFont(ot_handle.font.postscript_name, ot_handle.ref);
            _ = res_name;

            const width = ot_handle.font.textWidth("Hello, OpenType!", 24.0);
            std.debug.print("Text width at 24pt: {d:.2} points\n", .{width});

            std.debug.print("Font info:\n", .{});
            std.debug.print("  Family: {s}\n", .{ot_handle.font.font_family});
            std.debug.print("  Glyphs: {d}\n", .{ot_handle.font.num_glyphs});
            std.debug.print("  Units/em: {d}\n", .{ot_handle.font.units_per_em});
            std.debug.print("  CFF: {}\n", .{ot_handle.font.isCff()});
        } else {
            std.debug.print("Font is not an OpenType CFF font, loading as TrueType.\n", .{});
            // Use the generic loadFont which auto-detects
            const ref = doc.loadFont(fd) catch |err| {
                std.debug.print("Failed to load font: {}\n", .{err});
                return;
            };
            _ = ref;
        }
    } else {
        std.debug.print("No OpenType font file found on this system.\n", .{});
        std.debug.print("To use this example, place an .otf file in one of these paths:\n", .{});
        for (font_paths) |path| {
            std.debug.print("  {s}\n", .{path});
        }
    }

    // Always add some standard font content
    _ = try doc.getStandardFont(.helvetica);
    _ = try page.addFont("Helvetica", (try doc.getStandardFont(.helvetica)).ref);

    try page.drawText("OpenType CFF Font Embedding Example", .{
        .x = 50,
        .y = 750,
        .font = .helvetica,
        .font_size = 20,
        .color = zpdf.rgb(0, 0, 0),
    });

    try page.drawText("This document demonstrates OpenType CFF font support in zpdf.", .{
        .x = 50,
        .y = 700,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.rgb(80, 80, 80),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("opentype_fonts.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Wrote opentype_fonts.pdf ({d} bytes)\n", .{bytes.len});
}
