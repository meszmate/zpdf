const std = @import("std");

/// PDF token types produced by the tokenizer.
pub const Token = enum {
    number,
    string,
    hex_string,
    name,
    keyword,
    array_start,
    array_end,
    dict_start,
    dict_end,
    eof,
};

/// A PDF lexer that tokenizes raw PDF byte data.
pub const Tokenizer = struct {
    data: []const u8,
    pos: usize,
    token_start: usize,
    token_end: usize,
    current_token: Token,

    /// Initialize a tokenizer with the given PDF data.
    pub fn init(data: []const u8) Tokenizer {
        return .{
            .data = data,
            .pos = 0,
            .token_start = 0,
            .token_end = 0,
            .current_token = .eof,
        };
    }

    /// Advance to the next token and return its type.
    pub fn next(self: *Tokenizer) Token {
        self.skipWhitespaceAndComments();

        if (self.pos >= self.data.len) {
            self.current_token = .eof;
            return .eof;
        }

        const ch = self.data[self.pos];

        // Array delimiters
        if (ch == '[') {
            self.token_start = self.pos;
            self.pos += 1;
            self.token_end = self.pos;
            self.current_token = .array_start;
            return .array_start;
        }

        if (ch == ']') {
            self.token_start = self.pos;
            self.pos += 1;
            self.token_end = self.pos;
            self.current_token = .array_end;
            return .array_end;
        }

        // Dictionary delimiters
        if (ch == '<' and self.pos + 1 < self.data.len and self.data[self.pos + 1] == '<') {
            self.token_start = self.pos;
            self.pos += 2;
            self.token_end = self.pos;
            self.current_token = .dict_start;
            return .dict_start;
        }

        if (ch == '>' and self.pos + 1 < self.data.len and self.data[self.pos + 1] == '>') {
            self.token_start = self.pos;
            self.pos += 2;
            self.token_end = self.pos;
            self.current_token = .dict_end;
            return .dict_end;
        }

        // Hex string
        if (ch == '<') {
            return self.readHexString();
        }

        // Literal string
        if (ch == '(') {
            return self.readLiteralString();
        }

        // Name
        if (ch == '/') {
            return self.readName();
        }

        // Number (including negative and decimal)
        if (ch == '+' or ch == '-' or ch == '.' or (ch >= '0' and ch <= '9')) {
            return self.readNumber();
        }

        // Keyword (true, false, null, obj, endobj, stream, endstream, R, etc.)
        if (isRegularChar(ch)) {
            return self.readKeyword();
        }

        // Unknown character, skip
        self.pos += 1;
        return self.next();
    }

    /// Get the raw text value of the current token.
    pub fn getValue(self: *const Tokenizer) []const u8 {
        return self.data[self.token_start..self.token_end];
    }

    /// Get the current position in the data.
    pub fn getPos(self: *const Tokenizer) usize {
        return self.pos;
    }

    /// Set the position (for seeking).
    pub fn setPos(self: *Tokenizer, pos: usize) void {
        self.pos = pos;
    }

    fn skipWhitespaceAndComments(self: *Tokenizer) void {
        while (self.pos < self.data.len) {
            const ch = self.data[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == 0x0C or ch == 0x00) {
                self.pos += 1;
            } else if (ch == '%') {
                // Skip comment until end of line
                while (self.pos < self.data.len and self.data[self.pos] != '\n' and self.data[self.pos] != '\r') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn readHexString(self: *Tokenizer) Token {
        self.token_start = self.pos + 1; // Skip '<'
        self.pos += 1;

        while (self.pos < self.data.len and self.data[self.pos] != '>') {
            self.pos += 1;
        }

        self.token_end = self.pos;
        if (self.pos < self.data.len) self.pos += 1; // Skip '>'

        self.current_token = .hex_string;
        return .hex_string;
    }

    fn readLiteralString(self: *Tokenizer) Token {
        self.token_start = self.pos + 1; // Skip '('
        self.pos += 1;

        var depth: u32 = 1;
        while (self.pos < self.data.len and depth > 0) {
            const ch = self.data[self.pos];
            if (ch == '\\' and self.pos + 1 < self.data.len) {
                self.pos += 2; // Skip escape sequence
            } else if (ch == '(') {
                depth += 1;
                self.pos += 1;
            } else if (ch == ')') {
                depth -= 1;
                if (depth > 0) self.pos += 1;
            } else {
                self.pos += 1;
            }
        }

        self.token_end = self.pos;
        if (self.pos < self.data.len) self.pos += 1; // Skip ')'

        self.current_token = .string;
        return .string;
    }

    fn readName(self: *Tokenizer) Token {
        self.token_start = self.pos + 1; // Skip '/'
        self.pos += 1;

        while (self.pos < self.data.len and isRegularChar(self.data[self.pos])) {
            self.pos += 1;
        }

        self.token_end = self.pos;
        self.current_token = .name;
        return .name;
    }

    fn readNumber(self: *Tokenizer) Token {
        self.token_start = self.pos;

        // Skip sign
        if (self.pos < self.data.len and (self.data[self.pos] == '+' or self.data[self.pos] == '-')) {
            self.pos += 1;
        }

        var has_dot = false;
        while (self.pos < self.data.len) {
            const ch = self.data[self.pos];
            if (ch >= '0' and ch <= '9') {
                self.pos += 1;
            } else if (ch == '.' and !has_dot) {
                has_dot = true;
                self.pos += 1;
            } else {
                break;
            }
        }

        self.token_end = self.pos;
        self.current_token = .number;
        return .number;
    }

    fn readKeyword(self: *Tokenizer) Token {
        self.token_start = self.pos;

        while (self.pos < self.data.len and isRegularChar(self.data[self.pos])) {
            self.pos += 1;
        }

        self.token_end = self.pos;
        self.current_token = .keyword;
        return .keyword;
    }

    fn isRegularChar(ch: u8) bool {
        return switch (ch) {
            ' ', '\t', '\r', '\n', 0x0C, 0x00 => false, // whitespace
            '(', ')', '<', '>', '[', ']', '{', '}', '/', '%' => false, // delimiters
            else => true,
        };
    }
};

// -- Tests --

test "tokenizer: empty input" {
    var tok = Tokenizer.init("");
    try std.testing.expectEqual(Token.eof, tok.next());
}

test "tokenizer: number" {
    var tok = Tokenizer.init("42");
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqualStrings("42", tok.getValue());
}

test "tokenizer: negative number" {
    var tok = Tokenizer.init("-3.14");
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqualStrings("-3.14", tok.getValue());
}

test "tokenizer: string" {
    var tok = Tokenizer.init("(Hello World)");
    try std.testing.expectEqual(Token.string, tok.next());
    try std.testing.expectEqualStrings("Hello World", tok.getValue());
}

test "tokenizer: nested string" {
    var tok = Tokenizer.init("(Hello (World))");
    try std.testing.expectEqual(Token.string, tok.next());
    try std.testing.expectEqualStrings("Hello (World)", tok.getValue());
}

test "tokenizer: hex string" {
    var tok = Tokenizer.init("<48656C6C6F>");
    try std.testing.expectEqual(Token.hex_string, tok.next());
    try std.testing.expectEqualStrings("48656C6C6F", tok.getValue());
}

test "tokenizer: name" {
    var tok = Tokenizer.init("/Type");
    try std.testing.expectEqual(Token.name, tok.next());
    try std.testing.expectEqualStrings("Type", tok.getValue());
}

test "tokenizer: array" {
    var tok = Tokenizer.init("[1 2 3]");
    try std.testing.expectEqual(Token.array_start, tok.next());
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqual(Token.array_end, tok.next());
}

test "tokenizer: dict" {
    var tok = Tokenizer.init("<< /Type /Page >>");
    try std.testing.expectEqual(Token.dict_start, tok.next());
    try std.testing.expectEqual(Token.name, tok.next());
    try std.testing.expectEqualStrings("Type", tok.getValue());
    try std.testing.expectEqual(Token.name, tok.next());
    try std.testing.expectEqualStrings("Page", tok.getValue());
    try std.testing.expectEqual(Token.dict_end, tok.next());
}

test "tokenizer: keyword" {
    var tok = Tokenizer.init("true false null");
    try std.testing.expectEqual(Token.keyword, tok.next());
    try std.testing.expectEqualStrings("true", tok.getValue());
    try std.testing.expectEqual(Token.keyword, tok.next());
    try std.testing.expectEqualStrings("false", tok.getValue());
    try std.testing.expectEqual(Token.keyword, tok.next());
    try std.testing.expectEqualStrings("null", tok.getValue());
}

test "tokenizer: comments skipped" {
    var tok = Tokenizer.init("% this is a comment\n42");
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqualStrings("42", tok.getValue());
}

test "tokenizer: indirect object reference" {
    var tok = Tokenizer.init("10 0 R");
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqualStrings("10", tok.getValue());
    try std.testing.expectEqual(Token.number, tok.next());
    try std.testing.expectEqualStrings("0", tok.getValue());
    try std.testing.expectEqual(Token.keyword, tok.next());
    try std.testing.expectEqualStrings("R", tok.getValue());
}
