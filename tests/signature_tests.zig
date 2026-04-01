const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const Sha256 = zpdf.Sha256;
const prepareForSigning = zpdf.security.signature.prepareForSigning;
const applySignature = zpdf.security.signature.applySignature;
const verifySignatureStructure = zpdf.security.signature.verifySignatureStructure;
const pkcs7 = zpdf.security.pkcs7;

// ── SHA-256 tests ───────────────────────────────────────────────────

test "SHA-256: empty string" {
    const result = Sha256.hash("");
    const expected = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try testing.expectEqualSlices(u8, &expected, &result);
}

test "SHA-256: abc" {
    const result = Sha256.hash("abc");
    const expected = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    try testing.expectEqualSlices(u8, &expected, &result);
}

test "SHA-256: incremental matches oneshot" {
    var h = Sha256.init();
    h.update("hello ");
    h.update("world");
    const incremental = h.final();
    const oneshot = Sha256.hash("hello world");
    try testing.expectEqualSlices(u8, &oneshot, &incremental);
}

test "SHA-256: NIST two-block message" {
    const result = Sha256.hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    const expected = [_]u8{
        0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
        0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
        0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
        0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1,
    };
    try testing.expectEqualSlices(u8, &expected, &result);
}

// ── DER encoding tests ──────────────────────────────────────────────

test "DER: length short form" {
    const allocator = testing.allocator;
    const len = try pkcs7.derLength(allocator, 10);
    defer allocator.free(len);
    try testing.expectEqual(@as(usize, 1), len.len);
    try testing.expectEqual(@as(u8, 10), len[0]);
}

test "DER: length long form" {
    const allocator = testing.allocator;
    const len = try pkcs7.derLength(allocator, 256);
    defer allocator.free(len);
    try testing.expectEqual(@as(usize, 3), len.len);
    try testing.expectEqual(@as(u8, 0x82), len[0]);
    try testing.expectEqual(@as(u8, 0x01), len[1]);
    try testing.expectEqual(@as(u8, 0x00), len[2]);
}

test "DER: SEQUENCE wraps content with tag 0x30" {
    const allocator = testing.allocator;
    const content = [_]u8{ 0x01, 0x02, 0x03 };
    const seq = try pkcs7.derSequence(allocator, &content);
    defer allocator.free(seq);
    try testing.expectEqual(@as(u8, 0x30), seq[0]);
    try testing.expectEqual(@as(u8, 3), seq[1]);
    try testing.expectEqualSlices(u8, &content, seq[2..]);
}

test "DER: SET wraps content with tag 0x31" {
    const allocator = testing.allocator;
    const content = [_]u8{0xFF};
    const s = try pkcs7.derSet(allocator, &content);
    defer allocator.free(s);
    try testing.expectEqual(@as(u8, 0x31), s[0]);
}

test "DER: OID encoding" {
    const allocator = testing.allocator;
    const oid_bytes = [_]u8{ 0x2a, 0x86, 0x48 };
    const oid = try pkcs7.derOid(allocator, &oid_bytes);
    defer allocator.free(oid);
    try testing.expectEqual(@as(u8, 0x06), oid[0]);
    try testing.expectEqual(@as(u8, 3), oid[1]);
}

test "DER: INTEGER small values" {
    const allocator = testing.allocator;
    const zero = try pkcs7.derInteger(allocator, 0);
    defer allocator.free(zero);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x02, 0x01, 0x00 }, zero);

    const one = try pkcs7.derInteger(allocator, 1);
    defer allocator.free(one);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x02, 0x01, 0x01 }, one);
}

test "DER: OCTET STRING" {
    const allocator = testing.allocator;
    const data = [_]u8{ 0xCA, 0xFE };
    const os = try pkcs7.derOctetString(allocator, &data);
    defer allocator.free(os);
    try testing.expectEqual(@as(u8, 0x04), os[0]);
    try testing.expectEqual(@as(u8, 2), os[1]);
    try testing.expectEqualSlices(u8, &data, os[2..]);
}

test "DER: EXPLICIT context tag" {
    const allocator = testing.allocator;
    const content = [_]u8{0x42};
    const e = try pkcs7.derExplicit(allocator, 0, &content);
    defer allocator.free(e);
    try testing.expectEqual(@as(u8, 0xA0), e[0]);
    try testing.expectEqual(@as(u8, 1), e[1]);
}

// ── PKCS#7 structure tests ──────────────────────────────────────────

test "PKCS#7: builds valid DER structure" {
    const allocator = testing.allocator;

    // Minimal self-signed certificate (fabricated but structurally valid DER)
    // This is a minimal X.509 structure:
    // SEQUENCE {
    //   SEQUENCE {                    -- tbsCertificate
    //     [0] EXPLICIT INTEGER 2      -- version v3
    //     INTEGER 1                   -- serialNumber
    //     SEQUENCE { OID, NULL }      -- signature algorithm
    //     SEQUENCE {                  -- issuer
    //       SET { SEQUENCE { OID cn, UTF8STRING "Test" } }
    //     }
    //   }
    //   ...
    // }
    // Manually constructed minimal X.509-like DER with correct lengths:
    // UTF8STRING "Test" = 0x0C 0x04 "Test" (6 bytes)
    // OID cn (2.5.4.3) = 0x06 0x03 0x55 0x04 0x03 (5 bytes)
    // SEQUENCE { OID, UTF8STRING } = 0x30 0x0B ... (13 bytes)
    // SET { SEQUENCE } = 0x31 0x0D ... (15 bytes)
    // issuer SEQUENCE = 0x30 0x0F ... (17 bytes)
    // sig alg SEQUENCE = 0x30 0x0D ... (15 bytes)
    // serial INTEGER 1 = 0x02 0x01 0x01 (3 bytes)
    // version [0] = 0xA0 0x03 0x02 0x01 0x02 (5 bytes)
    // tbsCert content = 5 + 3 + 15 + 17 = 40 bytes
    // tbsCert SEQUENCE = 0x30 0x28 ... (42 bytes)
    // outer SEQUENCE = 0x30 0x2A ... (44 bytes)
    const fake_cert = [_]u8{
        0x30, 0x2A, // SEQUENCE (outer, 42 bytes content)
        0x30, 0x28, // SEQUENCE (tbsCertificate, 40 bytes)
        0xA0, 0x03, 0x02, 0x01, 0x02, // [0] EXPLICIT INTEGER 2
        0x02, 0x01, 0x01, // INTEGER 1 (serial)
        0x30, 0x0D, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00, // sig alg (15 bytes)
        0x30, 0x0F, // SEQUENCE (issuer, 15 bytes)
        0x31, 0x0D, 0x30, 0x0B, // SET { SEQUENCE (11 bytes)
        0x06, 0x03, 0x55, 0x04, 0x03, // OID cn (5 bytes)
        0x0C, 0x04, 0x54, 0x65, 0x73, 0x74, // UTF8STRING "Test" (6 bytes)
    };

    const digest = Sha256.hash("test data");
    const fake_signature = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 };

    const pkcs7_der = try pkcs7.buildPkcs7SignedData(
        allocator,
        digest,
        &fake_signature,
        &fake_cert,
    );
    defer allocator.free(pkcs7_der);

    // Verify it starts with SEQUENCE
    try testing.expectEqual(@as(u8, 0x30), pkcs7_der[0]);

    // Verify it contains the signedData OID (1.2.840.113549.1.7.2)
    const sd_oid = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02 };
    try testing.expect(containsSubslice(pkcs7_der, &sd_oid));

    // Verify it contains the sha256 OID
    const sha256_oid = [_]u8{ 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01 };
    try testing.expect(containsSubslice(pkcs7_der, &sha256_oid));

    // Verify it contains the signature bytes
    try testing.expect(containsSubslice(pkcs7_der, &fake_signature));
}

// ── Signature preparation tests ─────────────────────────────────────

test "prepareForSigning: creates valid ByteRange" {
    const allocator = testing.allocator;

    const minimal_pdf =
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

    var prepared = try prepareForSigning(allocator, minimal_pdf, .{
        .signature_size = 1024,
    });
    defer prepared.deinit();

    // ByteRange[0] must be 0
    try testing.expectEqual(@as(u64, 0), prepared.byte_range[0]);

    // Second segment must start after first segment
    try testing.expect(prepared.byte_range[2] > prepared.byte_range[1]);

    // The two segments plus the gap must equal total file size
    const gap = prepared.byte_range[2] - prepared.byte_range[1];
    const total = prepared.byte_range[1] + gap + prepared.byte_range[3];
    try testing.expectEqual(@as(u64, @intCast(prepared.pdf_bytes.len)), total);
}

test "prepareForSigning: ByteRange covers all bytes except Contents" {
    const allocator = testing.allocator;

    const minimal_pdf =
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

    var prepared = try prepareForSigning(allocator, minimal_pdf, .{
        .signature_size = 512,
    });
    defer prepared.deinit();

    // The excluded region should contain the hex Contents value
    const excl_start = prepared.byte_range[1];
    const excl_end = prepared.byte_range[2];
    const excluded = prepared.pdf_bytes[excl_start..excl_end];

    // It should start with '<' and end with '>'
    try testing.expectEqual(@as(u8, '<'), excluded[0]);
    try testing.expectEqual(@as(u8, '>'), excluded[excluded.len - 1]);
}

test "signature structure verification: round-trip" {
    const allocator = testing.allocator;

    const minimal_pdf =
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

    var prepared = try prepareForSigning(allocator, minimal_pdf, .{
        .appearance = .{
            .name = "John Doe",
            .reason = "Document Review",
            .location = "New York",
        },
        .signature_size = 256,
    });
    defer prepared.deinit();

    const verification = try verifySignatureStructure(prepared.pdf_bytes);
    try testing.expect(verification.has_signature);
    try testing.expect(verification.byte_range_valid);
    try testing.expectEqualSlices(u8, "John Doe", verification.signer_name.?);
    try testing.expectEqualSlices(u8, "Document Review", verification.reason.?);
}

// ── Helpers ─────────────────────────────────────────────────────────

fn containsSubslice(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}
