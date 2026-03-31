const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Well-known OIDs (DER-encoded value bytes, without tag+length) ───

/// 1.2.840.113549.1.7.2 (signedData)
const OID_SIGNED_DATA = &[_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02 };

/// 1.2.840.113549.1.7.1 (data)
const OID_DATA = &[_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01 };

/// 2.16.840.1.101.3.4.2.1 (sha-256)
const OID_SHA256 = &[_]u8{ 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01 };

/// 1.2.840.113549.1.1.1 (rsaEncryption)
const OID_RSA_ENCRYPTION = &[_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01 };

// ── ASN.1 DER encoding helpers ──────────────────────────────────────

/// Encode a DER length field.
pub fn derLength(allocator: Allocator, length: usize) ![]u8 {
    if (length < 0x80) {
        const buf = try allocator.alloc(u8, 1);
        buf[0] = @truncate(length);
        return buf;
    } else if (length <= 0xFF) {
        const buf = try allocator.alloc(u8, 2);
        buf[0] = 0x81;
        buf[1] = @truncate(length);
        return buf;
    } else if (length <= 0xFFFF) {
        const buf = try allocator.alloc(u8, 3);
        buf[0] = 0x82;
        buf[1] = @truncate(length >> 8);
        buf[2] = @truncate(length);
        return buf;
    } else if (length <= 0xFFFFFF) {
        const buf = try allocator.alloc(u8, 4);
        buf[0] = 0x83;
        buf[1] = @truncate(length >> 16);
        buf[2] = @truncate(length >> 8);
        buf[3] = @truncate(length);
        return buf;
    } else {
        const buf = try allocator.alloc(u8, 5);
        buf[0] = 0x84;
        buf[1] = @truncate(length >> 24);
        buf[2] = @truncate(length >> 16);
        buf[3] = @truncate(length >> 8);
        buf[4] = @truncate(length);
        return buf;
    }
}

/// Wrap contents with a tag and DER length.
fn derTagged(allocator: Allocator, tag: u8, contents: []const u8) ![]u8 {
    const len_bytes = try derLength(allocator, contents.len);
    defer allocator.free(len_bytes);

    const total = 1 + len_bytes.len + contents.len;
    const buf = try allocator.alloc(u8, total);
    buf[0] = tag;
    @memcpy(buf[1 .. 1 + len_bytes.len], len_bytes);
    @memcpy(buf[1 + len_bytes.len ..], contents);
    return buf;
}

/// SEQUENCE (tag 0x30)
pub fn derSequence(allocator: Allocator, contents: []const u8) ![]u8 {
    return derTagged(allocator, 0x30, contents);
}

/// SET (tag 0x31)
pub fn derSet(allocator: Allocator, contents: []const u8) ![]u8 {
    return derTagged(allocator, 0x31, contents);
}

/// OID (tag 0x06)
pub fn derOid(allocator: Allocator, oid_value: []const u8) ![]u8 {
    return derTagged(allocator, 0x06, oid_value);
}

/// OCTET STRING (tag 0x04)
pub fn derOctetString(allocator: Allocator, data: []const u8) ![]u8 {
    return derTagged(allocator, 0x04, data);
}

/// INTEGER (tag 0x02) for small non-negative values.
pub fn derInteger(allocator: Allocator, value: i64) ![]u8 {
    if (value >= 0 and value < 0x80) {
        const buf = try allocator.alloc(u8, 3);
        buf[0] = 0x02;
        buf[1] = 0x01;
        buf[2] = @truncate(@as(u64, @intCast(value)));
        return buf;
    }
    // Encode as variable-length big-endian
    const uval: u64 = @bitCast(value);
    var byte_count: usize = 8;
    while (byte_count > 1) : (byte_count -= 1) {
        const top_byte: u8 = @truncate(uval >> @intCast((byte_count - 1) * 8));
        const next_byte: u8 = @truncate(uval >> @intCast((byte_count - 2) * 8));
        if (top_byte == 0 and next_byte < 0x80) continue;
        if (top_byte == 0xFF and next_byte >= 0x80) continue;
        break;
    }

    const len_bytes = try derLength(allocator, byte_count);
    defer allocator.free(len_bytes);
    const buf = try allocator.alloc(u8, 1 + len_bytes.len + byte_count);
    buf[0] = 0x02;
    @memcpy(buf[1 .. 1 + len_bytes.len], len_bytes);
    for (0..byte_count) |i| {
        buf[1 + len_bytes.len + i] = @truncate(uval >> @intCast((byte_count - 1 - i) * 8));
    }
    return buf;
}

/// INTEGER from raw big-endian bytes (for serial numbers, etc.)
pub fn derIntegerBytes(allocator: Allocator, bytes: []const u8) ![]u8 {
    // If high bit is set, prepend a zero byte
    const needs_pad = bytes.len > 0 and bytes[0] >= 0x80;
    const content_len = bytes.len + @as(usize, if (needs_pad) 1 else 0);
    const len_enc = try derLength(allocator, content_len);
    defer allocator.free(len_enc);

    const buf = try allocator.alloc(u8, 1 + len_enc.len + content_len);
    buf[0] = 0x02;
    @memcpy(buf[1 .. 1 + len_enc.len], len_enc);
    var offset: usize = 1 + len_enc.len;
    if (needs_pad) {
        buf[offset] = 0x00;
        offset += 1;
    }
    @memcpy(buf[offset .. offset + bytes.len], bytes);
    return buf;
}

/// EXPLICIT context tag [tag] CONSTRUCTED
pub fn derExplicit(allocator: Allocator, tag: u8, contents: []const u8) ![]u8 {
    return derTagged(allocator, 0xA0 | tag, contents);
}

/// IMPLICIT context tag [tag] CONSTRUCTED
pub fn derImplicit(allocator: Allocator, tag: u8, contents: []const u8) ![]u8 {
    return derTagged(allocator, 0xA0 | tag, contents);
}

/// NULL (tag 0x05, length 0)
pub fn derNull(allocator: Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, 2);
    buf[0] = 0x05;
    buf[1] = 0x00;
    return buf;
}

/// Concatenate multiple DER-encoded fragments.
fn derConcat(allocator: Allocator, parts: []const []const u8) ![]u8 {
    var total: usize = 0;
    for (parts) |p| total += p.len;
    const buf = try allocator.alloc(u8, total);
    var offset: usize = 0;
    for (parts) |p| {
        @memcpy(buf[offset .. offset + p.len], p);
        offset += p.len;
    }
    return buf;
}

// ── Minimal X.509 certificate parsing ───────────────────────────────

/// Extract issuer and serial number from a DER-encoded X.509 certificate.
/// Returns the raw DER bytes for each.
const IssuerAndSerial = struct {
    issuer: []const u8,
    serial: []const u8,
};

fn parseCertIssuerAndSerial(cert_der: []const u8) !IssuerAndSerial {
    // Certificate ::= SEQUENCE { tbsCertificate, ... }
    // tbsCertificate ::= SEQUENCE { version [0] EXPLICIT, serialNumber, signature, issuer, ... }
    var pos: usize = 0;

    // Outer SEQUENCE
    if (cert_der[pos] != 0x30) return error.InvalidCertificate;
    pos += 1;
    _ = try skipLength(cert_der, &pos);

    // tbsCertificate SEQUENCE
    if (cert_der[pos] != 0x30) return error.InvalidCertificate;
    pos += 1;
    _ = try skipLength(cert_der, &pos);

    // version [0] EXPLICIT (optional)
    if (pos < cert_der.len and cert_der[pos] == 0xA0) {
        pos += 1;
        const vlen = try readLength(cert_der, &pos);
        pos += vlen;
    }

    // serialNumber INTEGER
    if (cert_der[pos] != 0x02) return error.InvalidCertificate;
    const serial_start = pos;
    pos += 1;
    const serial_content_len = try readLength(cert_der, &pos);
    const serial_bytes = cert_der[pos .. pos + serial_content_len];
    _ = serial_start;
    pos += serial_content_len;

    // signature AlgorithmIdentifier SEQUENCE (skip)
    if (cert_der[pos] != 0x30) return error.InvalidCertificate;
    pos += 1;
    const sig_len = try readLength(cert_der, &pos);
    pos += sig_len;

    // issuer Name SEQUENCE
    if (cert_der[pos] != 0x30) return error.InvalidCertificate;
    const issuer_start = pos;
    pos += 1;
    const issuer_content_len = try readLength(cert_der, &pos);
    const issuer_total = pos + issuer_content_len - issuer_start;
    const issuer_bytes = cert_der[issuer_start .. issuer_start + issuer_total];
    // pos += issuer_content_len; -- not needed

    return .{
        .issuer = issuer_bytes,
        .serial = serial_bytes,
    };
}

fn readLength(data: []const u8, pos: *usize) !usize {
    if (pos.* >= data.len) return error.InvalidAsn1;
    const first = data[pos.*];
    pos.* += 1;
    if (first < 0x80) return first;
    const num_bytes = first & 0x7F;
    if (num_bytes > 4) return error.InvalidAsn1;
    var length: usize = 0;
    for (0..num_bytes) |_| {
        if (pos.* >= data.len) return error.InvalidAsn1;
        length = (length << 8) | data[pos.*];
        pos.* += 1;
    }
    return length;
}

fn skipLength(data: []const u8, pos: *usize) !usize {
    return readLength(data, pos);
}

// ── PKCS#7 SignedData builder ───────────────────────────────────────

/// Build a PKCS#7 (CMS) SignedData container in DER format.
///
/// Parameters:
///   - digest: SHA-256 hash of the signed content
///   - signature_value: raw signature bytes (e.g., RSA signature)
///   - certificate_der: DER-encoded X.509 signing certificate
///
/// Returns DER-encoded ContentInfo wrapping SignedData.
pub fn buildPkcs7SignedData(
    allocator: Allocator,
    digest: [32]u8,
    signature_value: []const u8,
    certificate_der: []const u8,
) ![]u8 {
    // We accumulate temporary allocations and free them at the end.
    var temps: std.ArrayListUnmanaged([]u8) = .{};
    defer {
        for (temps.items) |t| allocator.free(t);
        temps.deinit(allocator);
    }

    // Helper to track a temporary allocation
    const track = struct {
        fn f(list: *std.ArrayListUnmanaged([]u8), alloc: Allocator, buf: []u8) ![]const u8 {
            try list.append(alloc, buf);
            return buf;
        }
    }.f;

    // -- digestAlgorithms SET { SEQUENCE { sha256, NULL } }
    const sha256_oid = try track(&temps, allocator, try derOid(allocator, OID_SHA256));
    const null_val = try track(&temps, allocator, try derNull(allocator));
    const sha256_alg_parts = [_][]const u8{ sha256_oid, null_val };
    const sha256_alg_content = try track(&temps, allocator, try derConcat(allocator, &sha256_alg_parts));
    const sha256_alg_seq = try track(&temps, allocator, try derSequence(allocator, sha256_alg_content));
    const digest_algorithms = try track(&temps, allocator, try derSet(allocator, sha256_alg_seq));

    // -- encapContentInfo SEQUENCE { OID data }
    const data_oid = try track(&temps, allocator, try derOid(allocator, OID_DATA));
    const encap_content_info = try track(&temps, allocator, try derSequence(allocator, data_oid));

    // -- certificates [0] IMPLICIT
    const certificates = try track(&temps, allocator, try derImplicit(allocator, 0, certificate_der));

    // -- signerInfos
    const version_1 = try track(&temps, allocator, try derInteger(allocator, 1));

    // issuerAndSerialNumber
    const cert_info = try parseCertIssuerAndSerial(certificate_der);
    const issuer_der = cert_info.issuer; // points into certificate_der, no free needed
    const serial_der = try track(&temps, allocator, try derIntegerBytes(allocator, cert_info.serial));
    const issuer_serial_parts = [_][]const u8{ issuer_der, serial_der };
    const issuer_serial_content = try track(&temps, allocator, try derConcat(allocator, &issuer_serial_parts));
    const issuer_serial = try track(&temps, allocator, try derSequence(allocator, issuer_serial_content));

    // digestAlgorithm
    const signer_digest_alg = try track(&temps, allocator, try derSequence(allocator, sha256_alg_content));

    // signatureAlgorithm
    const rsa_oid = try track(&temps, allocator, try derOid(allocator, OID_RSA_ENCRYPTION));
    const rsa_null = try track(&temps, allocator, try derNull(allocator));
    const rsa_alg_parts = [_][]const u8{ rsa_oid, rsa_null };
    const rsa_alg_content = try track(&temps, allocator, try derConcat(allocator, &rsa_alg_parts));
    const sig_algorithm = try track(&temps, allocator, try derSequence(allocator, rsa_alg_content));

    // signature OCTET STRING
    const sig_value = try track(&temps, allocator, try derOctetString(allocator, signature_value));

    // SignerInfo SEQUENCE
    _ = digest; // digest is embedded in the signature value already
    const signer_info_parts = [_][]const u8{
        version_1, issuer_serial, signer_digest_alg, sig_algorithm, sig_value,
    };
    const signer_info_content = try track(&temps, allocator, try derConcat(allocator, &signer_info_parts));
    const signer_info = try track(&temps, allocator, try derSequence(allocator, signer_info_content));
    const signer_infos = try track(&temps, allocator, try derSet(allocator, signer_info));

    // -- SignedData SEQUENCE
    const sd_parts = [_][]const u8{
        version_1, digest_algorithms, encap_content_info, certificates, signer_infos,
    };
    const sd_content = try track(&temps, allocator, try derConcat(allocator, &sd_parts));
    const signed_data = try track(&temps, allocator, try derSequence(allocator, sd_content));

    // -- ContentInfo SEQUENCE { OID signedData, [0] EXPLICIT SignedData }
    const sd_oid = try track(&temps, allocator, try derOid(allocator, OID_SIGNED_DATA));
    const explicit_sd = try track(&temps, allocator, try derExplicit(allocator, 0, signed_data));
    const ci_parts = [_][]const u8{ sd_oid, explicit_sd };
    const ci_content = try track(&temps, allocator, try derConcat(allocator, &ci_parts));

    // The final result - this one we return, not tracked
    return derSequence(allocator, ci_content);
}

// ── Tests ───────────────────────────────────────────────────────────

test "derLength: short form" {
    const allocator = std.testing.allocator;
    const len = try derLength(allocator, 5);
    defer allocator.free(len);
    try std.testing.expectEqual(@as(usize, 1), len.len);
    try std.testing.expectEqual(@as(u8, 5), len[0]);
}

test "derLength: long form 1 byte" {
    const allocator = std.testing.allocator;
    const len = try derLength(allocator, 200);
    defer allocator.free(len);
    try std.testing.expectEqual(@as(usize, 2), len.len);
    try std.testing.expectEqual(@as(u8, 0x81), len[0]);
    try std.testing.expectEqual(@as(u8, 200), len[1]);
}

test "derLength: long form 2 bytes" {
    const allocator = std.testing.allocator;
    const len = try derLength(allocator, 300);
    defer allocator.free(len);
    try std.testing.expectEqual(@as(usize, 3), len.len);
    try std.testing.expectEqual(@as(u8, 0x82), len[0]);
    try std.testing.expectEqual(@as(u8, 0x01), len[1]);
    try std.testing.expectEqual(@as(u8, 0x2C), len[2]);
}

test "derSequence: wraps content" {
    const allocator = std.testing.allocator;
    const content = [_]u8{ 0x01, 0x02 };
    const seq = try derSequence(allocator, &content);
    defer allocator.free(seq);
    try std.testing.expectEqual(@as(u8, 0x30), seq[0]);
    try std.testing.expectEqual(@as(u8, 0x02), seq[1]);
    try std.testing.expectEqual(@as(u8, 0x01), seq[2]);
    try std.testing.expectEqual(@as(u8, 0x02), seq[3]);
}

test "derSet: wraps content" {
    const allocator = std.testing.allocator;
    const content = [_]u8{0xAA};
    const s = try derSet(allocator, &content);
    defer allocator.free(s);
    try std.testing.expectEqual(@as(u8, 0x31), s[0]);
    try std.testing.expectEqual(@as(u8, 0x01), s[1]);
    try std.testing.expectEqual(@as(u8, 0xAA), s[2]);
}

test "derOid: encodes oid" {
    const allocator = std.testing.allocator;
    const oid = try derOid(allocator, OID_SHA256);
    defer allocator.free(oid);
    try std.testing.expectEqual(@as(u8, 0x06), oid[0]);
    try std.testing.expectEqual(@as(u8, OID_SHA256.len), oid[1]);
}

test "derInteger: small value" {
    const allocator = std.testing.allocator;
    const i = try derInteger(allocator, 1);
    defer allocator.free(i);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x02, 0x01, 0x01 }, i);
}

test "derInteger: zero" {
    const allocator = std.testing.allocator;
    const i = try derInteger(allocator, 0);
    defer allocator.free(i);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x02, 0x01, 0x00 }, i);
}

test "derOctetString: encodes data" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 0xDE, 0xAD };
    const os = try derOctetString(allocator, &data);
    defer allocator.free(os);
    try std.testing.expectEqual(@as(u8, 0x04), os[0]);
    try std.testing.expectEqual(@as(u8, 0x02), os[1]);
    try std.testing.expectEqual(@as(u8, 0xDE), os[2]);
    try std.testing.expectEqual(@as(u8, 0xAD), os[3]);
}

test "derExplicit: context tag 0" {
    const allocator = std.testing.allocator;
    const content = [_]u8{0x55};
    const e = try derExplicit(allocator, 0, &content);
    defer allocator.free(e);
    try std.testing.expectEqual(@as(u8, 0xA0), e[0]);
    try std.testing.expectEqual(@as(u8, 0x01), e[1]);
    try std.testing.expectEqual(@as(u8, 0x55), e[2]);
}
