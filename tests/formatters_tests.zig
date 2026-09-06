const std = @import("std");
const discord = @import("discord-zig");

test "markdown mentions" {
    const allocator = std.testing.allocator;

    const u = try discord.userMention(allocator, "123456789");
    defer allocator.free(u);
    try std.testing.expectEqualStrings("<@123456789>", u);

    const c = try discord.channelMention(allocator, "987654321");
    defer allocator.free(c);
    try std.testing.expectEqualStrings("<#987654321>", c);

    const r = try discord.roleMention(allocator, "1122334455");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("<@&1122334455>", r);
}

test "markdown time and timestamps" {
    const allocator = std.testing.allocator;

    const t1 = try discord.time(allocator, 1620000000, null);
    defer allocator.free(t1);
    try std.testing.expectEqualStrings("<t:1620000000>", t1);

    const t2 = try discord.time(allocator, 1620000000, discord.TimestampStyles.RelativeTime);
    defer allocator.free(t2);
    try std.testing.expectEqualStrings("<t:1620000000:R>", t2);

    const t3 = try discord.time(allocator, 1620000000, discord.TimestampStyles.ShortTime);
    defer allocator.free(t3);
    try std.testing.expectEqualStrings("<t:1620000000:t>", t3);
}

test "markdown styles and formatting" {
    const allocator = std.testing.allocator;

    const b = try discord.bold(allocator, "Hello");
    defer allocator.free(b);
    try std.testing.expectEqualStrings("**Hello**", b);

    const it = try discord.italic(allocator, "World");
    defer allocator.free(it);
    try std.testing.expectEqualStrings("*World*", it);

    const s = try discord.strikethrough(allocator, "Striked");
    defer allocator.free(s);
    try std.testing.expectEqualStrings("~~Striked~~", s);

    const u = try discord.underline(allocator, "Underlined");
    defer allocator.free(u);
    try std.testing.expectEqualStrings("__Underlined__", u);

    const sp = try discord.spoiler(allocator, "Secret");
    defer allocator.free(sp);
    try std.testing.expectEqualStrings("||Secret||", sp);

    const q = try discord.quote(allocator, "Quote text");
    defer allocator.free(q);
    try std.testing.expectEqualStrings("> Quote text", q);

    const bq = try discord.blockQuote(allocator, "Block quote text");
    defer allocator.free(bq);
    try std.testing.expectEqualStrings(">>> Block quote text", bq);

    const ic = try discord.inlineCode(allocator, "const x = 1;");
    defer allocator.free(ic);
    try std.testing.expectEqualStrings("`const x = 1;`", ic);

    const cb1 = try discord.codeBlock(allocator, "zig", "const x: u32 = 42;");
    defer allocator.free(cb1);
    try std.testing.expectEqualStrings("```zig\nconst x: u32 = 42;```", cb1);

    const cb2 = try discord.codeBlock(allocator, null, "plain code");
    defer allocator.free(cb2);
    try std.testing.expectEqualStrings("```\nplain code```", cb2);

    const hl = try discord.hyperlink(allocator, "Discord", "https://discord.com");
    defer allocator.free(hl);
    try std.testing.expectEqualStrings("[Discord](https://discord.com)", hl);

    const hle = try discord.hideLinkEmbed(allocator, "https://discord.com");
    defer allocator.free(hle);
    try std.testing.expectEqualStrings("<https://discord.com>", hle);

    const st = try discord.subtext(allocator, "Small text");
    defer allocator.free(st);
    try std.testing.expectEqualStrings("-# Small text", st);

    const em1 = try discord.formatEmoji(allocator, "12345", "blob", false);
    defer allocator.free(em1);
    try std.testing.expectEqualStrings("<:blob:12345>", em1);

    const em2 = try discord.formatEmoji(allocator, "67890", "party", true);
    defer allocator.free(em2);
    try std.testing.expectEqualStrings("<a:party:67890>", em2);
}

test "formatIso8601 produces valid ISO strings" {
    var buf: [32]u8 = undefined;

    const s0 = discord.formatIso8601(0, &buf);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", s0);

    const s1 = discord.formatIso8601(1622924906, &buf);
    try std.testing.expectEqualStrings("2021-06-05T20:28:26Z", s1);

    const s_neg = discord.formatIso8601(-1, &buf);
    try std.testing.expectEqualStrings("", s_neg);
}

test "real clock functions" {
    const io = std.testing.io;
    const sec = discord.util.realNowSec(io);
    const ms = discord.util.realNowMs(io);

    try std.testing.expect(sec > 1700000000);
    try std.testing.expect(ms > 1700000000000);
}




