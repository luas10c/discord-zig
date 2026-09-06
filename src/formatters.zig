const std = @import("std");

pub const TimestampStyles = struct {
    pub const ShortTime: u8 = 't';
    pub const LongTime: u8 = 'T';
    pub const ShortDate: u8 = 'd';
    pub const LongDate: u8 = 'D';
    pub const ShortDateTime: u8 = 'f';
    pub const LongDateTime: u8 = 'F';
    pub const RelativeTime: u8 = 'R';
};

pub fn userMention(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "<@{s}>", .{id});
}

pub fn channelMention(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "<#{s}>", .{id});
}

pub fn roleMention(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "<@&{s}>", .{id});
}

pub fn time(allocator: std.mem.Allocator, timestamp_seconds: i64, style: ?u8) ![]u8 {
    if (style) |s| {
        return std.fmt.allocPrint(allocator, "<t:{d}:{c}>", .{ timestamp_seconds, s });
    }
    return std.fmt.allocPrint(allocator, "<t:{d}>", .{timestamp_seconds});
}

pub fn formatIso8601(epoch_seconds: i64, buf: *[32]u8) []const u8 {
    if (epoch_seconds < 0) return "";
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch_seconds) };
    const day = epoch.getEpochDay();
    const day_secs = epoch.getDaySeconds();
    const ymd = day.calculateYearDay();
    const md = ymd.calculateMonthDay();

    return std.fmt.bufPrint(
        buf,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            ymd.year,
            md.month.numeric(),
            md.day_index + 1,
            day_secs.getHoursIntoDay(),
            day_secs.getMinutesIntoHour(),
            day_secs.getSecondsIntoMinute(),
        },
    ) catch "";
}


pub fn bold(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "**{s}**", .{text});
}

pub fn italic(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "*{s}*", .{text});
}

pub fn strikethrough(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "~~{s}~~", .{text});
}

pub fn underline(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "__{s}__", .{text});
}

pub fn spoiler(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "||{s}||", .{text});
}

pub fn quote(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "> {s}", .{text});
}

pub fn blockQuote(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ">>> {s}", .{text});
}

pub fn inlineCode(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "`{s}`", .{text});
}

pub fn codeBlock(allocator: std.mem.Allocator, language: ?[]const u8, text: []const u8) ![]u8 {
    if (language) |lang| {
        return std.fmt.allocPrint(allocator, "```{s}\n{s}```", .{ lang, text });
    }
    return std.fmt.allocPrint(allocator, "```\n{s}```", .{text});
}

pub fn hyperlink(allocator: std.mem.Allocator, text: []const u8, url: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "[{s}]({s})", .{ text, url });
}

pub fn hideLinkEmbed(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "<{s}>", .{url});
}

pub fn subtext(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "-# {s}", .{text});
}

pub fn formatEmoji(allocator: std.mem.Allocator, id: []const u8, name: []const u8, animated: bool) ![]u8 {
    if (animated) {
        return std.fmt.allocPrint(allocator, "<a:{s}:{s}>", .{ name, id });
    }
    return std.fmt.allocPrint(allocator, "<:{s}:{s}>", .{ name, id });
}
