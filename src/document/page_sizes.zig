const std = @import("std");

/// Predefined standard page sizes in PDF points (1 pt = 1/72 inch).
pub const PageSize = enum {
    a0,
    a1,
    a2,
    a3,
    a4,
    a5,
    a6,
    a7,
    a8,
    b0,
    b1,
    b2,
    b3,
    b4,
    b5,
    letter,
    legal,
    tabloid,
    ledger,
    executive,
    folio,
    quarto,

    /// Width and height in PDF points.
    pub const Dimensions = struct {
        width: f32,
        height: f32,
    };

    /// Returns the portrait dimensions for this page size.
    pub fn dimensions(self: PageSize) Dimensions {
        return switch (self) {
            .a0 => .{ .width = 2383.94, .height = 3370.39 },
            .a1 => .{ .width = 1683.78, .height = 2383.94 },
            .a2 => .{ .width = 1190.55, .height = 1683.78 },
            .a3 => .{ .width = 841.89, .height = 1190.55 },
            .a4 => .{ .width = 595.28, .height = 841.89 },
            .a5 => .{ .width = 419.53, .height = 595.28 },
            .a6 => .{ .width = 297.64, .height = 419.53 },
            .a7 => .{ .width = 209.76, .height = 297.64 },
            .a8 => .{ .width = 147.40, .height = 209.76 },
            .b0 => .{ .width = 2834.65, .height = 4008.19 },
            .b1 => .{ .width = 2004.09, .height = 2834.65 },
            .b2 => .{ .width = 1417.32, .height = 2004.09 },
            .b3 => .{ .width = 1000.63, .height = 1417.32 },
            .b4 => .{ .width = 708.66, .height = 1000.63 },
            .b5 => .{ .width = 498.90, .height = 708.66 },
            .letter => .{ .width = 612.0, .height = 792.0 },
            .legal => .{ .width = 612.0, .height = 1008.0 },
            .tabloid => .{ .width = 792.0, .height = 1224.0 },
            .ledger => .{ .width = 1224.0, .height = 792.0 },
            .executive => .{ .width = 522.0, .height = 756.0 },
            .folio => .{ .width = 612.0, .height = 936.0 },
            .quarto => .{ .width = 609.45, .height = 779.53 },
        };
    }

    /// Returns the landscape dimensions (width and height swapped).
    pub fn landscape(self: PageSize) Dimensions {
        const d = self.dimensions();
        return .{ .width = d.height, .height = d.width };
    }

    /// Creates custom dimensions from arbitrary width and height values in points.
    pub fn custom(width: f32, height: f32) Dimensions {
        return .{ .width = width, .height = height };
    }
};

// -- Tests --

test "a4 dimensions" {
    const d = PageSize.a4.dimensions();
    try std.testing.expectApproxEqAbs(@as(f32, 595.28), d.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 841.89), d.height, 0.01);
}

test "letter dimensions" {
    const d = PageSize.letter.dimensions();
    try std.testing.expectApproxEqAbs(@as(f32, 612.0), d.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 792.0), d.height, 0.01);
}

test "landscape swaps width and height" {
    const d = PageSize.a4.landscape();
    try std.testing.expectApproxEqAbs(@as(f32, 841.89), d.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 595.28), d.height, 0.01);
}

test "custom dimensions" {
    const d = PageSize.custom(100.0, 200.0);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), d.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), d.height, 0.01);
}
