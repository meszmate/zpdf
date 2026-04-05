const std = @import("std");
const zpdf = @import("zpdf");

const OcgBuilder = zpdf.OcgBuilder;
const ObjectStore = zpdf.ObjectStore;

test "OcgBuilder: add layers with default options" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const h1 = try b.addLayer("Layer A", .{});
    const h2 = try b.addLayer("Layer B", .{ .default_state = .off });

    try std.testing.expectEqual(@as(u32, 0), h1.index);
    try std.testing.expectEqual(@as(u32, 1), h2.index);
    try std.testing.expectEqual(@as(usize, 2), b.layers.items.len);
}

test "OcgBuilder: intent values map to correct pdf names" {
    try std.testing.expectEqualStrings("View", zpdf.OcgIntent.view.pdfName());
    try std.testing.expectEqualStrings("Design", zpdf.OcgIntent.design.pdfName());
    try std.testing.expectEqualStrings("All", zpdf.OcgIntent.all.pdfName());
}

test "OcgBuilder: radio group with invalid handle errors" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    _ = try b.addLayer("x", .{});
    const bad = zpdf.OcgLayerHandle{ .index = 10 };
    try std.testing.expectError(error.InvalidLayerHandle, b.addRadioGroup(&.{bad}));
}

test "OcgBuilder: lockLayer marks the layer" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const h = try b.addLayer("L", .{});
    try b.lockLayer(h);
    try std.testing.expect(b.layers.items[0].locked);
}

test "OcgBuilder: build produces an OCProperties dict" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const a = try b.addLayer("A", .{ .default_state = .on });
    const c = try b.addLayer("B", .{ .default_state = .off, .intent = .design });
    const d = try b.addLayer("C", .{ .default_state = .off, .print_visibility = .never_print });
    try b.lockLayer(d);
    try b.addRadioGroup(&.{ a, c });

    const props_ref = try b.build(&store);
    const obj = store.get(props_ref).?;
    try std.testing.expect(obj.isDict());

    const ocgs = obj.dict_obj.get("OCGs").?;
    try std.testing.expectEqual(@as(usize, 3), ocgs.array_obj.list.items.len);

    const d_dict = obj.dict_obj.get("D").?;
    try std.testing.expectEqual(@as(usize, 1), d_dict.dict_obj.get("ON").?.array_obj.list.items.len);
    try std.testing.expectEqual(@as(usize, 2), d_dict.dict_obj.get("OFF").?.array_obj.list.items.len);
    try std.testing.expectEqual(@as(usize, 1), d_dict.dict_obj.get("RBGroups").?.array_obj.list.items.len);
    try std.testing.expectEqual(@as(usize, 1), d_dict.dict_obj.get("Locked").?.array_obj.list.items.len);
}

test "OcgBuilder: layerRef returns resolved reference after build" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const h = try b.addLayer("L", .{});
    try std.testing.expectError(error.NotBuilt, b.layerRef(h));

    _ = try b.build(&store);
    const ref = try b.layerRef(h);
    try std.testing.expect(ref.obj_num != 0);
}

test "Page.beginLayer/endLayer writes marked content" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const h = try b.addLayer("Sample", .{});
    _ = try b.build(&store);

    var page = zpdf.Page.init(std.testing.allocator, 612, 792);
    defer page.deinit();

    try page.beginLayer(&b, h);
    try page.drawRect(.{ .x = 10, .y = 10, .width = 50, .height = 50, .color = zpdf.color.rgb(0, 0, 0) });
    try page.endLayer();

    try std.testing.expect(std.mem.indexOf(u8, page.content.items, "/OC /OC1 BDC") != null);
    try std.testing.expect(std.mem.indexOf(u8, page.content.items, "EMC") != null);
    try std.testing.expectEqual(@as(usize, 1), page.resources.properties.items.len);
}

test "Document: end-to-end PDF with OCG layers" {
    var doc = zpdf.Document.init(std.testing.allocator);
    defer doc.deinit();

    doc.setTitle("OCG Test");

    const page = try doc.addPage(.a4);
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    var builder = OcgBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const foreground = try builder.addLayer("Foreground", .{ .default_state = .on });
    const hidden = try builder.addLayer("Hidden", .{ .default_state = .off });
    try builder.addRadioGroup(&.{ foreground, hidden });

    const oc_ref = try builder.build(doc.objectStore());
    doc.setOcProperties(oc_ref);

    try page.beginLayer(&builder, foreground);
    try page.drawText("visible", .{ .x = 50, .y = 700 });
    try page.endLayer();

    try page.beginLayer(&builder, hidden);
    try page.drawText("hidden", .{ .x = 50, .y = 680 });
    try page.endLayer();

    const bytes = try doc.save(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "/OCProperties") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/OCG") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/RBGroups") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/Properties") != null);
}
