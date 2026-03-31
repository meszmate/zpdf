const std = @import("std");
const Allocator = std.mem.Allocator;

/// A byte buffer for sequential binary writing, wrapping an ArrayListUnmanaged(u8).
pub const ByteBuffer = struct {
    list: std.ArrayListUnmanaged(u8) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) ByteBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ByteBuffer) void {
        self.list.deinit(self.allocator);
    }

    /// Append a slice of bytes to the buffer.
    pub fn write(self: *ByteBuffer, bytes: []const u8) Allocator.Error!void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    /// Append a single byte to the buffer.
    pub fn writeByte(self: *ByteBuffer, byte: u8) Allocator.Error!void {
        try self.list.append(self.allocator, byte);
    }

    /// Write an integer in big-endian byte order.
    pub fn writeInt(self: *ByteBuffer, comptime T: type, value: T) Allocator.Error!void {
        const bytes = std.mem.toBytes(std.mem.nativeToBig(T, value));
        try self.list.appendSlice(self.allocator, &bytes);
    }

    /// Write a formatted string into the buffer.
    pub fn writeFmt(self: *ByteBuffer, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
        const writer = self.list.writer(self.allocator);
        writer.print(fmt, args) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Return the buffer contents as an owned slice, resetting the buffer.
    pub fn toOwnedSlice(self: *ByteBuffer) Allocator.Error![]u8 {
        return try self.list.toOwnedSlice(self.allocator);
    }

    /// Get the current contents of the buffer as a read-only slice.
    pub fn items(self: *const ByteBuffer) []const u8 {
        return self.list.items;
    }

    /// Return the current length of the buffer.
    pub fn len(self: *const ByteBuffer) usize {
        return self.list.items.len;
    }
};

test "ByteBuffer: init and deinit" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 0), buf.len());
}

test "ByteBuffer: write bytes" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.write("hello");
    try std.testing.expectEqualSlices(u8, "hello", buf.items());
    try std.testing.expectEqual(@as(usize, 5), buf.len());
}

test "ByteBuffer: writeByte" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.writeByte(0x42);
    try buf.writeByte(0x43);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x42, 0x43 }, buf.items());
}

test "ByteBuffer: writeInt big-endian" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.writeInt(u32, 0x01020304);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03, 0x04 }, buf.items());
}

test "ByteBuffer: writeInt u16" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.writeInt(u16, 0xABCD);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAB, 0xCD }, buf.items());
}

test "ByteBuffer: writeFmt" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.writeFmt("{d} {s}", .{ 42, "world" });
    try std.testing.expectEqualSlices(u8, "42 world", buf.items());
}

test "ByteBuffer: toOwnedSlice" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.write("data");
    const slice = try buf.toOwnedSlice();
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(u8, "data", slice);
    try std.testing.expectEqual(@as(usize, 0), buf.len());
}

test "ByteBuffer: multiple writes" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();

    try buf.write("abc");
    try buf.writeByte('d');
    try buf.write("ef");
    try std.testing.expectEqualSlices(u8, "abcdef", buf.items());
    try std.testing.expectEqual(@as(usize, 6), buf.len());
}
