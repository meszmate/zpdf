const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Tagged PDF structure element types.
pub const StructureTag = enum {
    document,
    part,
    section,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    p,
    div_,
    list,
    list_item,
    table_,
    table_row,
    table_header,
    table_data,
    figure,
    span,
    link,
    quote,
    note,

    /// Returns the PDF structure type name for this tag.
    pub fn pdfTagName(self: StructureTag) []const u8 {
        return switch (self) {
            .document => "Document",
            .part => "Part",
            .section => "Sect",
            .h1 => "H1",
            .h2 => "H2",
            .h3 => "H3",
            .h4 => "H4",
            .h5 => "H5",
            .h6 => "H6",
            .p => "P",
            .div_ => "Div",
            .list => "L",
            .list_item => "LI",
            .table_ => "Table",
            .table_row => "TR",
            .table_header => "TH",
            .table_data => "TD",
            .figure => "Figure",
            .span => "Span",
            .link => "Link",
            .quote => "Quote",
            .note => "Note",
        };
    }
};

/// A node in the structure tree.
const StructureNode = struct {
    tag: StructureTag,
    parent_index: ?usize,
    children: ArrayList(usize),

    fn deinit(self: *StructureNode, allocator: Allocator) void {
        self.children.deinit(allocator);
    }
};

/// Manages a tagged PDF structure tree for accessibility.
pub const StructureTree = struct {
    allocator: Allocator,
    nodes: ArrayList(StructureNode),
    current_stack: ArrayList(usize),
    root_children: ArrayList(usize),

    /// Initialize an empty structure tree.
    pub fn init(allocator: Allocator) StructureTree {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .current_stack = .{},
            .root_children = .{},
        };
    }

    /// Free all resources.
    pub fn deinit(self: *StructureTree) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.current_stack.deinit(self.allocator);
        self.root_children.deinit(self.allocator);
    }

    /// Begin a new structure element with the given tag.
    /// The element is added as a child of the current element (or as a root child).
    pub fn beginElement(self: *StructureTree, tag: StructureTag) !void {
        const idx = self.nodes.items.len;
        const parent_index = if (self.current_stack.items.len > 0)
            self.current_stack.items[self.current_stack.items.len - 1]
        else
            null;

        try self.nodes.append(self.allocator, .{
            .tag = tag,
            .parent_index = parent_index,
            .children = .{},
        });

        if (parent_index) |pi| {
            try self.nodes.items[pi].children.append(self.allocator, idx);
        } else {
            try self.root_children.append(self.allocator, idx);
        }

        try self.current_stack.append(self.allocator, idx);
    }

    /// End the current structure element, returning to the parent.
    pub fn endElement(self: *StructureTree) !void {
        if (self.current_stack.items.len == 0) {
            return error.NoOpenElement;
        }
        _ = self.current_stack.pop();
    }

    /// Returns the number of structure nodes.
    pub fn nodeCount(self: *const StructureTree) usize {
        return self.nodes.items.len;
    }

    /// Returns the current nesting depth.
    pub fn depth(self: *const StructureTree) usize {
        return self.current_stack.items.len;
    }

    /// Get the tag of a node at a given index.
    pub fn getTag(self: *const StructureTree, index: usize) ?StructureTag {
        if (index >= self.nodes.items.len) return null;
        return self.nodes.items[index].tag;
    }

    /// Get the children indices of a node.
    pub fn getChildren(self: *const StructureTree, index: usize) ?[]const usize {
        if (index >= self.nodes.items.len) return null;
        return self.nodes.items[index].children.items;
    }
};

// -- Tests --

test "structure tree: init and deinit" {
    var tree = StructureTree.init(std.testing.allocator);
    defer tree.deinit();
    try std.testing.expectEqual(@as(usize, 0), tree.nodeCount());
}

test "structure tree: begin and end element" {
    var tree = StructureTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.beginElement(.document);
    try std.testing.expectEqual(@as(usize, 1), tree.depth());
    try std.testing.expectEqual(@as(usize, 1), tree.nodeCount());

    try tree.endElement();
    try std.testing.expectEqual(@as(usize, 0), tree.depth());
}

test "structure tree: nested elements" {
    var tree = StructureTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.beginElement(.document);
    try tree.beginElement(.section);
    try tree.beginElement(.h1);
    try std.testing.expectEqual(@as(usize, 3), tree.depth());

    try tree.endElement(); // close h1
    try tree.beginElement(.p);
    try tree.endElement(); // close p
    try tree.endElement(); // close section
    try tree.endElement(); // close document

    try std.testing.expectEqual(@as(usize, 0), tree.depth());
    try std.testing.expectEqual(@as(usize, 4), tree.nodeCount());
}

test "structure tree: parent-child relationships" {
    var tree = StructureTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.beginElement(.document);
    try tree.beginElement(.p);
    try tree.endElement();
    try tree.beginElement(.p);
    try tree.endElement();
    try tree.endElement();

    // Document (0) should have 2 children
    const children = tree.getChildren(0).?;
    try std.testing.expectEqual(@as(usize, 2), children.len);
    try std.testing.expectEqual(@as(usize, 1), children[0]);
    try std.testing.expectEqual(@as(usize, 2), children[1]);
}

test "structure tree: tag names" {
    try std.testing.expectEqualStrings("Document", StructureTag.document.pdfTagName());
    try std.testing.expectEqualStrings("H1", StructureTag.h1.pdfTagName());
    try std.testing.expectEqualStrings("P", StructureTag.p.pdfTagName());
    try std.testing.expectEqualStrings("Table", StructureTag.table_.pdfTagName());
    try std.testing.expectEqualStrings("Div", StructureTag.div_.pdfTagName());
    try std.testing.expectEqualStrings("L", StructureTag.list.pdfTagName());
    try std.testing.expectEqualStrings("LI", StructureTag.list_item.pdfTagName());
}

test "structure tree: end element on empty stack" {
    var tree = StructureTree.init(std.testing.allocator);
    defer tree.deinit();

    const result = tree.endElement();
    try std.testing.expectError(error.NoOpenElement, result);
}

test "structure tree: root children" {
    var tree = StructureTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.beginElement(.p);
    try tree.endElement();
    try tree.beginElement(.p);
    try tree.endElement();

    try std.testing.expectEqual(@as(usize, 2), tree.root_children.items.len);
}
