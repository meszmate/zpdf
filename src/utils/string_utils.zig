const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StringError = error{
    InvalidHexString,
    InvalidDateFormat,
};

/// Escape special characters for PDF literal strings.
/// Escapes: backslash, open paren, close paren, carriage return, newline, tab, backspace, form feed.
pub fn escapePdfString(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (input) |ch| {
        switch (ch) {
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '(' => try result.appendSlice(allocator, "\\("),
            ')' => try result.appendSlice(allocator, "\\)"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            0x08 => try result.appendSlice(allocator, "\\b"),
            0x0C => try result.appendSlice(allocator, "\\f"),
            else => try result.append(allocator, ch),
        }
    }

    return try result.toOwnedSlice(allocator);
}

const hex_chars = "0123456789abcdef";

/// Convert raw bytes to a hex string (lowercase).
pub fn toHexString(allocator: Allocator, data: []const u8) Allocator.Error![]u8 {
    const out = try allocator.alloc(u8, data.len * 2);
    for (data, 0..) |byte, i| {
        out[i * 2] = hex_chars[byte >> 4];
        out[i * 2 + 1] = hex_chars[byte & 0x0F];
    }
    return out;
}

fn hexVal(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

/// Decode a hex string to raw bytes. Whitespace is ignored. Odd-length input
/// is treated as if the last nibble were 0 (per PDF spec).
pub fn fromHexString(allocator: Allocator, hex: []const u8) (Allocator.Error || StringError)![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    var nibble_buf: ?u4 = null;
    for (hex) |ch| {
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') continue;

        const val = hexVal(ch) orelse return StringError.InvalidHexString;
        if (nibble_buf) |high| {
            try result.append(allocator, @as(u8, high) << 4 | val);
            nibble_buf = null;
        } else {
            nibble_buf = val;
        }
    }

    // Trailing nibble: pad with 0
    if (nibble_buf) |high| {
        try result.append(allocator, @as(u8, high) << 4);
    }

    return try result.toOwnedSlice(allocator);
}

/// Format a Unix timestamp as a PDF date string: D:YYYYMMDDHHmmSS+00'00'
/// The output is always in UTC.
pub fn formatPdfDate(allocator: Allocator, timestamp: i64) Allocator.Error![]u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(@as(u64, @bitCast(timestamp))) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year = year_day.year;
    const month = @intFromEnum(month_day.month);
    const day = month_day.day_index + 1;
    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();

    return try std.fmt.allocPrint(allocator, "D:{d:0>4}{d:0>2}{d:0>2}{d:0>2}{d:0>2}{d:0>2}+00'00'", .{
        @as(u32, @intCast(year)),
        @as(u32, month),
        @as(u32, day),
        @as(u32, hour),
        @as(u32, minute),
        @as(u32, second),
    });
}

/// Parse a PDF date string (D:YYYYMMDDHHmmSS...) to a Unix timestamp.
/// Returns null if the format is invalid. Timezone offsets are applied.
pub fn parsePdfDate(date_str: []const u8) ?i64 {
    var s = date_str;

    // Strip optional "D:" prefix
    if (s.len >= 2 and s[0] == 'D' and s[1] == ':') {
        s = s[2..];
    }

    if (s.len < 4) return null;

    const year = parseDigits(s[0..4]) orelse return null;
    if (year < 1970) return null;

    var month: u32 = 1;
    var day: u32 = 1;
    var hour: u32 = 0;
    var minute: u32 = 0;
    var second: u32 = 0;

    if (s.len >= 6) month = parseDigits2(s[4..6]) orelse return null;
    if (s.len >= 8) day = parseDigits2(s[6..8]) orelse return null;
    if (s.len >= 10) hour = parseDigits2(s[8..10]) orelse return null;
    if (s.len >= 12) minute = parseDigits2(s[10..12]) orelse return null;
    if (s.len >= 14) second = parseDigits2(s[12..14]) orelse return null;

    if (month < 1 or month > 12) return null;
    if (day < 1 or day > 31) return null;
    if (hour > 23) return null;
    if (minute > 59) return null;
    if (second > 59) return null;

    // Parse timezone offset if present
    var tz_offset_seconds: i64 = 0;
    if (s.len > 14) {
        const tz = s[14..];
        if (tz.len >= 1) {
            const sign: i64 = switch (tz[0]) {
                '+' => 1,
                '-' => -1,
                'Z' => 0,
                else => return null,
            };
            if (sign != 0 and tz.len >= 3) {
                const tz_hours = parseDigits2(tz[1..3]) orelse return null;
                var tz_minutes: u32 = 0;
                var min_start: usize = 3;
                if (min_start < tz.len and tz[min_start] == '\'') min_start += 1;
                if (min_start + 2 <= tz.len) {
                    tz_minutes = parseDigits2(tz[min_start .. min_start + 2]) orelse return null;
                }
                tz_offset_seconds = sign * (@as(i64, tz_hours) * 3600 + @as(i64, tz_minutes) * 60);
            }
        }
    }

    // Convert to epoch seconds
    const epoch_year: u32 = 1970;
    var total_days: i64 = 0;

    var y: u32 = epoch_year;
    while (y < year) : (y += 1) {
        total_days += if (isLeapYear(y)) @as(i64, 366) else @as(i64, 365);
    }

    const days_in_months = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var m: u32 = 1;
    while (m < month) : (m += 1) {
        total_days += days_in_months[m - 1];
        if (m == 2 and isLeapYear(year)) total_days += 1;
    }

    total_days += day - 1;

    const total_seconds = total_days * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);

    // Subtract timezone offset (UTC = local - offset)
    return total_seconds - tz_offset_seconds;
}

fn isLeapYear(year: u32) bool {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    if (year % 400 != 0) return false;
    return true;
}

fn parseDigits(s: []const u8) ?u32 {
    var val: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return null;
        val = val * 10 + (ch - '0');
    }
    return val;
}

fn parseDigits2(s: []const u8) ?u32 {
    if (s.len < 2) return null;
    return parseDigits(s[0..2]);
}

test "escapePdfString: basic escapes" {
    const result = try escapePdfString(std.testing.allocator, "hello (world) \\ end");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "hello \\(world\\) \\\\ end", result);
}

test "escapePdfString: control chars" {
    const result = try escapePdfString(std.testing.allocator, "a\nb\rc\td");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "a\\nb\\rc\\td", result);
}

test "escapePdfString: no escaping needed" {
    const result = try escapePdfString(std.testing.allocator, "simple");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "simple", result);
}

test "toHexString" {
    const result = try toHexString(std.testing.allocator, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "deadbeef", result);
}

test "fromHexString" {
    const result = try fromHexString(std.testing.allocator, "DEADBEEF");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, result);
}

test "fromHexString: with whitespace" {
    const result = try fromHexString(std.testing.allocator, "DE AD BE EF");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, result);
}

test "fromHexString: odd length trailing nibble" {
    const result = try fromHexString(std.testing.allocator, "ABC");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAB, 0xC0 }, result);
}

test "fromHexString: invalid char" {
    const result = fromHexString(std.testing.allocator, "ZZZZ");
    try std.testing.expectError(StringError.InvalidHexString, result);
}

test "hex roundtrip" {
    const data = &[_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF };
    const hex = try toHexString(std.testing.allocator, data);
    defer std.testing.allocator.free(hex);
    const back = try fromHexString(std.testing.allocator, hex);
    defer std.testing.allocator.free(back);
    try std.testing.expectEqualSlices(u8, data, back);
}

test "formatPdfDate: epoch" {
    const result = try formatPdfDate(std.testing.allocator, 0);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "D:19700101000000+00'00'", result);
}

test "formatPdfDate: known date" {
    const result = try formatPdfDate(std.testing.allocator, 1705321845);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "D:20240115123045+00'00'", result);
}

test "parsePdfDate: basic" {
    const ts = parsePdfDate("D:20240115123045+00'00'");
    try std.testing.expectEqual(@as(?i64, 1705321845), ts);
}

test "parsePdfDate: without prefix" {
    const ts = parsePdfDate("20240115123045");
    try std.testing.expectEqual(@as(?i64, 1705321845), ts);
}

test "parsePdfDate: year only" {
    const ts = parsePdfDate("D:2024");
    try std.testing.expect(ts != null);
}

test "parsePdfDate: invalid" {
    try std.testing.expectEqual(@as(?i64, null), parsePdfDate("D:abc"));
    try std.testing.expectEqual(@as(?i64, null), parsePdfDate(""));
    try std.testing.expectEqual(@as(?i64, null), parsePdfDate("D:"));
}

test "parsePdfDate: with timezone" {
    const ts = parsePdfDate("D:20240115180045+05'30'");
    try std.testing.expectEqual(@as(?i64, 1705321845), ts);
}
