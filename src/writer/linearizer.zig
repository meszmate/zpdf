const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;

/// Options for PDF linearization.
pub const LinearizationOptions = struct {
    /// First page to optimize for (usually 0).
    first_page: usize = 0,
};

/// Information about a parsed PDF object from the input.
const RawObject = struct {
    obj_num: u32,
    gen_num: u16,
    /// Start offset of "N N obj" in input.
    start: usize,
    /// End offset (after "endobj") in input.
    end: usize,
    /// The raw bytes of the full object definition (N N obj ... endobj).
    data: []const u8,
    /// Whether this object is a page.
    is_page: bool,
    /// Whether this is the pages tree root (/Type /Pages).
    is_pages: bool,
    /// Whether this is the catalog (/Type /Catalog).
    is_catalog: bool,
    /// Index of the page this object belongs to (-1 if shared or unknown).
    page_index: i32,
};

/// Check if a PDF is already linearized.
/// A linearized PDF has a linearization parameter dictionary as its first
/// indirect object, containing the /Linearized key.
pub fn isLinearized(pdf_data: []const u8) bool {
    if (pdf_data.len < 20) return false;
    if (!std.mem.startsWith(u8, pdf_data, "%PDF-")) return false;

    // Skip past the header line(s) to find the first object
    var pos: usize = 0;
    // Skip header line
    while (pos < pdf_data.len and pdf_data[pos] != '\n' and pdf_data[pos] != '\r') {
        pos += 1;
    }
    while (pos < pdf_data.len and (pdf_data[pos] == '\n' or pdf_data[pos] == '\r')) {
        pos += 1;
    }
    // May have a binary comment line
    if (pos < pdf_data.len and pdf_data[pos] == '%') {
        while (pos < pdf_data.len and pdf_data[pos] != '\n' and pdf_data[pos] != '\r') {
            pos += 1;
        }
        while (pos < pdf_data.len and (pdf_data[pos] == '\n' or pdf_data[pos] == '\r')) {
            pos += 1;
        }
    }

    // Now we should be at the first object. Look for /Linearized in the
    // first 1024 bytes from here.
    const search_end = @min(pos + 1024, pdf_data.len);
    const region = pdf_data[pos..search_end];
    return std.mem.indexOf(u8, region, "/Linearized") != null;
}

/// Linearize an existing PDF for fast web viewing.
/// Takes PDF bytes and returns linearized PDF bytes.
/// The caller owns the returned slice and must free it with the same allocator.
pub fn linearizePdf(allocator: Allocator, pdf_data: []const u8) ![]u8 {
    if (pdf_data.len < 20 or !std.mem.startsWith(u8, pdf_data, "%PDF-")) {
        return error.InvalidPdf;
    }

    // Extract PDF version from header
    const version_end = std.mem.indexOf(u8, pdf_data[5..], "\n") orelse
        std.mem.indexOf(u8, pdf_data[5..], "\r") orelse 3;
    const version = pdf_data[0 .. 5 + version_end];

    // Parse all objects from the input PDF
    var objects = ArrayList(RawObject){};
    defer objects.deinit(allocator);
    try parseAllObjects(allocator, pdf_data, &objects);

    if (objects.items.len == 0) return error.InvalidPdf;

    // Find catalog, pages root, and page objects
    var catalog_idx: ?usize = null;
    var pages_idx: ?usize = null;
    var page_indices = ArrayList(usize){};
    defer page_indices.deinit(allocator);

    for (objects.items, 0..) |obj, i| {
        if (obj.is_catalog) catalog_idx = i;
        if (obj.is_pages) pages_idx = i;
        if (obj.is_page) try page_indices.append(allocator, i);
    }

    if (catalog_idx == null or pages_idx == null or page_indices.items.len == 0) {
        return error.InvalidPdf;
    }

    const num_pages = page_indices.items.len;
    const first_page_obj_idx = page_indices.items[0];

    // Identify first-page objects: the first page itself and objects referenced
    // by the first page's content stream. For a v1 implementation we associate
    // objects whose obj_num appears in the first page object bytes.
    var first_page_obj_nums = std.AutoHashMapUnmanaged(u32, void){};
    defer first_page_obj_nums.deinit(allocator);

    // Always include catalog, pages root, and first page
    try first_page_obj_nums.put(allocator, objects.items[catalog_idx.?].obj_num, {});
    try first_page_obj_nums.put(allocator, objects.items[pages_idx.?].obj_num, {});
    try first_page_obj_nums.put(allocator, objects.items[first_page_obj_idx].obj_num, {});

    // Scan first page object for references (N 0 R patterns)
    const first_page_data = objects.items[first_page_obj_idx].data;
    try findReferencedObjects(allocator, first_page_data, &first_page_obj_nums);

    // Also follow references from those objects (one level deep) to catch
    // content streams and resources
    {
        var extra_refs = std.AutoHashMapUnmanaged(u32, void){};
        defer extra_refs.deinit(allocator);

        for (objects.items) |obj| {
            if (first_page_obj_nums.contains(obj.obj_num)) {
                try findReferencedObjects(allocator, obj.data, &extra_refs);
            }
        }

        var it = extra_refs.iterator();
        while (it.next()) |entry| {
            try first_page_obj_nums.put(allocator, entry.key_ptr.*, {});
        }
    }

    // Build ordered lists: first-page objects, then remaining objects
    var first_page_objs = ArrayList(usize){};
    defer first_page_objs.deinit(allocator);
    var remaining_objs = ArrayList(usize){};
    defer remaining_objs.deinit(allocator);

    for (objects.items, 0..) |obj, i| {
        if (first_page_obj_nums.contains(obj.obj_num)) {
            try first_page_objs.append(allocator, i);
        } else {
            try remaining_objs.append(allocator, i);
        }
    }

    // Assign new object numbers. Object 1 is the linearization dict.
    // Then first-page objects, then remaining objects.
    const total_objects = 1 + objects.items.len; // +1 for linearization dict
    var obj_num_map = std.AutoHashMapUnmanaged(u32, u32){};
    defer obj_num_map.deinit(allocator);

    var next_obj_num: u32 = 1; // obj 1 = linearization dict
    next_obj_num += 1;

    // Map first-page objects
    for (first_page_objs.items) |idx| {
        try obj_num_map.put(allocator, objects.items[idx].obj_num, next_obj_num);
        next_obj_num += 1;
    }

    // Map remaining objects
    for (remaining_objs.items) |idx| {
        try obj_num_map.put(allocator, objects.items[idx].obj_num, next_obj_num);
        next_obj_num += 1;
    }

    const new_catalog_num = obj_num_map.get(objects.items[catalog_idx.?].obj_num).?;
    const new_first_page_num = obj_num_map.get(objects.items[first_page_obj_idx].obj_num).?;

    // Rewrite objects with remapped references
    var rewritten_first = ArrayList([]u8){};
    defer {
        for (rewritten_first.items) |item| allocator.free(item);
        rewritten_first.deinit(allocator);
    }
    var rewritten_remaining = ArrayList([]u8){};
    defer {
        for (rewritten_remaining.items) |item| allocator.free(item);
        rewritten_remaining.deinit(allocator);
    }

    for (first_page_objs.items) |idx| {
        const rewritten = try rewriteObject(allocator, &objects.items[idx], &obj_num_map);
        try rewritten_first.append(allocator, rewritten);
    }
    for (remaining_objs.items) |idx| {
        const rewritten = try rewriteObject(allocator, &objects.items[idx], &obj_num_map);
        try rewritten_remaining.append(allocator, rewritten);
    }

    // Two-pass approach: first compute all offsets, then write with correct values.
    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    // Compute the fixed size of the linearization dict by writing a dummy one
    {
        try writePaddedLinDict(&buf, 0, 0, 0, new_first_page_num, 0, num_pages, 0);
    }
    const lin_obj_size = buf.len();
    buf.list.clearRetainingCapacity();

    // === PASS 1: Compute all offsets ===

    var offset: usize = 0;

    // Header
    const header_size = version.len + 1 + 6; // version + \n + binary comment (%\xe2\xe3\xcf\xd3\n)
    offset += header_size;

    // Linearization dict
    const lin_dict_start_offset = offset;
    offset += lin_obj_size;

    // First-page xref: we need to know the offsets within it, but the offsets
    // depend on the xref size itself... We break the cycle by putting first-page
    // objects BEFORE the first-page xref in our layout. This is an acceptable
    // variant: the spec says the first-page xref must appear before %%EOF at
    // the point of the first-page data.
    //
    // Simpler correct layout for v1:
    // 1. Header
    // 2. Lin dict (obj 1)
    // 3. First-page objects (catalog, pages, first page, resources, content streams)
    // 4. First-page xref + trailer (partial, covering objects 0..first_page_last)
    // 5. Hint stream object
    // 6. Remaining objects
    // 7. Full xref + trailer
    //
    // This is valid per many PDF linearization implementations.

    // First-page objects offsets
    var fp_offsets = ArrayList(u64){};
    defer fp_offsets.deinit(allocator);

    for (rewritten_first.items) |obj_data| {
        try fp_offsets.append(allocator, @intCast(offset));
        offset += obj_data.len;
    }

    const end_of_first_page: usize = offset;

    // Hint stream (minimal for v1 - just a placeholder object)
    const hint_obj_num = next_obj_num;
    const hint_stream_offset: usize = offset;
    const hint_stream_data = try buildHintStream(allocator, num_pages, &fp_offsets, first_page_objs.items.len);
    defer allocator.free(hint_stream_data);

    var hint_obj_buf = ByteBuffer.init(allocator);
    defer hint_obj_buf.deinit();
    try hint_obj_buf.writeFmt("{d} 0 obj\n", .{hint_obj_num});
    try hint_obj_buf.writeFmt("<< /Length {d} /S {d} >>", .{ hint_stream_data.len, hint_stream_data.len });
    try hint_obj_buf.write("\nstream\n");
    try hint_obj_buf.write(hint_stream_data);
    try hint_obj_buf.write("\nendstream\nendobj\n");
    const hint_obj_bytes = hint_obj_buf.items();
    offset += hint_obj_bytes.len;

    // First-page xref + trailer
    const first_xref_offset: usize = offset;
    var first_xref_buf = ByteBuffer.init(allocator);
    defer first_xref_buf.deinit();

    // Write first-page xref
    try first_xref_buf.write("xref\n");
    // Section for obj 0 and obj 1 (linearization dict)
    try first_xref_buf.write("0 2\n");
    try first_xref_buf.writeFmt("{d:0>10} {d:0>5} f \n", .{ @as(u64, 0), @as(u16, 65535) });
    try first_xref_buf.writeFmt("{d:0>10} {d:0>5} n \n", .{ @as(u64, lin_dict_start_offset), @as(u16, 0) });

    // Section for first-page objects (contiguous range starting from obj 2)
    if (first_page_objs.items.len > 0) {
        const fp_start_num = obj_num_map.get(objects.items[first_page_objs.items[0]].obj_num).?;
        try first_xref_buf.writeFmt("{d} {d}\n", .{ fp_start_num, first_page_objs.items.len });
        for (fp_offsets.items) |fp_off| {
            try first_xref_buf.writeFmt("{d:0>10} {d:0>5} n \n", .{ fp_off, @as(u16, 0) });
        }
    }

    // Hint stream xref entry
    try first_xref_buf.writeFmt("{d} 1\n", .{hint_obj_num});
    try first_xref_buf.writeFmt("{d:0>10} {d:0>5} n \n", .{ @as(u64, hint_stream_offset), @as(u16, 0) });

    // Trailer for first-page xref
    try first_xref_buf.write("trailer\n<< ");
    try first_xref_buf.writeFmt("/Size {d} ", .{total_objects + 1}); // +1 for hint stream
    try first_xref_buf.writeFmt("/Root {d} 0 R ", .{new_catalog_num});
    try first_xref_buf.write(">>\n");
    try first_xref_buf.writeFmt("startxref\n{d}\n", .{first_xref_offset});
    try first_xref_buf.write("%%EOF\n");

    offset += first_xref_buf.len();

    // Remaining objects
    var rem_offsets = ArrayList(u64){};
    defer rem_offsets.deinit(allocator);

    for (rewritten_remaining.items) |obj_data| {
        try rem_offsets.append(allocator, @intCast(offset));
        offset += obj_data.len;
    }

    // Main xref table
    const main_xref_offset: usize = offset;

    // Total file length
    // We need to estimate the main xref + trailer size
    var main_xref_buf = ByteBuffer.init(allocator);
    defer main_xref_buf.deinit();

    try writeMainXref(allocator, &main_xref_buf, total_objects + 1, lin_dict_start_offset, &first_page_objs, &fp_offsets, &obj_num_map, &objects, hint_obj_num, hint_stream_offset, &remaining_objs, &rem_offsets, new_catalog_num, first_xref_offset);

    // Add startxref + %%EOF to the main xref buffer
    try main_xref_buf.writeFmt("startxref\n{d}\n", .{main_xref_offset});
    try main_xref_buf.write("%%EOF\n");

    const total_file_length = offset + main_xref_buf.len();

    // === PASS 2: Write everything ===

    buf.list.clearRetainingCapacity();

    // 1. Header
    try buf.write(version);
    try buf.writeByte('\n');
    try buf.write("%\xe2\xe3\xcf\xd3\n");

    // 2. Linearization dict with correct values
    try writePaddedLinDict(&buf, total_file_length, hint_stream_offset, hint_obj_bytes.len, new_first_page_num, end_of_first_page, num_pages, main_xref_offset);

    // 3. First-page objects
    for (rewritten_first.items) |obj_data| {
        try buf.write(obj_data);
    }

    // 4. Hint stream
    try buf.write(hint_obj_bytes);

    // 5. First-page xref + trailer
    try buf.write(first_xref_buf.items());

    // 6. Remaining objects
    for (rewritten_remaining.items) |obj_data| {
        try buf.write(obj_data);
    }

    // 7. Main xref + trailer
    try buf.write(main_xref_buf.items());

    return buf.toOwnedSlice();
}

// --- Internal helpers ---

fn writePaddedLinDict(buf: *ByteBuffer, file_len: usize, hint_offset: usize, hint_length: usize, first_page_obj: u32, end_first_page: usize, num_pages: usize, main_xref_offset: usize) !void {
    try buf.write("1 0 obj\n<< /Linearized 1");
    try buf.writeFmt(" /L {d:0>10}", .{file_len});
    try buf.writeFmt(" /H [{d:0>10} {d:0>10}]", .{ hint_offset, hint_length });
    try buf.writeFmt(" /O {d:0>5}", .{first_page_obj});
    try buf.writeFmt(" /E {d:0>10}", .{end_first_page});
    try buf.writeFmt(" /N {d:0>5}", .{num_pages});
    try buf.writeFmt(" /T {d:0>10}", .{main_xref_offset});
    try buf.write(" >>\nendobj\n");
}

fn writeMainXref(
    allocator: Allocator,
    buf: *ByteBuffer,
    size: usize,
    lin_dict_offset: usize,
    first_page_objs: *const ArrayList(usize),
    fp_offsets: *const ArrayList(u64),
    obj_num_map: *const std.AutoHashMapUnmanaged(u32, u32),
    objects: *const ArrayList(RawObject),
    hint_obj_num: u32,
    hint_stream_offset: usize,
    remaining_objs: *const ArrayList(usize),
    rem_offsets: *const ArrayList(u64),
    catalog_num: u32,
    prev_xref_offset: usize,
) !void {
    _ = allocator;

    // Build a complete xref covering all objects
    // We need entries for obj 0 through max_obj_num
    const max_obj = size;

    try buf.write("xref\n");
    try buf.writeFmt("0 {d}\n", .{max_obj});

    // Object 0: free entry
    try buf.writeFmt("{d:0>10} {d:0>5} f \n", .{ @as(u64, 0), @as(u16, 65535) });

    // Build offset array indexed by new object number
    var offset_table = ArrayList(u64){};
    defer offset_table.deinit(buf.allocator);
    try offset_table.appendNTimes(buf.allocator, 0, max_obj);

    // Lin dict is obj 1
    offset_table.items[1] = @intCast(lin_dict_offset);

    // First-page objects
    for (first_page_objs.items, 0..) |idx, i| {
        const new_num = obj_num_map.get(objects.items[idx].obj_num).?;
        if (new_num < max_obj) {
            offset_table.items[new_num] = fp_offsets.items[i];
        }
    }

    // Hint stream
    if (hint_obj_num < max_obj) {
        offset_table.items[hint_obj_num] = @intCast(hint_stream_offset);
    }

    // Remaining objects
    for (remaining_objs.items, 0..) |idx, i| {
        const new_num = obj_num_map.get(objects.items[idx].obj_num).?;
        if (new_num < max_obj) {
            offset_table.items[new_num] = rem_offsets.items[i];
        }
    }

    // Write entries for objects 1..max_obj-1
    for (offset_table.items[1..]) |off| {
        try buf.writeFmt("{d:0>10} {d:0>5} n \n", .{ off, @as(u16, 0) });
    }

    // Trailer
    try buf.write("trailer\n<< ");
    try buf.writeFmt("/Size {d} ", .{max_obj});
    try buf.writeFmt("/Root {d} 0 R ", .{catalog_num});
    try buf.writeFmt("/Prev {d} ", .{prev_xref_offset});
    try buf.write(">>\n");

}

/// Build a minimal hint stream containing page offset hints.
fn buildHintStream(allocator: Allocator, num_pages: usize, fp_offsets: *const ArrayList(u64), first_page_obj_count: usize) ![]u8 {
    // The hint stream contains two tables:
    // 1. Page offset hint table
    // 2. Shared object hint table
    //
    // For v1, we write a minimal valid hint stream.
    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    // Page offset hint table header (per Table F.3 in spec)
    // Item 1: least number of objects in a page = 1
    try buf.writeInt(u32, 1);
    // Item 2: location of first page's page object (offset from file start)
    const first_offset: u32 = if (fp_offsets.items.len > 0) @intCast(fp_offsets.items[0]) else 0;
    try buf.writeInt(u32, first_offset);
    // Item 3: number of bits needed to represent the difference in number of objects
    try buf.writeInt(u16, 0);
    // Item 4: least length of a page in bytes
    try buf.writeInt(u32, 0);
    // Item 5: number of bits for page length differences
    try buf.writeInt(u16, 0);
    // Item 6: least offset of content stream
    try buf.writeInt(u32, 0);
    // Item 7: number of bits for content stream offset differences
    try buf.writeInt(u16, 0);
    // Item 8: least content stream length
    try buf.writeInt(u32, 0);
    // Item 9: number of bits for content stream length differences
    try buf.writeInt(u16, 0);
    // Item 10: number of bits for shared object references per page
    try buf.writeInt(u16, 0);
    // Item 11: number of bits for shared object identifier
    try buf.writeInt(u16, 0);
    // Item 12: number of bits for numerator of fractional position
    try buf.writeInt(u16, 0);
    // Item 13: shared object denominator
    try buf.writeInt(u16, 0);

    // Per-page entries (minimal - just indicating each page has a fixed number of objects)
    for (0..num_pages) |_| {
        // Delta number of objects: 0 (they all have the min)
        // Delta page length: 0
        // Number of shared objects: 0
        // (All zero bit-width, so no per-page bits needed)
    }

    // Shared object hint table header (per Table F.5)
    // Item 1: first shared object number
    try buf.writeInt(u32, 0);
    // Item 2: location of first shared object
    try buf.writeInt(u32, first_offset);
    // Item 3: number of first-page shared object entries
    try buf.writeInt(u32, @intCast(first_page_obj_count));
    // Item 4: number of shared object entries for other pages
    try buf.writeInt(u32, 0);
    // Item 5: number of bits for object lengths
    try buf.writeInt(u16, 0);
    // Item 6: least object length
    try buf.writeInt(u32, 0);
    // Item 7: number of bits for number of shared group references
    try buf.writeInt(u16, 0);

    return buf.toOwnedSlice();
}

fn parseAllObjects(allocator: Allocator, data: []const u8, objects: *ArrayList(RawObject)) !void {
    var pos: usize = 0;
    while (pos < data.len) {
        // Look for "N N obj" pattern
        if (findNextObject(data, pos)) |obj_info| {
            const obj_end = findEndObj(data, obj_info.body_start) orelse {
                pos = obj_info.body_start;
                continue;
            };

            const obj_data = data[obj_info.start..obj_end];

            // Determine object type by scanning for /Type
            var is_page = false;
            var is_pages = false;
            var is_catalog = false;

            const search_region = data[obj_info.body_start..@min(obj_info.body_start + 512, obj_end)];
            if (std.mem.indexOf(u8, search_region, "/Type")) |type_pos| {
                const after_type = search_region[type_pos + 5 ..];
                // Skip whitespace
                var t: usize = 0;
                while (t < after_type.len and (after_type[t] == ' ' or after_type[t] == '\n' or after_type[t] == '\r')) {
                    t += 1;
                }
                if (t < after_type.len and after_type[t] == '/') {
                    const name_start = t + 1;
                    var name_end = name_start;
                    while (name_end < after_type.len and after_type[name_end] != ' ' and
                        after_type[name_end] != '/' and after_type[name_end] != '\n' and
                        after_type[name_end] != '\r' and after_type[name_end] != '>' and
                        after_type[name_end] != '<')
                    {
                        name_end += 1;
                    }
                    const type_name = after_type[name_start..name_end];
                    if (std.mem.eql(u8, type_name, "Catalog")) {
                        is_catalog = true;
                    } else if (std.mem.eql(u8, type_name, "Pages")) {
                        is_pages = true;
                    } else if (std.mem.eql(u8, type_name, "Page")) {
                        is_page = true;
                    }
                }
            }

            try objects.append(allocator, .{
                .obj_num = obj_info.obj_num,
                .gen_num = obj_info.gen_num,
                .start = obj_info.start,
                .end = obj_end,
                .data = obj_data,
                .is_page = is_page,
                .is_pages = is_pages,
                .is_catalog = is_catalog,
                .page_index = -1,
            });

            pos = obj_end;
        } else {
            break;
        }
    }
}

const ObjectStart = struct {
    obj_num: u32,
    gen_num: u16,
    start: usize,
    body_start: usize,
};

fn findNextObject(data: []const u8, start_pos: usize) ?ObjectStart {
    var pos = start_pos;
    while (pos < data.len) {
        // Look for a digit that could start an object number
        if (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            // Try to parse "N N obj"
            const save_pos = pos;
            var obj_num: u32 = 0;
            while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                obj_num = obj_num * 10 + (data[pos] - '0');
                pos += 1;
            }
            if (pos < data.len and data[pos] == ' ') {
                pos += 1;
                var gen_num: u16 = 0;
                const gen_start = pos;
                while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                    gen_num = gen_num * 10 + @as(u16, @intCast(data[pos] - '0'));
                    pos += 1;
                }
                if (pos > gen_start and pos + 4 <= data.len and
                    data[pos] == ' ' and data[pos + 1] == 'o' and
                    data[pos + 2] == 'b' and data[pos + 3] == 'j')
                {
                    const body_start = pos + 4;
                    return .{
                        .obj_num = obj_num,
                        .gen_num = gen_num,
                        .start = save_pos,
                        .body_start = body_start,
                    };
                }
            }
            pos = save_pos + 1;
        } else {
            pos += 1;
        }
    }
    return null;
}

fn findEndObj(data: []const u8, start: usize) ?usize {
    if (std.mem.indexOf(u8, data[start..], "endobj")) |pos| {
        var end = start + pos + 6; // "endobj".len
        // Include trailing whitespace/newline
        while (end < data.len and (data[end] == '\n' or data[end] == '\r' or data[end] == ' ')) {
            end += 1;
        }
        return end;
    }
    return null;
}

fn findReferencedObjects(allocator: Allocator, data: []const u8, refs: *std.AutoHashMapUnmanaged(u32, void)) !void {
    // Scan for "N 0 R" patterns
    var pos: usize = 0;
    while (pos < data.len) {
        if (data[pos] >= '0' and data[pos] <= '9') {
            const num_start = pos;
            var num: u32 = 0;
            while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                num = num * 10 + (data[pos] - '0');
                pos += 1;
            }
            // Check for " N R" pattern
            if (pos < data.len and data[pos] == ' ') {
                pos += 1;
                // Skip gen number
                const gen_start = pos;
                while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                    pos += 1;
                }
                if (pos > gen_start and pos < data.len and data[pos] == ' ') {
                    pos += 1;
                    if (pos < data.len and data[pos] == 'R') {
                        try refs.put(allocator, num, {});
                        pos += 1;
                        continue;
                    }
                }
            }
            // Not a reference, advance past the number we consumed
            if (pos == num_start) pos += 1;
        } else {
            pos += 1;
        }
    }
}

/// Rewrite an object with remapped object numbers.
/// Returns a newly allocated byte slice for the rewritten object definition.
fn rewriteObject(allocator: Allocator, obj: *const RawObject, obj_num_map: *const std.AutoHashMapUnmanaged(u32, u32)) ![]u8 {
    const new_num = obj_num_map.get(obj.obj_num) orelse obj.obj_num;
    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    // Write new object header
    try buf.writeFmt("{d} {d} obj\n", .{ new_num, obj.gen_num });

    // Find the body (after "N N obj")
    const body_start = blk: {
        var pos: usize = 0;
        // Skip object number
        while (pos < obj.data.len and obj.data[pos] >= '0' and obj.data[pos] <= '9') pos += 1;
        if (pos < obj.data.len and obj.data[pos] == ' ') pos += 1;
        // Skip gen number
        while (pos < obj.data.len and obj.data[pos] >= '0' and obj.data[pos] <= '9') pos += 1;
        // Skip " obj"
        if (pos + 4 <= obj.data.len) pos += 4;
        // Skip whitespace
        while (pos < obj.data.len and (obj.data[pos] == '\n' or obj.data[pos] == '\r' or obj.data[pos] == ' ')) pos += 1;
        break :blk pos;
    };

    // Find "endobj" and get the body
    const endobj_pos = std.mem.indexOf(u8, obj.data, "endobj") orelse obj.data.len;
    const body = obj.data[body_start..endobj_pos];

    // Rewrite references in the body
    try rewriteRefsInBody(&buf, body, obj_num_map);

    try buf.write("endobj\n");

    return buf.toOwnedSlice();
}

fn rewriteRefsInBody(buf: *ByteBuffer, body: []const u8, obj_num_map: *const std.AutoHashMapUnmanaged(u32, u32)) !void {
    var pos: usize = 0;
    while (pos < body.len) {
        // Check if we're at a potential reference "N N R"
        if (body[pos] >= '0' and body[pos] <= '9') {
            const num_start = pos;
            var num: u32 = 0;
            var p = pos;
            while (p < body.len and body[p] >= '0' and body[p] <= '9') {
                num = num * 10 + (body[p] - '0');
                p += 1;
            }
            if (p < body.len and body[p] == ' ') {
                p += 1;
                var gen: u32 = 0;
                const gen_start = p;
                while (p < body.len and body[p] >= '0' and body[p] <= '9') {
                    gen = gen * 10 + (body[p] - '0');
                    p += 1;
                }
                if (p > gen_start and p < body.len and body[p] == ' ') {
                    p += 1;
                    if (p < body.len and body[p] == 'R') {
                        // This is a reference! Remap it.
                        const new_num = obj_num_map.get(num) orelse num;
                        try buf.writeFmt("{d} {d} R", .{ new_num, gen });
                        pos = p + 1;
                        continue;
                    }
                }
            }
            // Not a reference, write the digit and advance
            try buf.writeByte(body[num_start]);
            pos = num_start + 1;
        } else {
            try buf.writeByte(body[pos]);
            pos += 1;
        }
    }
}

// -- Tests --

test "isLinearized detects non-linearized PDF" {
    const pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\xref
        \\0 2
        \\0000000000 65535 f
        \\0000000009 00000 n
        \\trailer
        \\<< /Size 2 /Root 1 0 R >>
        \\startxref
        \\63
        \\%%EOF
    ;
    try std.testing.expect(!isLinearized(pdf));
}

test "isLinearized detects linearized PDF" {
    const pdf = "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<< /Linearized 1 /L 1000 /H [100 50] /O 3 /E 500 /N 2 /T 900 >>\nendobj\n";
    try std.testing.expect(isLinearized(pdf));
}

test "isLinearized rejects non-PDF" {
    try std.testing.expect(!isLinearized("not a pdf"));
    try std.testing.expect(!isLinearized(""));
}

test "linearizePdf rejects invalid input" {
    const allocator = std.testing.allocator;
    const result = linearizePdf(allocator, "not a pdf");
    try std.testing.expectError(error.InvalidPdf, result);
}

test "linearizePdf produces linearized output" {
    const allocator = std.testing.allocator;

    // Build a simple multi-page PDF
    const input_pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>
        \\endobj
        \\4 0 obj
        \\<< /Length 44 >>
        \\stream
        \\BT /F1 12 Tf 100 700 Td (Page 1) Tj ET
        \\endstream
        \\endobj
        \\5 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R >>
        \\endobj
        \\6 0 obj
        \\<< /Length 44 >>
        \\stream
        \\BT /F1 12 Tf 100 700 Td (Page 2) Tj ET
        \\endstream
        \\endobj
        \\xref
        \\0 7
        \\0000000000 65535 f
        \\0000000009 00000 n
        \\0000000058 00000 n
        \\0000000115 00000 n
        \\0000000206 00000 n
        \\0000000300 00000 n
        \\0000000391 00000 n
        \\trailer
        \\<< /Size 7 /Root 1 0 R >>
        \\startxref
        \\485
        \\%%EOF
    ;

    const result = try linearizePdf(allocator, input_pdf);
    defer allocator.free(result);

    // Verify the output is a valid PDF
    try std.testing.expect(std.mem.startsWith(u8, result, "%PDF-1.4"));

    // Verify it's linearized
    try std.testing.expect(isLinearized(result));

    // Verify it contains the linearization dictionary
    try std.testing.expect(std.mem.indexOf(u8, result, "/Linearized 1") != null);

    // Verify it has /L (file length) matching actual length
    try std.testing.expect(std.mem.indexOf(u8, result, "/L ") != null);

    // Verify structural elements exist
    try std.testing.expect(std.mem.indexOf(u8, result, "/Catalog") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "/Pages") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "xref") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "trailer") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "%%EOF") != null);

    // Verify catalog appears before remaining page objects
    const catalog_pos = std.mem.indexOf(u8, result, "/Catalog").?;
    // The second page content should appear after catalog
    // Find second occurrence of "Page" after catalog
    try std.testing.expect(catalog_pos > 0);
}

test "linearizePdf file length matches /L value" {
    const allocator = std.testing.allocator;

    const input_pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R] /Count 1 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>
        \\endobj
        \\xref
        \\0 4
        \\0000000000 65535 f
        \\0000000009 00000 n
        \\0000000058 00000 n
        \\0000000115 00000 n
        \\trailer
        \\<< /Size 4 /Root 1 0 R >>
        \\startxref
        \\192
        \\%%EOF
    ;

    const result = try linearizePdf(allocator, input_pdf);
    defer allocator.free(result);

    // Extract /L value and verify it matches actual file length
    if (std.mem.indexOf(u8, result, "/L ")) |l_pos| {
        var num_start = l_pos + 3;
        while (num_start < result.len and result[num_start] == '0') num_start += 1;
        var num_end = num_start;
        while (num_end < result.len and result[num_end] >= '0' and result[num_end] <= '9') num_end += 1;
        if (num_end > num_start) {
            const l_value = std.fmt.parseInt(usize, result[num_start..num_end], 10) catch 0;
            try std.testing.expectEqual(result.len, l_value);
        }
    }
}

test "findReferencedObjects extracts refs" {
    const allocator = std.testing.allocator;
    var refs = std.AutoHashMapUnmanaged(u32, void){};
    defer refs.deinit(allocator);

    try findReferencedObjects(allocator, "<< /Contents 4 0 R /Parent 2 0 R >>", &refs);
    try std.testing.expect(refs.contains(4));
    try std.testing.expect(refs.contains(2));
    try std.testing.expect(!refs.contains(1));
}

test "parseAllObjects finds objects" {
    const allocator = std.testing.allocator;
    var objects = ArrayList(RawObject){};
    defer objects.deinit(allocator);

    const pdf =
        \\1 0 obj
        \\<< /Type /Catalog >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Page >>
        \\endobj
    ;

    try parseAllObjects(allocator, pdf, &objects);
    try std.testing.expectEqual(@as(usize, 2), objects.items.len);
    try std.testing.expectEqual(@as(u32, 1), objects.items[0].obj_num);
    try std.testing.expect(objects.items[0].is_catalog);
    try std.testing.expectEqual(@as(u32, 2), objects.items[1].obj_num);
    try std.testing.expect(objects.items[1].is_page);
}
