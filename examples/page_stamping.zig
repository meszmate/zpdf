const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const stampPdf = zpdf.modify.stamper.stampPdf;
    const StampOptions = zpdf.modify.stamper.StampOptions;
    const color = zpdf.color;

    // ── Create the base document ─────────────────────────────────────
    {
        var doc = Document.init(allocator);
        defer doc.deinit();

        doc.setTitle("Base Document");
        const page = try doc.addPage(PageSize.letter);

        const helv = try doc.getStandardFont(.helvetica_bold);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);
        const helv_reg = try doc.getStandardFont(.helvetica);
        _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

        try page.drawText("Annual Report 2026", .{
            .x = 72,
            .y = 720,
            .font = .helvetica_bold,
            .font_size = 24,
            .color = color.rgb(0, 0, 0),
        });
        try page.drawText("This document contains important financial data.", .{
            .x = 72,
            .y = 690,
            .font = .helvetica,
            .font_size = 12,
        });

        const base_bytes = try doc.save(allocator);
        defer allocator.free(base_bytes);

        // ── Create the stamp document ────────────────────────────────
        var stamp_doc = Document.init(allocator);
        defer stamp_doc.deinit();

        const stamp_page = try stamp_doc.addPage(PageSize.letter);
        const stamp_font = try stamp_doc.getStandardFont(.helvetica_bold);
        _ = try stamp_page.addFont(stamp_font.font.pdfName(), stamp_font.ref);

        try stamp_page.drawText("CONFIDENTIAL", .{
            .x = 150,
            .y = 400,
            .font = .helvetica_bold,
            .font_size = 60,
            .color = color.rgb(255, 0, 0),
        });

        const stamp_bytes = try stamp_doc.save(allocator);
        defer allocator.free(stamp_bytes);

        // ── Foreground stamp ─────────────────────────────────────────
        const fg_result = try stampPdf(allocator, base_bytes, stamp_bytes, StampOptions{
            .position = .foreground,
        });
        defer allocator.free(fg_result);

        const fg_file = try std.fs.cwd().createFile("stamped_foreground.pdf", .{});
        defer fg_file.close();
        try fg_file.writeAll(fg_result);
        std.debug.print("Created stamped_foreground.pdf ({d} bytes)\n", .{fg_result.len});

        // ── Background stamp ─────────────────────────────────────────
        const bg_result = try stampPdf(allocator, base_bytes, stamp_bytes, StampOptions{
            .position = .background,
        });
        defer allocator.free(bg_result);

        const bg_file = try std.fs.cwd().createFile("stamped_background.pdf", .{});
        defer bg_file.close();
        try bg_file.writeAll(bg_result);
        std.debug.print("Created stamped_background.pdf ({d} bytes)\n", .{bg_result.len});
    }
}
