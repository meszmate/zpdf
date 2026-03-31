const std = @import("std");

/// The 14 standard PDF fonts that are guaranteed to be available in all PDF viewers.
pub const StandardFont = enum {
    helvetica,
    helvetica_bold,
    helvetica_oblique,
    helvetica_bold_oblique,
    times_roman,
    times_bold,
    times_italic,
    times_bold_italic,
    courier,
    courier_bold,
    courier_oblique,
    courier_bold_oblique,
    symbol,
    zapf_dingbats,

    /// Returns the PDF base font name for use in font dictionaries.
    pub fn pdfName(self: StandardFont) []const u8 {
        return switch (self) {
            .helvetica => "Helvetica",
            .helvetica_bold => "Helvetica-Bold",
            .helvetica_oblique => "Helvetica-Oblique",
            .helvetica_bold_oblique => "Helvetica-BoldOblique",
            .times_roman => "Times-Roman",
            .times_bold => "Times-Bold",
            .times_italic => "Times-Italic",
            .times_bold_italic => "Times-BoldItalic",
            .courier => "Courier",
            .courier_bold => "Courier-Bold",
            .courier_oblique => "Courier-Oblique",
            .courier_bold_oblique => "Courier-BoldOblique",
            .symbol => "Symbol",
            .zapf_dingbats => "ZapfDingbats",
        };
    }

    /// Returns true if the font is fixed-pitch (monospaced).
    pub fn isFixedPitch(self: StandardFont) bool {
        return switch (self) {
            .courier, .courier_bold, .courier_oblique, .courier_bold_oblique => true,
            else => false,
        };
    }

    /// Get character width in font units (out of 1000) for a given character code.
    /// Uses accurate Adobe metrics for Helvetica; Courier is fixed at 600;
    /// other fonts use Helvetica widths as an approximation.
    pub fn charWidth(self: StandardFont, char: u8) u16 {
        return switch (self) {
            .courier, .courier_bold, .courier_oblique, .courier_bold_oblique => 600,
            .helvetica, .helvetica_oblique => helvetica_widths[char],
            .helvetica_bold, .helvetica_bold_oblique => helvetica_bold_widths[char],
            .times_roman => times_roman_widths[char],
            .times_bold => times_bold_widths[char],
            .times_italic, .times_bold_italic => times_roman_widths[char],
            .symbol, .zapf_dingbats => helvetica_widths[char],
        };
    }

    /// Calculate the width of a text string in points at a given font size.
    pub fn textWidth(self: StandardFont, text: []const u8, font_size: f32) f32 {
        var total: u32 = 0;
        for (text) |ch| {
            total += self.charWidth(ch);
        }
        return @as(f32, @floatFromInt(total)) * font_size / 1000.0;
    }

    /// Font ascender in font units (out of 1000).
    pub fn ascender(self: StandardFont) i16 {
        return switch (self) {
            .helvetica, .helvetica_oblique => 718,
            .helvetica_bold, .helvetica_bold_oblique => 718,
            .times_roman, .times_italic => 683,
            .times_bold, .times_bold_italic => 683,
            .courier, .courier_bold, .courier_oblique, .courier_bold_oblique => 629,
            .symbol => 1010,
            .zapf_dingbats => 820,
        };
    }

    /// Font descender in font units (out of 1000). Typically negative.
    pub fn descender(self: StandardFont) i16 {
        return switch (self) {
            .helvetica, .helvetica_oblique => -207,
            .helvetica_bold, .helvetica_bold_oblique => -207,
            .times_roman, .times_italic => -217,
            .times_bold, .times_bold_italic => -217,
            .courier, .courier_bold, .courier_oblique, .courier_bold_oblique => -157,
            .symbol => -293,
            .zapf_dingbats => -143,
        };
    }

    /// Average character width as a fraction (width / 1000).
    /// Used for rough text width estimation in word-wrapping.
    pub fn avgCharWidth(self: StandardFont) f32 {
        return switch (self) {
            .courier, .courier_bold, .courier_oblique, .courier_bold_oblique => 0.6,
            .helvetica, .helvetica_oblique => 0.52,
            .helvetica_bold, .helvetica_bold_oblique => 0.535,
            .times_roman, .times_italic, .times_bold, .times_bold_italic => 0.47,
            .symbol, .zapf_dingbats => 0.52,
        };
    }

    /// Recommended line gap in font units.
    pub fn lineGap(self: StandardFont) i16 {
        return switch (self) {
            .helvetica, .helvetica_oblique => 33,
            .helvetica_bold, .helvetica_bold_oblique => 33,
            .times_roman, .times_italic => 0,
            .times_bold, .times_bold_italic => 0,
            .courier, .courier_bold, .courier_oblique, .courier_bold_oblique => 0,
            .symbol => 0,
            .zapf_dingbats => 0,
        };
    }
};

// ---------------------------------------------------------------------------
// Helvetica character widths (Adobe standard metrics, all 256 character codes)
// Based on the Adobe Font Metrics (AFM) file for Helvetica.
// ---------------------------------------------------------------------------
const helvetica_widths: [256]u16 = blk: {
    var w: [256]u16 = [_]u16{278} ** 256; // default to space width
    // Control characters 0-31: width 0
    for (0..32) |i| {
        w[i] = 0;
    }
    // ASCII printable characters 32-126 (Adobe Helvetica AFM metrics)
    w[32] = 278; // space
    w[33] = 278; // exclam
    w[34] = 355; // quotedbl
    w[35] = 556; // numbersign
    w[36] = 556; // dollar
    w[37] = 889; // percent
    w[38] = 667; // ampersand
    w[39] = 191; // quotesingle
    w[40] = 333; // parenleft
    w[41] = 333; // parenright
    w[42] = 389; // asterisk
    w[43] = 584; // plus
    w[44] = 278; // comma
    w[45] = 333; // hyphen
    w[46] = 278; // period
    w[47] = 278; // slash
    w[48] = 556; // zero
    w[49] = 556; // one
    w[50] = 556; // two
    w[51] = 556; // three
    w[52] = 556; // four
    w[53] = 556; // five
    w[54] = 556; // six
    w[55] = 556; // seven
    w[56] = 556; // eight
    w[57] = 556; // nine
    w[58] = 278; // colon
    w[59] = 278; // semicolon
    w[60] = 584; // less
    w[61] = 584; // equal
    w[62] = 584; // greater
    w[63] = 556; // question
    w[64] = 1015; // at
    w[65] = 667; // A
    w[66] = 667; // B
    w[67] = 722; // C
    w[68] = 722; // D
    w[69] = 667; // E
    w[70] = 611; // F
    w[71] = 778; // G
    w[72] = 722; // H
    w[73] = 278; // I
    w[74] = 500; // J
    w[75] = 667; // K
    w[76] = 556; // L
    w[77] = 833; // M
    w[78] = 722; // N
    w[79] = 778; // O
    w[80] = 667; // P
    w[81] = 778; // Q
    w[82] = 722; // R
    w[83] = 667; // S
    w[84] = 611; // T
    w[85] = 722; // U
    w[86] = 667; // V
    w[87] = 944; // W
    w[88] = 667; // X
    w[89] = 667; // Y
    w[90] = 611; // Z
    w[91] = 278; // bracketleft
    w[92] = 278; // backslash
    w[93] = 278; // bracketright
    w[94] = 469; // asciicircum
    w[95] = 556; // underscore
    w[96] = 333; // grave
    w[97] = 556; // a
    w[98] = 556; // b
    w[99] = 500; // c
    w[100] = 556; // d
    w[101] = 556; // e
    w[102] = 278; // f
    w[103] = 556; // g
    w[104] = 556; // h
    w[105] = 222; // i
    w[106] = 222; // j
    w[107] = 500; // k
    w[108] = 222; // l
    w[109] = 833; // m
    w[110] = 556; // n
    w[111] = 556; // o
    w[112] = 556; // p
    w[113] = 556; // q
    w[114] = 333; // r
    w[115] = 500; // s
    w[116] = 278; // t
    w[117] = 556; // u
    w[118] = 500; // v
    w[119] = 722; // w
    w[120] = 500; // x
    w[121] = 500; // y
    w[122] = 500; // z
    w[123] = 334; // braceleft
    w[124] = 260; // bar
    w[125] = 334; // braceright
    w[126] = 584; // asciitilde
    w[127] = 0; // DEL
    // Extended Latin (128-255) - WinAnsi encoding widths from Helvetica AFM
    w[128] = 556; // Euro (estimated)
    w[130] = 222; // quotesinglbase
    w[131] = 556; // florin
    w[132] = 333; // quotedblbase
    w[133] = 1000; // ellipsis
    w[134] = 556; // dagger
    w[135] = 556; // daggerdbl
    w[136] = 333; // circumflex
    w[137] = 1000; // perthousand
    w[138] = 667; // Scaron
    w[139] = 333; // guilsinglleft
    w[140] = 1000; // OE
    w[142] = 611; // Zcaron
    w[145] = 222; // quoteleft
    w[146] = 222; // quoteright
    w[147] = 333; // quotedblleft
    w[148] = 333; // quotedblright
    w[149] = 350; // bullet
    w[150] = 556; // endash
    w[151] = 1000; // emdash
    w[152] = 333; // tilde
    w[153] = 1000; // trademark
    w[154] = 500; // scaron
    w[155] = 333; // guilsinglright
    w[156] = 944; // oe
    w[158] = 500; // zcaron
    w[159] = 667; // Ydieresis
    w[160] = 278; // nbspace
    w[161] = 333; // exclamdown
    w[162] = 556; // cent
    w[163] = 556; // sterling
    w[164] = 556; // currency
    w[165] = 556; // yen
    w[166] = 260; // brokenbar
    w[167] = 556; // section
    w[168] = 333; // dieresis
    w[169] = 737; // copyright
    w[170] = 370; // ordfeminine
    w[171] = 556; // guillemotleft
    w[172] = 584; // logicalnot
    w[173] = 333; // softhyphen
    w[174] = 737; // registered
    w[175] = 333; // macron
    w[176] = 400; // degree
    w[177] = 584; // plusminus
    w[178] = 333; // twosuperior
    w[179] = 333; // threesuperior
    w[180] = 333; // acute
    w[181] = 556; // mu
    w[182] = 537; // paragraph
    w[183] = 278; // periodcentered
    w[184] = 333; // cedilla
    w[185] = 333; // onesuperior
    w[186] = 365; // ordmasculine
    w[187] = 556; // guillemotright
    w[188] = 834; // onequarter
    w[189] = 834; // onehalf
    w[190] = 834; // threequarters
    w[191] = 611; // questiondown
    w[192] = 667; // Agrave
    w[193] = 667; // Aacute
    w[194] = 667; // Acircumflex
    w[195] = 667; // Atilde
    w[196] = 667; // Adieresis
    w[197] = 667; // Aring
    w[198] = 1000; // AE
    w[199] = 722; // Ccedilla
    w[200] = 667; // Egrave
    w[201] = 667; // Eacute
    w[202] = 667; // Ecircumflex
    w[203] = 667; // Edieresis
    w[204] = 278; // Igrave
    w[205] = 278; // Iacute
    w[206] = 278; // Icircumflex
    w[207] = 278; // Idieresis
    w[208] = 722; // Eth
    w[209] = 722; // Ntilde
    w[210] = 778; // Ograve
    w[211] = 778; // Oacute
    w[212] = 778; // Ocircumflex
    w[213] = 778; // Otilde
    w[214] = 778; // Odieresis
    w[215] = 584; // multiply
    w[216] = 778; // Oslash
    w[217] = 722; // Ugrave
    w[218] = 722; // Uacute
    w[219] = 722; // Ucircumflex
    w[220] = 722; // Udieresis
    w[221] = 667; // Yacute
    w[222] = 667; // Thorn
    w[223] = 611; // germandbls
    w[224] = 556; // agrave
    w[225] = 556; // aacute
    w[226] = 556; // acircumflex
    w[227] = 556; // atilde
    w[228] = 556; // adieresis
    w[229] = 556; // aring
    w[230] = 889; // ae
    w[231] = 500; // ccedilla
    w[232] = 556; // egrave
    w[233] = 556; // eacute
    w[234] = 556; // ecircumflex
    w[235] = 556; // edieresis
    w[236] = 278; // igrave (using 278 per AFM; some sources say 222)
    w[237] = 278; // iacute
    w[238] = 278; // icircumflex
    w[239] = 278; // idieresis
    w[240] = 556; // eth
    w[241] = 556; // ntilde
    w[242] = 556; // ograve
    w[243] = 556; // oacute
    w[244] = 556; // ocircumflex
    w[245] = 556; // otilde
    w[246] = 556; // odieresis
    w[247] = 584; // divide
    w[248] = 611; // oslash
    w[249] = 556; // ugrave
    w[250] = 556; // uacute
    w[251] = 556; // ucircumflex
    w[252] = 556; // udieresis
    w[253] = 500; // yacute
    w[254] = 556; // thorn
    w[255] = 500; // ydieresis
    break :blk w;
};

// ---------------------------------------------------------------------------
// Helvetica-Bold character widths (Adobe AFM metrics)
// ---------------------------------------------------------------------------
const helvetica_bold_widths: [256]u16 = blk: {
    var w: [256]u16 = [_]u16{278} ** 256;
    for (0..32) |i| {
        w[i] = 0;
    }
    w[32] = 278; // space
    w[33] = 333; // exclam
    w[34] = 474; // quotedbl
    w[35] = 556; // numbersign
    w[36] = 556; // dollar
    w[37] = 889; // percent
    w[38] = 722; // ampersand
    w[39] = 238; // quotesingle
    w[40] = 333; // parenleft
    w[41] = 333; // parenright
    w[42] = 389; // asterisk
    w[43] = 584; // plus
    w[44] = 278; // comma
    w[45] = 333; // hyphen
    w[46] = 278; // period
    w[47] = 278; // slash
    w[48] = 556; // zero
    w[49] = 556; // one
    w[50] = 556; // two
    w[51] = 556; // three
    w[52] = 556; // four
    w[53] = 556; // five
    w[54] = 556; // six
    w[55] = 556; // seven
    w[56] = 556; // eight
    w[57] = 556; // nine
    w[58] = 333; // colon
    w[59] = 333; // semicolon
    w[60] = 584; // less
    w[61] = 584; // equal
    w[62] = 584; // greater
    w[63] = 611; // question
    w[64] = 975; // at
    w[65] = 722; // A
    w[66] = 722; // B
    w[67] = 722; // C
    w[68] = 722; // D
    w[69] = 667; // E
    w[70] = 611; // F
    w[71] = 778; // G
    w[72] = 722; // H
    w[73] = 278; // I
    w[74] = 556; // J
    w[75] = 722; // K
    w[76] = 611; // L
    w[77] = 833; // M
    w[78] = 722; // N
    w[79] = 778; // O
    w[80] = 667; // P
    w[81] = 778; // Q
    w[82] = 722; // R
    w[83] = 667; // S
    w[84] = 611; // T
    w[85] = 722; // U
    w[86] = 667; // V
    w[87] = 944; // W
    w[88] = 667; // X
    w[89] = 667; // Y
    w[90] = 611; // Z
    w[91] = 333; // bracketleft
    w[92] = 278; // backslash
    w[93] = 333; // bracketright
    w[94] = 584; // asciicircum
    w[95] = 556; // underscore
    w[96] = 333; // grave
    w[97] = 556; // a
    w[98] = 611; // b
    w[99] = 556; // c
    w[100] = 611; // d
    w[101] = 556; // e
    w[102] = 333; // f
    w[103] = 611; // g
    w[104] = 611; // h
    w[105] = 278; // i
    w[106] = 278; // j
    w[107] = 556; // k
    w[108] = 278; // l
    w[109] = 889; // m
    w[110] = 611; // n
    w[111] = 611; // o
    w[112] = 611; // p
    w[113] = 611; // q
    w[114] = 389; // r
    w[115] = 556; // s
    w[116] = 333; // t
    w[117] = 611; // u
    w[118] = 556; // v
    w[119] = 778; // w
    w[120] = 556; // x
    w[121] = 556; // y
    w[122] = 500; // z
    w[123] = 389; // braceleft
    w[124] = 280; // bar
    w[125] = 389; // braceright
    w[126] = 584; // asciitilde
    w[127] = 0;
    // Extended characters use same as helvetica for simplicity
    w[160] = 278;
    w[161] = 333;
    w[162] = 556;
    w[163] = 556;
    w[164] = 556;
    w[165] = 556;
    w[166] = 280;
    w[167] = 556;
    w[168] = 333;
    w[169] = 737;
    w[170] = 370;
    w[171] = 556;
    w[172] = 584;
    w[173] = 333;
    w[174] = 737;
    w[175] = 333;
    w[176] = 400;
    w[177] = 584;
    w[192] = 722;
    w[193] = 722;
    w[194] = 722;
    w[195] = 722;
    w[196] = 722;
    w[197] = 722;
    w[198] = 1000;
    w[199] = 722;
    w[200] = 667;
    w[201] = 667;
    w[202] = 667;
    w[203] = 667;
    w[204] = 278;
    w[205] = 278;
    w[206] = 278;
    w[207] = 278;
    w[208] = 722;
    w[209] = 722;
    w[210] = 778;
    w[211] = 778;
    w[212] = 778;
    w[213] = 778;
    w[214] = 778;
    w[215] = 584;
    w[216] = 778;
    w[217] = 722;
    w[218] = 722;
    w[219] = 722;
    w[220] = 722;
    w[221] = 667;
    w[222] = 667;
    w[223] = 611;
    w[224] = 556;
    w[225] = 556;
    w[226] = 556;
    w[227] = 556;
    w[228] = 556;
    w[229] = 556;
    w[230] = 889;
    w[231] = 556;
    w[232] = 556;
    w[233] = 556;
    w[234] = 556;
    w[235] = 556;
    w[236] = 278;
    w[237] = 278;
    w[238] = 278;
    w[239] = 278;
    w[240] = 611;
    w[241] = 611;
    w[242] = 611;
    w[243] = 611;
    w[244] = 611;
    w[245] = 611;
    w[246] = 611;
    w[247] = 584;
    w[248] = 611;
    w[249] = 611;
    w[250] = 611;
    w[251] = 611;
    w[252] = 611;
    w[253] = 556;
    w[254] = 611;
    w[255] = 556;
    break :blk w;
};

// ---------------------------------------------------------------------------
// Times-Roman character widths (Adobe AFM metrics, printable ASCII)
// ---------------------------------------------------------------------------
const times_roman_widths: [256]u16 = blk: {
    var w: [256]u16 = [_]u16{250} ** 256;
    for (0..32) |i| {
        w[i] = 0;
    }
    w[32] = 250; // space
    w[33] = 333; // exclam
    w[34] = 408; // quotedbl
    w[35] = 500; // numbersign
    w[36] = 500; // dollar
    w[37] = 833; // percent
    w[38] = 778; // ampersand
    w[39] = 180; // quotesingle
    w[40] = 333; // parenleft
    w[41] = 333; // parenright
    w[42] = 500; // asterisk
    w[43] = 564; // plus
    w[44] = 250; // comma
    w[45] = 333; // hyphen
    w[46] = 250; // period
    w[47] = 278; // slash
    w[48] = 500; // zero
    w[49] = 500; // one
    w[50] = 500; // two
    w[51] = 500; // three
    w[52] = 500; // four
    w[53] = 500; // five
    w[54] = 500; // six
    w[55] = 500; // seven
    w[56] = 500; // eight
    w[57] = 500; // nine
    w[58] = 278; // colon
    w[59] = 278; // semicolon
    w[60] = 564; // less
    w[61] = 564; // equal
    w[62] = 564; // greater
    w[63] = 444; // question
    w[64] = 921; // at
    w[65] = 722; // A
    w[66] = 667; // B
    w[67] = 667; // C
    w[68] = 722; // D
    w[69] = 611; // E
    w[70] = 556; // F
    w[71] = 722; // G
    w[72] = 722; // H
    w[73] = 333; // I
    w[74] = 389; // J
    w[75] = 722; // K
    w[76] = 611; // L
    w[77] = 889; // M
    w[78] = 722; // N
    w[79] = 722; // O
    w[80] = 556; // P
    w[81] = 722; // Q
    w[82] = 667; // R
    w[83] = 556; // S
    w[84] = 611; // T
    w[85] = 722; // U
    w[86] = 722; // V
    w[87] = 944; // W
    w[88] = 722; // X
    w[89] = 722; // Y
    w[90] = 611; // Z
    w[91] = 333; // bracketleft
    w[92] = 278; // backslash
    w[93] = 333; // bracketright
    w[94] = 469; // asciicircum
    w[95] = 500; // underscore
    w[96] = 333; // grave
    w[97] = 444; // a
    w[98] = 500; // b
    w[99] = 444; // c
    w[100] = 500; // d
    w[101] = 444; // e
    w[102] = 333; // f
    w[103] = 500; // g
    w[104] = 500; // h
    w[105] = 278; // i
    w[106] = 278; // j
    w[107] = 500; // k
    w[108] = 278; // l
    w[109] = 778; // m
    w[110] = 500; // n
    w[111] = 500; // o
    w[112] = 500; // p
    w[113] = 500; // q
    w[114] = 333; // r
    w[115] = 389; // s
    w[116] = 278; // t
    w[117] = 500; // u
    w[118] = 500; // v
    w[119] = 722; // w
    w[120] = 500; // x
    w[121] = 500; // y
    w[122] = 444; // z
    w[123] = 480; // braceleft
    w[124] = 200; // bar
    w[125] = 480; // braceright
    w[126] = 541; // asciitilde
    w[127] = 0;
    break :blk w;
};

// ---------------------------------------------------------------------------
// Times-Bold character widths (Adobe AFM metrics, printable ASCII)
// ---------------------------------------------------------------------------
const times_bold_widths: [256]u16 = blk: {
    var w: [256]u16 = [_]u16{250} ** 256;
    for (0..32) |i| {
        w[i] = 0;
    }
    w[32] = 250; // space
    w[33] = 333; // exclam
    w[34] = 555; // quotedbl
    w[35] = 500; // numbersign
    w[36] = 500; // dollar
    w[37] = 1000; // percent
    w[38] = 833; // ampersand
    w[39] = 278; // quotesingle
    w[40] = 333; // parenleft
    w[41] = 333; // parenright
    w[42] = 500; // asterisk
    w[43] = 570; // plus
    w[44] = 250; // comma
    w[45] = 333; // hyphen
    w[46] = 250; // period
    w[47] = 278; // slash
    w[48] = 500; // zero
    w[49] = 500; // one
    w[50] = 500; // two
    w[51] = 500; // three
    w[52] = 500; // four
    w[53] = 500; // five
    w[54] = 500; // six
    w[55] = 500; // seven
    w[56] = 500; // eight
    w[57] = 500; // nine
    w[58] = 333; // colon
    w[59] = 333; // semicolon
    w[60] = 570; // less
    w[61] = 570; // equal
    w[62] = 570; // greater
    w[63] = 500; // question
    w[64] = 930; // at
    w[65] = 722; // A
    w[66] = 667; // B
    w[67] = 722; // C
    w[68] = 722; // D
    w[69] = 667; // E
    w[70] = 611; // F
    w[71] = 778; // G
    w[72] = 778; // H
    w[73] = 389; // I
    w[74] = 500; // J
    w[75] = 778; // K
    w[76] = 667; // L
    w[77] = 944; // M
    w[78] = 722; // N
    w[79] = 778; // O
    w[80] = 611; // P
    w[81] = 778; // Q
    w[82] = 722; // R
    w[83] = 556; // S
    w[84] = 667; // T
    w[85] = 722; // U
    w[86] = 722; // V
    w[87] = 1000; // W
    w[88] = 722; // X
    w[89] = 722; // Y
    w[90] = 667; // Z
    w[91] = 333; // bracketleft
    w[92] = 278; // backslash
    w[93] = 333; // bracketright
    w[94] = 581; // asciicircum
    w[95] = 500; // underscore
    w[96] = 333; // grave
    w[97] = 500; // a
    w[98] = 556; // b
    w[99] = 444; // c
    w[100] = 556; // d
    w[101] = 444; // e
    w[102] = 333; // f
    w[103] = 500; // g
    w[104] = 556; // h
    w[105] = 278; // i
    w[106] = 333; // j
    w[107] = 556; // k
    w[108] = 278; // l
    w[109] = 833; // m
    w[110] = 556; // n
    w[111] = 500; // o
    w[112] = 556; // p
    w[113] = 556; // q
    w[114] = 444; // r
    w[115] = 389; // s
    w[116] = 333; // t
    w[117] = 556; // u
    w[118] = 500; // v
    w[119] = 722; // w
    w[120] = 500; // x
    w[121] = 500; // y
    w[122] = 444; // z
    w[123] = 394; // braceleft
    w[124] = 220; // bar
    w[125] = 394; // braceright
    w[126] = 520; // asciitilde
    w[127] = 0;
    break :blk w;
};

// -- Tests --

test "pdf name" {
    try std.testing.expectEqualStrings("Helvetica", StandardFont.helvetica.pdfName());
    try std.testing.expectEqualStrings("Courier-Bold", StandardFont.courier_bold.pdfName());
    try std.testing.expectEqualStrings("Times-Roman", StandardFont.times_roman.pdfName());
    try std.testing.expectEqualStrings("ZapfDingbats", StandardFont.zapf_dingbats.pdfName());
}

test "isFixedPitch" {
    try std.testing.expect(StandardFont.courier.isFixedPitch());
    try std.testing.expect(StandardFont.courier_bold.isFixedPitch());
    try std.testing.expect(!StandardFont.helvetica.isFixedPitch());
    try std.testing.expect(!StandardFont.times_roman.isFixedPitch());
}

test "helvetica charWidth space" {
    try std.testing.expectEqual(@as(u16, 278), StandardFont.helvetica.charWidth(' '));
}

test "helvetica charWidth A" {
    try std.testing.expectEqual(@as(u16, 667), StandardFont.helvetica.charWidth('A'));
}

test "helvetica charWidth a" {
    try std.testing.expectEqual(@as(u16, 556), StandardFont.helvetica.charWidth('a'));
}

test "helvetica charWidth 0" {
    try std.testing.expectEqual(@as(u16, 556), StandardFont.helvetica.charWidth('0'));
}

test "courier charWidth is always 600" {
    try std.testing.expectEqual(@as(u16, 600), StandardFont.courier.charWidth('A'));
    try std.testing.expectEqual(@as(u16, 600), StandardFont.courier.charWidth(' '));
    try std.testing.expectEqual(@as(u16, 600), StandardFont.courier.charWidth('z'));
}

test "textWidth" {
    // "Hello" in Helvetica: H=722 e=556 l=222 l=222 o=556 = 2278
    const w = StandardFont.helvetica.textWidth("Hello", 12.0);
    try std.testing.expectApproxEqAbs(@as(f32, 27.336), w, 0.01);
}

test "ascender and descender" {
    try std.testing.expectEqual(@as(i16, 718), StandardFont.helvetica.ascender());
    try std.testing.expectEqual(@as(i16, -207), StandardFont.helvetica.descender());
    try std.testing.expectEqual(@as(i16, 629), StandardFont.courier.ascender());
}

test "lineGap" {
    try std.testing.expectEqual(@as(i16, 33), StandardFont.helvetica.lineGap());
    try std.testing.expectEqual(@as(i16, 0), StandardFont.times_roman.lineGap());
}
