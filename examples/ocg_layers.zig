const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("OCG Layers Example");

    const page = try doc.addPage(zpdf.PageSize.a4);
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Build layer definitions.
    var builder = zpdf.OcgBuilder.init(allocator);
    defer builder.deinit();

    const background = try builder.addLayer("Background", .{ .default_state = .on });
    const annotations = try builder.addLayer("Annotations", .{
        .default_state = .on,
        .intent = .view,
    });
    const design_notes = try builder.addLayer("Design Notes", .{
        .default_state = .off,
        .intent = .design,
        .print_visibility = .never_print,
    });
    const watermark = try builder.addLayer("Watermark", .{
        .default_state = .on,
        .print_visibility = .always_print,
    });

    // Lock the watermark so end-users cannot toggle it.
    try builder.lockLayer(watermark);

    // Make "Annotations" and "Design Notes" mutually exclusive.
    try builder.addRadioGroup(&.{ annotations, design_notes });

    // Resolve OCGs + /OCProperties into the object store.
    const oc_props_ref = try builder.build(doc.objectStore());
    doc.setOcProperties(oc_props_ref);

    // Draw content inside each layer.
    try page.beginLayer(&builder, background);
    try page.drawRect(.{
        .x = 50, .y = 600, .width = 500, .height = 180,
        .color = zpdf.color.rgb(230, 240, 255),
    });
    try page.endLayer();

    try page.beginLayer(&builder, annotations);
    try page.drawText("Annotation: review this section.", .{
        .x = 72, .y = 700, .font_size = 14,
        .color = zpdf.color.rgb(180, 0, 0),
    });
    try page.endLayer();

    try page.beginLayer(&builder, design_notes);
    try page.drawText("Designer note: margin = 72pt.", .{
        .x = 72, .y = 660, .font_size = 10,
        .color = zpdf.color.rgb(60, 60, 60),
    });
    try page.endLayer();

    try page.beginLayer(&builder, watermark);
    try page.drawText("DRAFT", .{
        .x = 220, .y = 400, .font_size = 80,
        .color = zpdf.color.rgb(220, 220, 220),
    });
    try page.endLayer();

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("ocg_layers.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created ocg_layers.pdf ({d} bytes)\n", .{bytes.len});
}
