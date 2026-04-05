//! Demonstrates loading and embedding a per-object ICC color profile as a
//! PDF `ICCBased` color space into a low-level object store.
//!
//! This example does not touch the high-level `Document` API — it works
//! directly with the object store so you can see exactly what the ICC
//! profile support produces.

const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Use the built-in sRGB profile that ships with zpdf.
    const srgb = zpdf.SRGB_ICC_PROFILE;
    std.debug.print(
        "Loaded sRGB profile: {d} bytes, {d} components, space={s}\n",
        .{
            srgb.data.len,
            srgb.num_components,
            @tagName(srgb.color_space),
        },
    );

    // 2. Parse an ICC profile buffer ourselves. This also accepts CMYK and
    //    grayscale profiles; here we reuse the bundled sRGB bytes.
    const parsed = try zpdf.loadIccProfile(srgb.data);
    std.debug.print(
        "Parsed profile header: space={s}, components={d}\n",
        .{ @tagName(parsed.color_space), parsed.num_components },
    );

    // 3. Embed the profile into an object store as an ICCBased color space.
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const cs_ref = try zpdf.embedIccProfile(allocator, &store, srgb);
    std.debug.print(
        "Embedded ICCBased color space as object {d} {d} R (store now holds {d} objects)\n",
        .{ cs_ref.obj_num, cs_ref.gen_num, store.count() },
    );
}
