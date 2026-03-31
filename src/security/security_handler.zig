const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const md5_mod = @import("md5.zig");
const rc4_mod = @import("rc4.zig");
const aes_mod = @import("aes.zig");

/// Encryption algorithm selection.
pub const Algorithm = enum {
    rc4_40,
    rc4_128,
    aes_128,
    aes_256,

    /// Returns the key length in bytes for this algorithm.
    pub fn keyLength(self: Algorithm) usize {
        return switch (self) {
            .rc4_40 => 5,
            .rc4_128 => 16,
            .aes_128 => 16,
            .aes_256 => 32,
        };
    }

    /// Returns the PDF /V value for this algorithm.
    pub fn vValue(self: Algorithm) i64 {
        return switch (self) {
            .rc4_40 => 1,
            .rc4_128 => 2,
            .aes_128 => 4,
            .aes_256 => 5,
        };
    }

    /// Returns the PDF /R value (revision) for this algorithm.
    pub fn rValue(self: Algorithm) i64 {
        return switch (self) {
            .rc4_40 => 2,
            .rc4_128 => 3,
            .aes_128 => 4,
            .aes_256 => 6,
        };
    }
};

/// PDF document permissions (maps to the /P value in the encrypt dict).
pub const Permissions = packed struct {
    printing: bool = true,
    modifying: bool = true,
    copying: bool = true,
    annotating: bool = true,
    filling_forms: bool = true,
    content_accessibility: bool = true,
    document_assembly: bool = true,
    high_quality_printing: bool = true,

    /// Encode permissions into the 32-bit /P value per PDF spec.
    pub fn toInt(self: Permissions) i32 {
        // Bits 1-2 must be 0, bits 7-8 reserved (must be 1 for rev 2).
        // Bit 3: print, Bit 4: modify, Bit 5: copy, Bit 6: annotate
        // Bit 9: fill forms, Bit 10: extract for accessibility
        // Bit 11: assemble, Bit 12: high-quality print
        var p: i32 = -3904; // All upper bits set, bits 1-2 clear, bits 7-8 set
        if (self.printing) p |= (1 << 2);
        if (self.modifying) p |= (1 << 3);
        if (self.copying) p |= (1 << 4);
        if (self.annotating) p |= (1 << 5);
        if (self.filling_forms) p |= (1 << 8);
        if (self.content_accessibility) p |= (1 << 9);
        if (self.document_assembly) p |= (1 << 10);
        if (self.high_quality_printing) p |= (1 << 11);
        return p;
    }
};

/// Options for initializing encryption.
pub const EncryptionOptions = struct {
    owner_password: []const u8 = "",
    user_password: []const u8 = "",
    algorithm: Algorithm = .aes_128,
    permissions: Permissions = .{},
};

/// PDF padding string (32 bytes, per PDF spec).
const pdf_padding = [_]u8{
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
};

/// Handles PDF document encryption: key computation, stream encryption,
/// and building the /Encrypt dictionary.
pub const SecurityHandler = struct {
    algorithm: Algorithm,
    owner_password_hash: [32]u8,
    user_password_hash: [32]u8,
    encryption_key: [32]u8,
    key_length: usize,
    permissions: Permissions,

    /// Initialize a security handler from the given options.
    /// Computes owner/user password hashes and the encryption key.
    pub fn init(options: EncryptionOptions) SecurityHandler {
        var handler = SecurityHandler{
            .algorithm = options.algorithm,
            .owner_password_hash = undefined,
            .user_password_hash = undefined,
            .encryption_key = undefined,
            .key_length = options.algorithm.keyLength(),
            .permissions = options.permissions,
        };

        handler.computeOwnerPasswordHash(options.owner_password, options.user_password);
        handler.computeEncryptionKey(options.user_password);
        handler.computeUserPasswordHash();

        return handler;
    }

    /// Pad or truncate a password to exactly 32 bytes using the PDF padding string.
    fn padPassword(password: []const u8) [32]u8 {
        var result: [32]u8 = pdf_padding;
        const copy_len = @min(password.len, 32);
        @memcpy(result[0..copy_len], password[0..copy_len]);
        return result;
    }

    fn computeOwnerPasswordHash(self: *SecurityHandler, owner_pwd: []const u8, user_pwd: []const u8) void {
        // Use owner password if provided, otherwise use user password
        const pwd = if (owner_pwd.len > 0) owner_pwd else user_pwd;
        const padded = padPassword(pwd);

        // MD5 hash of the padded owner password
        var hash = md5_mod.md5(&padded);

        // For revision 3+, hash 50 more times
        if (self.algorithm.rValue() >= 3) {
            for (0..50) |_| {
                hash = md5_mod.md5(hash[0..self.key_length]);
            }
        }

        // Use the hash as a key to RC4-encrypt the padded user password
        const user_padded = padPassword(user_pwd);
        var encrypted: [32]u8 = undefined;
        rc4_mod.rc4(hash[0..self.key_length], &user_padded, &encrypted);

        // For revision 3+, iterate 19 times with modified keys
        if (self.algorithm.rValue() >= 3) {
            for (1..20) |i| {
                var modified_key: [32]u8 = undefined;
                for (0..self.key_length) |k| {
                    modified_key[k] = hash[k] ^ @as(u8, @intCast(i));
                }
                var temp: [32]u8 = undefined;
                rc4_mod.rc4(modified_key[0..self.key_length], &encrypted, &temp);
                encrypted = temp;
            }
        }

        self.owner_password_hash = encrypted;
    }

    fn computeEncryptionKey(self: *SecurityHandler, user_pwd: []const u8) void {
        const padded = padPassword(user_pwd);

        // Build the hash input: padded password + O value + P value + file ID
        // For simplicity, use a fixed file ID (in production, this would be the document's /ID)
        var hasher = std.crypto.hash.Md5.init(.{});
        hasher.update(&padded);
        hasher.update(&self.owner_password_hash);

        // Permissions as little-endian 4 bytes
        const p = self.permissions.toInt();
        const p_bytes = std.mem.toBytes(p);
        hasher.update(&p_bytes);

        // File ID (using a fixed placeholder)
        const file_id = [_]u8{0} ** 16;
        hasher.update(&file_id);

        var hash: [16]u8 = undefined;
        hasher.final(&hash);

        // For revision 3+, hash 50 more times
        if (self.algorithm.rValue() >= 3) {
            for (0..50) |_| {
                const temp = md5_mod.md5(hash[0..self.key_length]);
                @memcpy(hash[0..16], &temp);
            }
        }

        @memcpy(self.encryption_key[0..self.key_length], hash[0..self.key_length]);
    }

    fn computeUserPasswordHash(self: *SecurityHandler) void {
        if (self.algorithm.rValue() >= 3) {
            // Hash the padding string with file ID
            var hasher = std.crypto.hash.Md5.init(.{});
            hasher.update(&pdf_padding);
            const file_id = [_]u8{0} ** 16;
            hasher.update(&file_id);
            var hash: [16]u8 = undefined;
            hasher.final(&hash);

            // RC4 encrypt with the encryption key
            var encrypted: [16]u8 = undefined;
            rc4_mod.rc4(self.encryption_key[0..self.key_length], &hash, &encrypted);

            // 19 iterations with modified keys
            for (1..20) |i| {
                var modified_key: [32]u8 = undefined;
                for (0..self.key_length) |k| {
                    modified_key[k] = self.encryption_key[k] ^ @as(u8, @intCast(i));
                }
                var temp: [16]u8 = undefined;
                rc4_mod.rc4(modified_key[0..self.key_length], &encrypted, &temp);
                encrypted = temp;
            }

            // Pad to 32 bytes
            @memcpy(self.user_password_hash[0..16], &encrypted);
            @memset(self.user_password_hash[16..32], 0);
        } else {
            // Revision 2: RC4 encrypt the padding with the key
            rc4_mod.rc4(self.encryption_key[0..self.key_length], &pdf_padding, &self.user_password_hash);
        }
    }

    /// Encrypt a content stream for a specific object.
    /// The per-object key is derived from the encryption key, object number, and generation number.
    pub fn encryptStream(self: *const SecurityHandler, allocator: Allocator, data: []const u8, obj_num: u32, gen_num: u16) ![]u8 {
        // Compute per-object key: MD5(encryption_key + obj_num_bytes + gen_num_bytes)
        var key_input: [32 + 5]u8 = undefined;
        @memcpy(key_input[0..self.key_length], self.encryption_key[0..self.key_length]);

        // Object number as 3 little-endian bytes
        key_input[self.key_length] = @intCast(obj_num & 0xFF);
        key_input[self.key_length + 1] = @intCast((obj_num >> 8) & 0xFF);
        key_input[self.key_length + 2] = @intCast((obj_num >> 16) & 0xFF);

        // Generation number as 2 little-endian bytes
        key_input[self.key_length + 3] = @intCast(gen_num & 0xFF);
        key_input[self.key_length + 4] = @intCast((gen_num >> 8) & 0xFF);

        const obj_key_len = @min(self.key_length + 5, 16);
        const obj_key_hash = md5_mod.md5(key_input[0 .. self.key_length + 5]);
        const obj_key = obj_key_hash[0..obj_key_len];

        switch (self.algorithm) {
            .rc4_40, .rc4_128 => {
                const output = try allocator.alloc(u8, data.len);
                rc4_mod.rc4(obj_key, data, output);
                return output;
            },
            .aes_128 => {
                // Generate random IV
                var iv: [16]u8 = undefined;
                std.crypto.random.bytes(&iv);
                const encrypted = try aes_mod.aesEncryptCbc(allocator, obj_key, iv, data);

                // Prepend IV to output
                const result = try allocator.alloc(u8, 16 + encrypted.len);
                @memcpy(result[0..16], &iv);
                @memcpy(result[16..], encrypted);
                allocator.free(encrypted);
                return result;
            },
            .aes_256 => {
                var iv: [16]u8 = undefined;
                std.crypto.random.bytes(&iv);
                const encrypted = try aes_mod.aesEncryptCbc(allocator, self.encryption_key[0..32], iv, data);

                const result = try allocator.alloc(u8, 16 + encrypted.len);
                @memcpy(result[0..16], &iv);
                @memcpy(result[16..], encrypted);
                allocator.free(encrypted);
                return result;
            },
        }
    }

    /// Build the /Encrypt dictionary as a PdfObject.
    pub fn buildEncryptDict(self: *const SecurityHandler, allocator: Allocator) !PdfObject {
        var dict = types.pdfDict(allocator);
        errdefer dict.deinit(allocator);

        try dict.dict_obj.put(allocator, "Filter", types.pdfName("Standard"));
        try dict.dict_obj.put(allocator, "V", types.pdfInt(self.algorithm.vValue()));
        try dict.dict_obj.put(allocator, "R", types.pdfInt(self.algorithm.rValue()));
        try dict.dict_obj.put(allocator, "Length", types.pdfInt(@as(i64, @intCast(self.key_length * 8))));
        try dict.dict_obj.put(allocator, "P", types.pdfInt(@as(i64, self.permissions.toInt())));
        try dict.dict_obj.put(allocator, "O", types.pdfString(&self.owner_password_hash));
        try dict.dict_obj.put(allocator, "U", types.pdfString(&self.user_password_hash));

        if (self.algorithm == .aes_128 or self.algorithm == .aes_256) {
            var cf_dict = types.pdfDict(allocator);
            var std_cf = types.pdfDict(allocator);
            try std_cf.dict_obj.put(allocator, "CFM", types.pdfName("AESV2"));
            try std_cf.dict_obj.put(allocator, "AuthEvent", types.pdfName("DocOpen"));
            try std_cf.dict_obj.put(allocator, "Length", types.pdfInt(@as(i64, @intCast(self.key_length))));
            try cf_dict.dict_obj.put(allocator, "StdCF", std_cf);
            try dict.dict_obj.put(allocator, "CF", cf_dict);
            try dict.dict_obj.put(allocator, "StmF", types.pdfName("StdCF"));
            try dict.dict_obj.put(allocator, "StrF", types.pdfName("StdCF"));
        }

        return dict;
    }
};

// -- Tests --

test "security handler: init with defaults" {
    const handler = SecurityHandler.init(.{});
    try std.testing.expect(handler.key_length == 16);
    try std.testing.expect(handler.algorithm == .aes_128);
}

test "security handler: rc4_40" {
    const handler = SecurityHandler.init(.{
        .algorithm = .rc4_40,
        .owner_password = "owner",
        .user_password = "user",
    });
    try std.testing.expect(handler.key_length == 5);
}

test "security handler: permissions to int" {
    const perms = Permissions{};
    const p = perms.toInt();
    // With all permissions set, specific bits should be on
    try std.testing.expect(p & (1 << 2) != 0); // printing
    try std.testing.expect(p & (1 << 4) != 0); // copying
}

test "security handler: permissions restricted" {
    const perms = Permissions{
        .printing = false,
        .copying = false,
        .modifying = false,
        .annotating = false,
        .filling_forms = false,
        .content_accessibility = false,
        .document_assembly = false,
        .high_quality_printing = false,
    };
    const p = perms.toInt();
    try std.testing.expect(p & (1 << 2) == 0); // no printing
    try std.testing.expect(p & (1 << 4) == 0); // no copying
}

test "security handler: build encrypt dict" {
    const allocator = std.testing.allocator;
    const handler = SecurityHandler.init(.{ .algorithm = .rc4_128 });
    var dict = try handler.buildEncryptDict(allocator);
    defer dict.deinit(allocator);

    try std.testing.expect(dict.isDict());
}

test "security handler: encrypt stream rc4" {
    const allocator = std.testing.allocator;
    const handler = SecurityHandler.init(.{
        .algorithm = .rc4_128,
        .user_password = "test",
    });
    const data = "Hello, PDF!";
    const encrypted = try handler.encryptStream(allocator, data, 1, 0);
    defer allocator.free(encrypted);

    try std.testing.expect(encrypted.len == data.len);
    try std.testing.expect(!std.mem.eql(u8, data, encrypted));
}
