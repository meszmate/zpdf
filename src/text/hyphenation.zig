const std = @import("std");

/// Language for hyphenation patterns.
pub const Language = enum {
    english,
};

/// A hyphenation pattern used in the Liang algorithm.
/// The pattern string contains letters (and '.') while values contains
/// the numeric hyphenation weights at each inter-letter position.
const HyphenPattern = struct {
    /// The letter pattern (lowercase, '.' for word boundary).
    text: []const u8,
    /// Numeric values between each letter position.
    /// Length = text.len + 1 (values at positions 0..text.len inclusive).
    values: []const u8,
};

/// Hyphenator using the Liang algorithm (as used by TeX).
pub const Hyphenator = struct {
    patterns: []const PatternEntry,
    min_prefix: u8 = 2,
    min_suffix: u8 = 3,

    const PatternEntry = struct {
        text: []const u8,
        values: []const u8,
    };

    /// Initialize a hyphenator for the given language.
    pub fn init(language: Language) Hyphenator {
        return switch (language) {
            .english => .{
                .patterns = &english_patterns,
                .min_prefix = 2,
                .min_suffix = 3,
            },
        };
    }

    /// Find valid hyphenation points in a word.
    /// Returns a slice of byte indices where the word can be split.
    /// Caller owns the returned slice.
    pub fn hyphenate(self: *const Hyphenator, allocator: std.mem.Allocator, word: []const u8) ![]usize {
        // Words too short to hyphenate
        if (word.len < @as(usize, self.min_prefix) + @as(usize, self.min_suffix)) {
            return allocator.alloc(usize, 0);
        }

        // Build the dotted word: ".word."
        var lower_buf = try allocator.alloc(u8, word.len);
        defer allocator.free(lower_buf);
        for (word, 0..) |ch, i| {
            lower_buf[i] = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
        }
        const lower = lower_buf[0..word.len];

        // dotted = "." ++ lower ++ "."
        var dotted = try allocator.alloc(u8, lower.len + 2);
        defer allocator.free(dotted);
        dotted[0] = '.';
        @memcpy(dotted[1 .. 1 + lower.len], lower);
        dotted[dotted.len - 1] = '.';

        // levels array: one entry per position between characters (word.len + 1 positions)
        // Position 0 = before first char, position word.len = after last char
        var levels = try allocator.alloc(u8, word.len + 1);
        defer allocator.free(levels);
        @memset(levels, 0);

        // Apply all patterns
        for (self.patterns) |pat| {
            // Try to find this pattern at every position in dotted
            const pat_text = pat.text;
            const pat_values = pat.values;
            if (pat_text.len > dotted.len) continue;

            var pos: usize = 0;
            while (pos + pat_text.len <= dotted.len) : (pos += 1) {
                if (matchesAt(dotted, pos, pat_text)) {
                    // Apply values. The pattern at position pos in dotted corresponds
                    // to levels starting at (pos - 1) in the word (because dotted[0] = '.').
                    // pat_values has pat_text.len + 1 entries.
                    for (pat_values, 0..) |v, vi| {
                        // The level index in the word: pos + vi maps to dotted position,
                        // and dotted position - 1 = word level position (since dotted starts with '.')
                        const level_idx_signed: isize = @as(isize, @intCast(pos)) + @as(isize, @intCast(vi)) - 1;
                        if (level_idx_signed >= 0 and level_idx_signed <= @as(isize, @intCast(word.len))) {
                            const level_idx: usize = @intCast(level_idx_signed);
                            if (v > levels[level_idx]) {
                                levels[level_idx] = v;
                            }
                        }
                    }
                }
            }
        }

        // Collect hyphenation points (odd levels), respecting min_prefix and min_suffix
        var points: std.ArrayListUnmanaged(usize) = .{};
        errdefer points.deinit(allocator);

        for (1..word.len) |i| {
            if (i < self.min_prefix or i > word.len - self.min_suffix) continue;
            if (levels[i] % 2 == 1) {
                try points.append(allocator, i);
            }
        }

        return points.toOwnedSlice(allocator);
    }

    fn matchesAt(haystack: []const u8, pos: usize, needle: []const u8) bool {
        if (pos + needle.len > haystack.len) return false;
        for (needle, 0..) |ch, i| {
            if (haystack[pos + i] != ch) return false;
        }
        return true;
    }
};

// English hyphenation patterns (Liang algorithm format).
// Each entry: { .text = "pattern_letters", .values = &[_]u8{ v0, v1, ... } }
// where values has length = text.len + 1, representing the hyphenation values
// at positions between each letter.
//
// These are derived from the standard TeX English hyphenation patterns.
const english_patterns = [_]Hyphenator.PatternEntry{
    // Common suffix/prefix patterns
    .{ .text = ".hy", .values = &[_]u8{ 0, 0, 1, 0 } }, // hy-
    .{ .text = "phen", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // phen-
    .{ .text = "hen", .values = &[_]u8{ 0, 0, 2, 0 } }, // override: he-n blocked
    .{ .text = "hena", .values = &[_]u8{ 0, 0, 0, 2, 0 } }, // block hen-a
    .{ .text = "na1tio", .values = &[_]u8{ 0, 0, 0, 0, 0, 0, 0 } },
    .{ .text = ".pre", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // pre-
    .{ .text = ".re", .values = &[_]u8{ 0, 0, 1, 0 } }, // re-
    .{ .text = ".un", .values = &[_]u8{ 0, 0, 1, 0 } }, // un-
    .{ .text = ".over", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } }, // over- (ov-er)
    .{ .text = ".mis", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // mis-
    .{ .text = ".dis", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // dis-
    .{ .text = ".de", .values = &[_]u8{ 0, 0, 1, 0 } }, // de-
    .{ .text = ".in", .values = &[_]u8{ 0, 0, 1, 0 } }, // in-
    .{ .text = ".con", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // con-
    .{ .text = ".com", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // com-
    .{ .text = ".ex", .values = &[_]u8{ 0, 0, 1, 0 } }, // ex-
    .{ .text = ".inter", .values = &[_]u8{ 0, 0, 0, 1, 0, 0, 0 } }, // in-ter
    .{ .text = ".auto", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } }, // au-to
    .{ .text = ".semi", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } }, // sem-i
    .{ .text = ".anti", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } }, // an-ti
    .{ .text = ".sub", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // sub-
    .{ .text = ".super", .values = &[_]u8{ 0, 0, 0, 1, 0, 0, 0 } }, // su-per
    .{ .text = ".trans", .values = &[_]u8{ 0, 0, 0, 0, 0, 1, 0 } }, // trans-
    .{ .text = ".out", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // out-
    .{ .text = ".non", .values = &[_]u8{ 0, 0, 0, 1, 0 } }, // non-
    .{ .text = ".micro", .values = &[_]u8{ 0, 0, 0, 1, 0, 0, 0 } }, // mi-cro
    .{ .text = ".macro", .values = &[_]u8{ 0, 0, 0, 1, 0, 0, 0 } }, // ma-cro

    // Common suffixes
    .{ .text = "tion.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -tion
    .{ .text = "sion.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -sion
    .{ .text = "ment.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -ment
    .{ .text = "ness.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -ness
    .{ .text = "able.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -able
    .{ .text = "ible.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -ible
    .{ .text = "ing.", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ing
    .{ .text = "ling.", .values = &[_]u8{ 0, 0, 1, 0, 0, 0 } }, // -ling
    .{ .text = "ous.", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ous
    .{ .text = "ious.", .values = &[_]u8{ 0, 0, 1, 0, 0, 0 } }, // -ious
    .{ .text = "eous.", .values = &[_]u8{ 0, 0, 1, 0, 0, 0 } }, // -eous
    .{ .text = "ful.", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ful
    .{ .text = "less.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -less
    .{ .text = "ance.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -ance
    .{ .text = "ence.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -ence
    .{ .text = "ally.", .values = &[_]u8{ 0, 0, 1, 0, 0, 0 } }, // -ally
    .{ .text = "ment", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ment
    .{ .text = "ness", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ness
    .{ .text = "tion", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -tion
    .{ .text = "sion", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -sion
    .{ .text = "ture.", .values = &[_]u8{ 0, 1, 0, 0, 0, 0 } }, // -ture
    .{ .text = "ture", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ture
    .{ .text = "ity.", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ity
    .{ .text = "ment", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ment
    .{ .text = "ism.", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ism
    .{ .text = "ist.", .values = &[_]u8{ 0, 1, 0, 0, 0 } }, // -ist

    // Vowel-consonant patterns (general syllable breaking)
    .{ .text = "ab", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ac", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ad", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "af", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ag", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ak", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "al", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "am", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "an", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ap", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ar", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "as", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "at", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "av", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ax", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "az", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "eb", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ec", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ed", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ef", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "eg", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ek", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "el", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "em", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "en", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ep", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "er", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "es", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "et", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ev", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ex", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ib", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ic", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "id", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "if", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ig", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ik", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "il", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "im", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "in", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ip", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ir", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "is", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "it", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "iv", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ix", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "iz", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ob", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "oc", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "od", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "of", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "og", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ok", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ol", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "om", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "on", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "op", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "or", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "os", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ot", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ov", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ox", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "oz", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ub", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "uc", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ud", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "uf", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ug", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "uk", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ul", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "um", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "un", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "up", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ur", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "us", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ut", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "uv", .values = &[_]u8{ 0, 1, 0 } },

    // Consonant cluster patterns - keep together (higher even values to suppress breaks)
    .{ .text = "bl", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "br", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "ch", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "ck", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "cl", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "cr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "dr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "fl", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "fr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "gh", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "gl", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "gr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "kn", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "pl", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "pr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "qu", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sc", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sh", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sk", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sl", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sm", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sn", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sp", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "st", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "sw", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "th", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "tr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "tw", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "wh", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "wr", .values = &[_]u8{ 0, 0, 2 } },
    .{ .text = "ph", .values = &[_]u8{ 0, 0, 2 } },

    // Double consonants - break between them
    .{ .text = "bb", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "cc", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "dd", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ff", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "gg", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ll", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "mm", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "nn", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "pp", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "rr", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "ss", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "tt", .values = &[_]u8{ 0, 1, 0 } },
    .{ .text = "zz", .values = &[_]u8{ 0, 1, 0 } },

    // Consonant-vowel onset patterns (break before consonant+vowel)
    .{ .text = "ba", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "be", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "bi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "bo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "bu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ca", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ce", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ci", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "co", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "cu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "da", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "de", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "di", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "do", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "du", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "fa", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "fe", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "fi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "fo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "fu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ga", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ge", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "gi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "go", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "gu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ha", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "he", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "hi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ho", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "hu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ja", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "je", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ji", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "jo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ju", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ka", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ke", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ki", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ko", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ku", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "la", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "le", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "li", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "lo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "lu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ma", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "me", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "mi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "mo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "mu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "na", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ne", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ni", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "no", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "nu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "pa", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "pe", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "pi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "po", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "pu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ra", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "re", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ri", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ro", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ru", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "sa", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "se", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "si", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "so", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "su", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ta", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "te", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ti", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "to", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "tu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "va", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ve", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "vi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "vo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "vu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "wa", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "we", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "wi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "wo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "xa", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "xe", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "xi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "xo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ya", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ye", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "yi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "yo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "yu", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "za", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "ze", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "zi", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "zo", .values = &[_]u8{ 1, 0, 0 } },
    .{ .text = "zu", .values = &[_]u8{ 1, 0, 0 } },

    // Protect word-initial consonant clusters from breaking
    .{ .text = ".bl", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".br", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".ch", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".cl", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".cr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".dr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".fl", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".fr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".gl", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".gr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".kn", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".ph", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".pl", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".pr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".qu", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sc", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sh", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sk", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sl", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sm", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sn", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sp", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".st", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".sw", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".th", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".tr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".tw", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".wh", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".wr", .values = &[_]u8{ 0, 0, 2, 0 } },
    .{ .text = ".str", .values = &[_]u8{ 0, 0, 0, 2, 0 } },
    .{ .text = ".scr", .values = &[_]u8{ 0, 0, 0, 2, 0 } },
    .{ .text = ".spl", .values = &[_]u8{ 0, 0, 0, 2, 0 } },
    .{ .text = ".spr", .values = &[_]u8{ 0, 0, 0, 2, 0 } },
    .{ .text = ".squ", .values = &[_]u8{ 0, 0, 0, 2, 0 } },

    // Common word patterns
    .{ .text = "abil", .values = &[_]u8{ 0, 0, 1, 0, 0 } },
    .{ .text = "abl", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = "ical", .values = &[_]u8{ 0, 0, 1, 0, 0 } },
    .{ .text = "ual", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = "ual.", .values = &[_]u8{ 0, 0, 1, 0, 0 } },
    .{ .text = "olo", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = "olog", .values = &[_]u8{ 0, 0, 1, 0, 0 } },
    .{ .text = "omi", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = "graph", .values = &[_]u8{ 0, 0, 0, 0, 2, 0 } },
    .{ .text = "trop", .values = &[_]u8{ 0, 0, 0, 1, 0 } },
    .{ .text = "tic", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "tic.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ical.", .values = &[_]u8{ 0, 0, 1, 0, 0, 0 } },
    .{ .text = "ary.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ery.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ory.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ary", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ery", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ory", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "age.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "age", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ive.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ive", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ize.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ize", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ate.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ure.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ite.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },
    .{ .text = "ute.", .values = &[_]u8{ 0, 1, 0, 0, 0 } },

    // Additional useful patterns
    .{ .text = "ect", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "act", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ist", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ism", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ize", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ise", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ous", .values = &[_]u8{ 0, 1, 0, 0 } },
    .{ .text = "ful", .values = &[_]u8{ 0, 1, 0, 0 } },

    // Protect silent-e endings
    .{ .text = "le.", .values = &[_]u8{ 2, 0, 0, 0 } },
    .{ .text = "ble.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "tle.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "ple.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "dle.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "gle.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "fle.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "kle.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },
    .{ .text = "cle.", .values = &[_]u8{ 0, 2, 0, 0, 0 } },

    // More prefix patterns
    .{ .text = ".be", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = ".en", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = ".em", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = ".im", .values = &[_]u8{ 0, 0, 1, 0 } },
    .{ .text = ".pro", .values = &[_]u8{ 0, 0, 0, 1, 0 } },
    .{ .text = ".per", .values = &[_]u8{ 0, 0, 0, 1, 0 } },
    .{ .text = ".para", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } },
    .{ .text = ".mono", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } },
    .{ .text = ".poly", .values = &[_]u8{ 0, 0, 0, 1, 0, 0 } },
    .{ .text = ".multi", .values = &[_]u8{ 0, 0, 0, 0, 1, 0, 0 } },
    .{ .text = ".under", .values = &[_]u8{ 0, 0, 0, 1, 0, 0, 0 } },
    .{ .text = ".counter", .values = &[_]u8{ 0, 0, 0, 0, 0, 1, 0, 0, 0 } },
};

test "hyphenate basic word" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "hyphenation");
    defer std.testing.allocator.free(points);
    // Should find at least one hyphenation point
    try std.testing.expect(points.len > 0);
}

test "hyphenate short word returns no points" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "the");
    defer std.testing.allocator.free(points);
    try std.testing.expectEqual(@as(usize, 0), points.len);
}

test "min_prefix and min_suffix enforced" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "evening");
    defer std.testing.allocator.free(points);
    for (points) |p| {
        try std.testing.expect(p >= hyph.min_prefix);
        try std.testing.expect(p <= "evening".len - hyph.min_suffix);
    }
}
