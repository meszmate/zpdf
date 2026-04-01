const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 1: Create a simple PDF document
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Digitally Signed Document");
    doc.setAuthor("zpdf");

    const page = try doc.addPage(zpdf.PageSize.a4);

    try page.drawText("Digital Signature Demo", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = zpdf.color.rgb(0, 51, 153),
    });

    try page.drawText("This document demonstrates PDF digital signature preparation.", .{
        .x = 72,
        .y = 710,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.color.rgb(0, 0, 0),
    });

    try page.drawText("The signature placeholder is embedded in the PDF structure.", .{
        .x = 72,
        .y = 690,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.color.rgb(0, 0, 0),
    });

    try page.drawText("An external signing service or HSM can then provide the actual", .{
        .x = 72,
        .y = 660,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.color.rgb(80, 80, 80),
    });

    try page.drawText("PKCS#7 signature to complete the signing process.", .{
        .x = 72,
        .y = 640,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.color.rgb(80, 80, 80),
    });

    // Step 2: Save the document to bytes
    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    std.debug.print("Original PDF size: {d} bytes\n", .{pdf_bytes.len});

    // Step 3: Prepare for signing
    var prepared = try zpdf.security.signature.prepareForSigning(allocator, pdf_bytes, .{
        .appearance = .{
            .name = "Alice Smith",
            .reason = "Document Approval",
            .location = "San Francisco, CA",
            .contact_info = "alice@example.com",
        },
        .signature_size = 8192,
    });
    defer prepared.deinit();

    std.debug.print("Prepared PDF size: {d} bytes\n", .{prepared.pdf_bytes.len});
    std.debug.print("ByteRange: [{d}, {d}, {d}, {d}]\n", .{
        prepared.byte_range[0],
        prepared.byte_range[1],
        prepared.byte_range[2],
        prepared.byte_range[3],
    });
    std.debug.print("Signature placeholder offset: {d}\n", .{prepared.signature_offset});
    std.debug.print("Signature max hex length: {d}\n", .{prepared.signature_max_length});

    // Step 4: Compute the digest of the signed bytes
    const signed_parts = prepared.getSignedBytes();
    var hasher = zpdf.Sha256.init();
    hasher.update(signed_parts[0]);
    hasher.update(signed_parts[1]);
    const digest = hasher.final();

    std.debug.print("SHA-256 digest of signed content: ", .{});
    for (digest) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n", .{});

    // Step 5: Verify the signature structure
    const verification = try zpdf.security.signature.verifySignatureStructure(prepared.pdf_bytes);
    std.debug.print("\nSignature structure verification:\n", .{});
    std.debug.print("  Has signature: {}\n", .{verification.has_signature});
    std.debug.print("  ByteRange valid: {}\n", .{verification.byte_range_valid});
    if (verification.signer_name) |name| {
        std.debug.print("  Signer: {s}\n", .{name});
    }
    if (verification.reason) |reason| {
        std.debug.print("  Reason: {s}\n", .{reason});
    }
    if (verification.sign_date) |date| {
        std.debug.print("  Date: {s}\n", .{date});
    }

    // Note: To complete the signing, you would:
    // 1. Send the digest to a signing service or use a private key
    // 2. Build PKCS#7 with zpdf.security.pkcs7.buildPkcs7SignedData()
    // 3. Call zpdf.security.signature.applySignature() with the PKCS#7 DER bytes
    // 4. Write the prepared.pdf_bytes to a file

    std.debug.print("\nTo complete signing, provide the digest to an external signer\n", .{});
    std.debug.print("and call applySignature() with the resulting PKCS#7 DER bytes.\n", .{});
}
