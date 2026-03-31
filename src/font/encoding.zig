const std = @import("std");

/// WinAnsi encoding glyph name table.
/// Maps character codes 0-255 to Adobe glyph names as used in PDF WinAnsiEncoding.
/// Codes that do not map to a glyph return ".notdef".
pub fn glyphName(code: u8) []const u8 {
    return winansi_glyph_names[code];
}

/// The WinAnsiEncoding differences array describes the glyph names that differ
/// from the standard encoding. This constant provides the entries as they would
/// appear in a PDF /Differences array, covering the positions 128-159 which
/// differ from the standard Latin encoding, plus selected positions in 160-255.
pub const winansi_differences = [_]WinAnsiDifference{
    .{ .code = 128, .name = "Euro" },
    .{ .code = 130, .name = "quotesinglbase" },
    .{ .code = 131, .name = "florin" },
    .{ .code = 132, .name = "quotedblbase" },
    .{ .code = 133, .name = "ellipsis" },
    .{ .code = 134, .name = "dagger" },
    .{ .code = 135, .name = "daggerdbl" },
    .{ .code = 136, .name = "circumflex" },
    .{ .code = 137, .name = "perthousand" },
    .{ .code = 138, .name = "Scaron" },
    .{ .code = 139, .name = "guilsinglleft" },
    .{ .code = 140, .name = "OE" },
    .{ .code = 142, .name = "Zcaron" },
    .{ .code = 145, .name = "quoteleft" },
    .{ .code = 146, .name = "quoteright" },
    .{ .code = 147, .name = "quotedblleft" },
    .{ .code = 148, .name = "quotedblright" },
    .{ .code = 149, .name = "bullet" },
    .{ .code = 150, .name = "endash" },
    .{ .code = 151, .name = "emdash" },
    .{ .code = 152, .name = "tilde" },
    .{ .code = 153, .name = "trademark" },
    .{ .code = 154, .name = "scaron" },
    .{ .code = 155, .name = "guilsinglright" },
    .{ .code = 156, .name = "oe" },
    .{ .code = 158, .name = "zcaron" },
    .{ .code = 159, .name = "Ydieresis" },
};

pub const WinAnsiDifference = struct {
    code: u8,
    name: []const u8,
};

/// Complete WinAnsiEncoding glyph name table for all 256 character codes.
const winansi_glyph_names: [256][]const u8 = .{
    // 0-31: control characters
    ".notdef", // 0
    ".notdef", // 1
    ".notdef", // 2
    ".notdef", // 3
    ".notdef", // 4
    ".notdef", // 5
    ".notdef", // 6
    ".notdef", // 7
    ".notdef", // 8
    ".notdef", // 9
    ".notdef", // 10
    ".notdef", // 11
    ".notdef", // 12
    ".notdef", // 13
    ".notdef", // 14
    ".notdef", // 15
    ".notdef", // 16
    ".notdef", // 17
    ".notdef", // 18
    ".notdef", // 19
    ".notdef", // 20
    ".notdef", // 21
    ".notdef", // 22
    ".notdef", // 23
    ".notdef", // 24
    ".notdef", // 25
    ".notdef", // 26
    ".notdef", // 27
    ".notdef", // 28
    ".notdef", // 29
    ".notdef", // 30
    ".notdef", // 31
    // 32-127: ASCII printable
    "space", // 32
    "exclam", // 33
    "quotedbl", // 34
    "numbersign", // 35
    "dollar", // 36
    "percent", // 37
    "ampersand", // 38
    "quotesingle", // 39
    "parenleft", // 40
    "parenright", // 41
    "asterisk", // 42
    "plus", // 43
    "comma", // 44
    "hyphen", // 45
    "period", // 46
    "slash", // 47
    "zero", // 48
    "one", // 49
    "two", // 50
    "three", // 51
    "four", // 52
    "five", // 53
    "six", // 54
    "seven", // 55
    "eight", // 56
    "nine", // 57
    "colon", // 58
    "semicolon", // 59
    "less", // 60
    "equal", // 61
    "greater", // 62
    "question", // 63
    "at", // 64
    "A", // 65
    "B", // 66
    "C", // 67
    "D", // 68
    "E", // 69
    "F", // 70
    "G", // 71
    "H", // 72
    "I", // 73
    "J", // 74
    "K", // 75
    "L", // 76
    "M", // 77
    "N", // 78
    "O", // 79
    "P", // 80
    "Q", // 81
    "R", // 82
    "S", // 83
    "T", // 84
    "U", // 85
    "V", // 86
    "W", // 87
    "X", // 88
    "Y", // 89
    "Z", // 90
    "bracketleft", // 91
    "backslash", // 92
    "bracketright", // 93
    "asciicircum", // 94
    "underscore", // 95
    "grave", // 96
    "a", // 97
    "b", // 98
    "c", // 99
    "d", // 100
    "e", // 101
    "f", // 102
    "g", // 103
    "h", // 104
    "i", // 105
    "j", // 106
    "k", // 107
    "l", // 108
    "m", // 109
    "n", // 110
    "o", // 111
    "p", // 112
    "q", // 113
    "r", // 114
    "s", // 115
    "t", // 116
    "u", // 117
    "v", // 118
    "w", // 119
    "x", // 120
    "y", // 121
    "z", // 122
    "braceleft", // 123
    "bar", // 124
    "braceright", // 125
    "asciitilde", // 126
    ".notdef", // 127
    // 128-159: WinAnsi differences
    "Euro", // 128
    ".notdef", // 129
    "quotesinglbase", // 130
    "florin", // 131
    "quotedblbase", // 132
    "ellipsis", // 133
    "dagger", // 134
    "daggerdbl", // 135
    "circumflex", // 136
    "perthousand", // 137
    "Scaron", // 138
    "guilsinglleft", // 139
    "OE", // 140
    ".notdef", // 141
    "Zcaron", // 142
    ".notdef", // 143
    ".notdef", // 144
    "quoteleft", // 145
    "quoteright", // 146
    "quotedblleft", // 147
    "quotedblright", // 148
    "bullet", // 149
    "endash", // 150
    "emdash", // 151
    "tilde", // 152
    "trademark", // 153
    "scaron", // 154
    "guilsinglright", // 155
    "oe", // 156
    ".notdef", // 157
    "zcaron", // 158
    "Ydieresis", // 159
    // 160-255: Latin-1 supplement
    "space", // 160 (non-breaking space)
    "exclamdown", // 161
    "cent", // 162
    "sterling", // 163
    "currency", // 164
    "yen", // 165
    "brokenbar", // 166
    "section", // 167
    "dieresis", // 168
    "copyright", // 169
    "ordfeminine", // 170
    "guillemotleft", // 171
    "logicalnot", // 172
    "hyphen", // 173 (soft hyphen)
    "registered", // 174
    "macron", // 175
    "degree", // 176
    "plusminus", // 177
    "twosuperior", // 178
    "threesuperior", // 179
    "acute", // 180
    "mu", // 181
    "paragraph", // 182
    "periodcentered", // 183
    "cedilla", // 184
    "onesuperior", // 185
    "ordmasculine", // 186
    "guillemotright", // 187
    "onequarter", // 188
    "onehalf", // 189
    "threequarters", // 190
    "questiondown", // 191
    "Agrave", // 192
    "Aacute", // 193
    "Acircumflex", // 194
    "Atilde", // 195
    "Adieresis", // 196
    "Aring", // 197
    "AE", // 198
    "Ccedilla", // 199
    "Egrave", // 200
    "Eacute", // 201
    "Ecircumflex", // 202
    "Edieresis", // 203
    "Igrave", // 204
    "Iacute", // 205
    "Icircumflex", // 206
    "Idieresis", // 207
    "Eth", // 208
    "Ntilde", // 209
    "Ograve", // 210
    "Oacute", // 211
    "Ocircumflex", // 212
    "Otilde", // 213
    "Odieresis", // 214
    "multiply", // 215
    "Oslash", // 216
    "Ugrave", // 217
    "Uacute", // 218
    "Ucircumflex", // 219
    "Udieresis", // 220
    "Yacute", // 221
    "Thorn", // 222
    "germandbls", // 223
    "agrave", // 224
    "aacute", // 225
    "acircumflex", // 226
    "atilde", // 227
    "adieresis", // 228
    "aring", // 229
    "ae", // 230
    "ccedilla", // 231
    "egrave", // 232
    "eacute", // 233
    "ecircumflex", // 234
    "edieresis", // 235
    "igrave", // 236
    "iacute", // 237
    "icircumflex", // 238
    "idieresis", // 239
    "eth", // 240
    "ntilde", // 241
    "ograve", // 242
    "oacute", // 243
    "ocircumflex", // 244
    "otilde", // 245
    "odieresis", // 246
    "divide", // 247
    "oslash", // 248
    "ugrave", // 249
    "uacute", // 250
    "ucircumflex", // 251
    "udieresis", // 252
    "yacute", // 253
    "thorn", // 254
    "ydieresis", // 255
};

// -- Tests --

test "glyphName space" {
    try std.testing.expectEqualStrings("space", glyphName(32));
}

test "glyphName A" {
    try std.testing.expectEqualStrings("A", glyphName(65));
}

test "glyphName a" {
    try std.testing.expectEqualStrings("a", glyphName(97));
}

test "glyphName control char" {
    try std.testing.expectEqualStrings(".notdef", glyphName(0));
}

test "glyphName Euro" {
    try std.testing.expectEqualStrings("Euro", glyphName(128));
}

test "glyphName Agrave" {
    try std.testing.expectEqualStrings("Agrave", glyphName(192));
}

test "glyphName ydieresis" {
    try std.testing.expectEqualStrings("ydieresis", glyphName(255));
}

test "winansi_differences length" {
    try std.testing.expectEqual(@as(usize, 27), winansi_differences.len);
}

test "winansi_differences first entry" {
    try std.testing.expectEqual(@as(u8, 128), winansi_differences[0].code);
    try std.testing.expectEqualStrings("Euro", winansi_differences[0].name);
}
