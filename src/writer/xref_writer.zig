const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const Ref = types.Ref;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;

/// An entry in the PDF cross-reference table.
pub const XrefEntry = struct {
    offset: u64,
    gen: u16,
    in_use: bool,
};

/// Writes the cross-reference table to the buffer and returns the byte offset
/// where the xref section starts (for use in startxref).
pub fn writeXref(buffer: *ByteBuffer, entries: []const XrefEntry) !u64 {
    const xref_offset: u64 = @intCast(buffer.len());

    try buffer.write("xref\n");
    try buffer.writeFmt("0 {d}\n", .{entries.len});

    for (entries) |entry| {
        if (entry.in_use) {
            try buffer.writeFmt("{d:0>10} {d:0>5} n \n", .{ entry.offset, entry.gen });
        } else {
            try buffer.writeFmt("{d:0>10} {d:0>5} f \n", .{ entry.offset, entry.gen });
        }
    }

    return xref_offset;
}

/// Writes the PDF trailer dictionary.
pub fn writeTrailer(buffer: *ByteBuffer, size: usize, root_ref: Ref, info_ref: ?Ref) !void {
    try buffer.write("trailer\n");
    try buffer.write("<< ");
    try buffer.writeFmt("/Size {d} ", .{size});
    try buffer.writeFmt("/Root {d} {d} R ", .{ root_ref.obj_num, root_ref.gen_num });
    if (info_ref) |info| {
        try buffer.writeFmt("/Info {d} {d} R ", .{ info.obj_num, info.gen_num });
    }
    try buffer.write(">>\n");
}

// -- Tests --

test "write xref table" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    const entries = [_]XrefEntry{
        .{ .offset = 0, .gen = 65535, .in_use = false },
        .{ .offset = 9, .gen = 0, .in_use = true },
        .{ .offset = 74, .gen = 0, .in_use = true },
    };

    const offset = try writeXref(&buf, &entries);
    try std.testing.expectEqual(@as(u64, 0), offset);

    const output = buf.items();
    try std.testing.expect(std.mem.startsWith(u8, output, "xref\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "0 3\n") != null);
}

test "write trailer" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    const root = Ref{ .obj_num = 1, .gen_num = 0 };
    const info = Ref{ .obj_num = 2, .gen_num = 0 };
    try writeTrailer(&buf, 3, root, info);

    const output = buf.items();
    try std.testing.expect(std.mem.startsWith(u8, output, "trailer\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "/Root 1 0 R") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "/Info 2 0 R") != null);
}

test "write trailer without info" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    const root = Ref{ .obj_num = 1, .gen_num = 0 };
    try writeTrailer(&buf, 2, root, null);

    const output = buf.items();
    try std.testing.expect(std.mem.indexOf(u8, output, "/Info") == null);
}
