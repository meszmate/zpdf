const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Document = @import("../document/document.zig").Document;
const PageSize = @import("../document/page_sizes.zig").PageSize;

/// A single field in a merge record (name-value pair).
pub const MergeField = struct {
    name: []const u8,
    value: []const u8,
};

/// A record containing fields for one merge iteration.
pub const MergeRecord = struct {
    fields: []const MergeField,

    /// Look up a field value by name. Returns null if not found.
    pub fn get(self: MergeRecord, name: []const u8) ?[]const u8 {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return field.value;
            }
        }
        return null;
    }
};

/// Controls how merged output is produced.
pub const OutputMode = enum {
    /// Concatenate all records into a single PDF.
    single_file,
    /// Return separate PDF bytes for each record.
    per_record,
};

/// Options controlling the mail merge process.
pub const MergeOptions = struct {
    output_mode: OutputMode = .single_file,
};

/// Error set for mail merge operations.
pub const MergeError = error{
    NoTemplate,
    NoRecords,
};

/// A builder function that populates a document for a single record.
pub const BuilderFn = *const fn (allocator: Allocator, doc: *Document, record: MergeRecord) anyerror!void;

/// Mail merge engine: generates multiple personalized PDFs from a template and data records.
///
/// Supports two approaches:
/// 1. Template-based: provide PDF bytes containing `{{field_name}}` placeholders that get
///    replaced with field values from each record.
/// 2. Builder-based: provide a callback function that receives a `Document` and `MergeRecord`,
///    letting the caller construct pages programmatically per record.
pub const MailMerge = struct {
    allocator: Allocator,
    records: ArrayList(MergeRecord),
    options: MergeOptions,
    template_bytes: ?[]const u8,
    builder_fn: ?BuilderFn,

    /// Create a new MailMerge instance.
    pub fn init(allocator: Allocator) MailMerge {
        return .{
            .allocator = allocator,
            .records = .{},
            .options = .{},
            .template_bytes = null,
            .builder_fn = null,
        };
    }

    /// Free all resources held by the MailMerge.
    pub fn deinit(self: *MailMerge) void {
        self.records.deinit(self.allocator);
    }

    /// Set the template as raw PDF bytes containing `{{placeholder}}` markers.
    pub fn setTemplate(self: *MailMerge, pdf_bytes: []const u8) void {
        self.template_bytes = pdf_bytes;
        self.builder_fn = null;
    }

    /// Set the template as a builder function that will be called per record.
    pub fn setBuilder(self: *MailMerge, func: BuilderFn) void {
        self.builder_fn = func;
        self.template_bytes = null;
    }

    /// Add a data record to the merge.
    pub fn addRecord(self: *MailMerge, fields: []const MergeField) !void {
        try self.records.append(self.allocator, .{ .fields = fields });
    }

    /// Set merge options.
    pub fn setOptions(self: *MailMerge, opts: MergeOptions) void {
        self.options = opts;
    }

    /// Generate the merged output.
    ///
    /// In `single_file` mode, returns a single `[]u8` (caller must free).
    /// In `per_record` mode, returns a single `[]u8` as well (use `generateMultiple` for separate outputs).
    pub fn generate(self: *MailMerge, allocator: Allocator) ![]u8 {
        if (self.records.items.len == 0) return MergeError.NoRecords;

        if (self.builder_fn) |func| {
            return self.generateWithBuilder(allocator, func);
        }

        if (self.template_bytes) |tmpl| {
            return self.generateFromTemplate(allocator, tmpl);
        }

        return MergeError.NoTemplate;
    }

    /// Generate separate PDF bytes for each record (per_record mode).
    /// Caller owns all returned slices and the outer slice.
    pub fn generateMultiple(self: *MailMerge, allocator: Allocator) ![][]u8 {
        if (self.records.items.len == 0) return MergeError.NoRecords;

        var results = ArrayList([]u8){};
        errdefer {
            for (results.items) |item| {
                allocator.free(item);
            }
            results.deinit(allocator);
        }

        if (self.builder_fn) |func| {
            for (self.records.items) |record| {
                var doc = Document.init(allocator);
                defer doc.deinit();
                try func(allocator, &doc, record);
                const bytes = try doc.save(allocator);
                try results.append(allocator, bytes);
            }
        } else if (self.template_bytes) |tmpl| {
            for (self.records.items) |record| {
                const bytes = try replacePlaceholders(allocator, tmpl, record);
                try results.append(allocator, bytes);
            }
        } else {
            return MergeError.NoTemplate;
        }

        return try results.toOwnedSlice(allocator);
    }

    fn generateWithBuilder(self: *MailMerge, allocator: Allocator, func: BuilderFn) ![]u8 {
        if (self.options.output_mode == .per_record) {
            // For single output in per_record mode, just do first record
            var doc = Document.init(allocator);
            defer doc.deinit();
            try func(allocator, &doc, self.records.items[0]);
            return doc.save(allocator);
        }

        // single_file: build all records into one document
        var doc = Document.init(allocator);
        defer doc.deinit();
        for (self.records.items) |record| {
            try func(allocator, &doc, record);
        }
        return doc.save(allocator);
    }

    fn generateFromTemplate(self: *MailMerge, allocator: Allocator, tmpl: []const u8) ![]u8 {
        if (self.options.output_mode == .per_record) {
            return replacePlaceholders(allocator, tmpl, self.records.items[0]);
        }

        // single_file: concatenate all replaced copies
        // For template-based, we generate each record's PDF bytes then
        // use the merger to combine them.
        const merger_mod = @import("../modify/merger.zig");
        var merger = merger_mod.PdfMerger.init(allocator);
        defer merger.deinit();

        for (self.records.items) |record| {
            const replaced = try replacePlaceholders(allocator, tmpl, record);
            defer allocator.free(replaced);
            try merger.add(replaced);
        }

        return merger.merge(allocator);
    }
};

/// Replace all `{{field_name}}` placeholders in raw PDF bytes with field values from the record.
/// This operates at the byte level, scanning for `{{` and `}}` delimiters.
pub fn replacePlaceholders(allocator: Allocator, template: []const u8, record: MergeRecord) ![]u8 {
    var result = ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (i + 1 < template.len and template[i] == '{' and template[i + 1] == '{') {
            // Find closing }}
            const start = i + 2;
            var end: ?usize = null;
            var j: usize = start;
            while (j + 1 < template.len) : (j += 1) {
                if (template[j] == '}' and template[j + 1] == '}') {
                    end = j;
                    break;
                }
            }

            if (end) |e| {
                const field_name = template[start..e];
                if (record.get(field_name)) |value| {
                    try result.appendSlice(allocator, value);
                } else {
                    // Keep the placeholder if field not found
                    try result.appendSlice(allocator, template[i .. e + 2]);
                }
                i = e + 2;
            } else {
                // No closing }}, copy literally
                try result.append(allocator, template[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, template[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Convenience function: generate merged PDF bytes using a builder function.
///
/// This is the simplest way to do a mail merge. The builder function is called once per record
/// and receives a `Document` to populate. All records are concatenated into a single PDF.
///
/// Example:
/// ```zig
/// const result = try mergeWithBuilder(allocator, &records, myBuilder);
/// defer allocator.free(result);
/// ```
pub fn mergeWithBuilder(
    allocator: Allocator,
    records: []const MergeRecord,
    builder_fn: BuilderFn,
) ![]u8 {
    var doc = Document.init(allocator);
    defer doc.deinit();

    for (records) |record| {
        try builder_fn(allocator, &doc, record);
    }

    return doc.save(allocator);
}

// -- Tests --

test "MergeRecord.get returns field value" {
    const fields = [_]MergeField{
        .{ .name = "name", .value = "Alice" },
        .{ .name = "city", .value = "Berlin" },
    };
    const record = MergeRecord{ .fields = &fields };
    try std.testing.expectEqualStrings("Alice", record.get("name").?);
    try std.testing.expectEqualStrings("Berlin", record.get("city").?);
    try std.testing.expect(record.get("missing") == null);
}

test "replacePlaceholders replaces fields" {
    const allocator = std.testing.allocator;
    const fields = [_]MergeField{
        .{ .name = "name", .value = "Bob" },
        .{ .name = "amount", .value = "42" },
    };
    const record = MergeRecord{ .fields = &fields };

    const result = try replacePlaceholders(allocator, "Hello {{name}}, you owe {{amount}} dollars.", record);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello Bob, you owe 42 dollars.", result);
}

test "replacePlaceholders keeps unknown placeholders" {
    const allocator = std.testing.allocator;
    const fields = [_]MergeField{
        .{ .name = "name", .value = "Eve" },
    };
    const record = MergeRecord{ .fields = &fields };

    const result = try replacePlaceholders(allocator, "Hi {{name}}, ref: {{unknown}}", record);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hi Eve, ref: {{unknown}}", result);
}

test "replacePlaceholders handles unclosed braces" {
    const allocator = std.testing.allocator;
    const fields = [_]MergeField{};
    const record = MergeRecord{ .fields = &fields };

    const result = try replacePlaceholders(allocator, "test {{unclosed value", record);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("test {{unclosed value", result);
}

test "MailMerge returns error with no records" {
    var mm = MailMerge.init(std.testing.allocator);
    defer mm.deinit();
    mm.setTemplate("dummy");

    const result = mm.generate(std.testing.allocator);
    try std.testing.expectError(MergeError.NoRecords, result);
}

test "MailMerge returns error with no template" {
    var mm = MailMerge.init(std.testing.allocator);
    defer mm.deinit();

    const fields = [_]MergeField{.{ .name = "x", .value = "y" }};
    try mm.addRecord(&fields);

    const result = mm.generate(std.testing.allocator);
    try std.testing.expectError(MergeError.NoTemplate, result);
}

test "MailMerge builder single_file mode" {
    const allocator = std.testing.allocator;

    const Builder = struct {
        fn build(alloc: Allocator, doc: *Document, record: MergeRecord) anyerror!void {
            _ = alloc;
            const page = try doc.addPage(.a4);
            const name = record.get("name") orelse "Unknown";
            try page.drawText(name, .{ .x = 50, .y = 750 });
        }
    };

    var mm = MailMerge.init(allocator);
    defer mm.deinit();
    mm.setBuilder(Builder.build);

    const fields1 = [_]MergeField{.{ .name = "name", .value = "Alice" }};
    const fields2 = [_]MergeField{.{ .name = "name", .value = "Bob" }};
    try mm.addRecord(&fields1);
    try mm.addRecord(&fields2);

    const result = try mm.generate(allocator);
    defer allocator.free(result);

    // Should produce valid PDF bytes
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, result, "%PDF"));
}

test "MailMerge generateMultiple with builder" {
    const allocator = std.testing.allocator;

    const Builder = struct {
        fn build(alloc: Allocator, doc: *Document, record: MergeRecord) anyerror!void {
            _ = alloc;
            const page = try doc.addPage(.letter);
            const val = record.get("id") orelse "0";
            try page.drawText(val, .{ .x = 50, .y = 700 });
        }
    };

    var mm = MailMerge.init(allocator);
    defer mm.deinit();
    mm.setBuilder(Builder.build);

    const f1 = [_]MergeField{.{ .name = "id", .value = "1" }};
    const f2 = [_]MergeField{.{ .name = "id", .value = "2" }};
    try mm.addRecord(&f1);
    try mm.addRecord(&f2);

    const results = try mm.generateMultiple(allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
    for (results) |r| {
        try std.testing.expect(r.len > 0);
        try std.testing.expect(std.mem.startsWith(u8, r, "%PDF"));
    }
}

test "mergeWithBuilder convenience function" {
    const allocator = std.testing.allocator;

    const Builder = struct {
        fn build(alloc: Allocator, doc: *Document, record: MergeRecord) anyerror!void {
            _ = alloc;
            const page = try doc.addPage(.a4);
            const greeting = record.get("greeting") orelse "Hello";
            try page.drawText(greeting, .{ .x = 50, .y = 750 });
        }
    };

    const f1 = [_]MergeField{.{ .name = "greeting", .value = "Hi" }};
    const f2 = [_]MergeField{.{ .name = "greeting", .value = "Hey" }};
    const records = [_]MergeRecord{
        .{ .fields = &f1 },
        .{ .fields = &f2 },
    };

    const result = try mergeWithBuilder(allocator, &records, Builder.build);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, result, "%PDF"));
}
