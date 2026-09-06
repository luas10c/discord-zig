const std = @import("std");
const discord = @import("discord-zig");

test "cdn avatar urls static and animated" {
    const allocator = std.testing.allocator;

    const static_url = try discord.cdn.avatar(allocator, "123", "abcdef123456", .{});
    defer allocator.free(static_url);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/avatars/123/abcdef123456.png", static_url);

    const anim_url = try discord.cdn.avatar(allocator, "123", "a_animatedhash", .{});
    defer allocator.free(anim_url);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/avatars/123/a_animatedhash.gif", anim_url);

    const sized_url = try discord.cdn.avatar(allocator, "123", "abcdef123456", .{ .size = 1024, .format = .webp });
    defer allocator.free(sized_url);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/avatars/123/abcdef123456.webp?size=1024", sized_url);

    const default_av = try discord.cdn.defaultAvatar(allocator, 2);
    defer allocator.free(default_av);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/embed/avatars/2.png", default_av);
}

test "cdn guild and asset urls" {
    const allocator = std.testing.allocator;

    const icon = try discord.cdn.guildIcon(allocator, "guild1", "iconhash", .{});
    defer allocator.free(icon);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/icons/guild1/iconhash.png", icon);

    const banner = try discord.cdn.guildBanner(allocator, "guild1", "bannerhash", .{ .size = 512 });
    defer allocator.free(banner);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/banners/guild1/bannerhash.png?size=512", banner);

    const emoji = try discord.cdn.emoji(allocator, "emoji1", .{});
    defer allocator.free(emoji);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/emojis/emoji1.png", emoji);

    const sticker = try discord.cdn.sticker(allocator, "sticker1", .{});
    defer allocator.free(sticker);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/stickers/sticker1.png", sticker);
}
