const std = @import("std");

pub const base_url: []const u8 = "https://cdn.discordapp.com";

pub const ImageFormat = enum {
    png,
    jpg,
    jpeg,
    webp,
    gif,

    pub fn extension(self: ImageFormat) []const u8 {
        return @tagName(self);
    }
};

pub const ImageOptions = struct {
    size: ?u16 = null,
    format: ?ImageFormat = null,
    force_static: bool = false,
};

fn resolveFormat(hash: []const u8, options: ImageOptions) []const u8 {
    if (options.format) |f| {
        return f.extension();
    }
    if (!options.force_static and std.mem.startsWith(u8, hash, "a_")) {
        return "gif";
    }
    return "png";
}

fn sizedUrl(
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}" ++ fmt, .{base_url} ++ args);
}

pub fn avatar(
    allocator: std.mem.Allocator,
    user_id: []const u8,
    avatar_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(avatar_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/avatars/{s}/{s}.{s}?size={d}", .{ user_id, avatar_hash, ext, s });
    }
    return sizedUrl(allocator, "/avatars/{s}/{s}.{s}", .{ user_id, avatar_hash, ext });
}

pub fn defaultAvatar(
    allocator: std.mem.Allocator,
    index: u32,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/embed/avatars/{d}.png", .{ base_url, index });
}

pub fn guildMemberAvatar(
    allocator: std.mem.Allocator,
    guild_id: []const u8,
    user_id: []const u8,
    avatar_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(avatar_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/guilds/{s}/users/{s}/avatars/{s}.{s}?size={d}", .{ guild_id, user_id, avatar_hash, ext, s });
    }
    return sizedUrl(allocator, "/guilds/{s}/users/{s}/avatars/{s}.{s}", .{ guild_id, user_id, avatar_hash, ext });
}

pub fn banner(
    allocator: std.mem.Allocator,
    id: []const u8,
    banner_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(banner_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/banners/{s}/{s}.{s}?size={d}", .{ id, banner_hash, ext, s });
    }
    return sizedUrl(allocator, "/banners/{s}/{s}.{s}", .{ id, banner_hash, ext });
}

pub fn guildIcon(
    allocator: std.mem.Allocator,
    guild_id: []const u8,
    icon_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(icon_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/icons/{s}/{s}.{s}?size={d}", .{ guild_id, icon_hash, ext, s });
    }
    return sizedUrl(allocator, "/icons/{s}/{s}.{s}", .{ guild_id, icon_hash, ext });
}

pub fn guildSplash(
    allocator: std.mem.Allocator,
    guild_id: []const u8,
    splash_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(splash_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/splashes/{s}/{s}.{s}?size={d}", .{ guild_id, splash_hash, ext, s });
    }
    return sizedUrl(allocator, "/splashes/{s}/{s}.{s}", .{ guild_id, splash_hash, ext });
}

pub fn guildDiscoverySplash(
    allocator: std.mem.Allocator,
    guild_id: []const u8,
    splash_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(splash_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/discovery-splashes/{s}/{s}.{s}?size={d}", .{ guild_id, splash_hash, ext, s });
    }
    return sizedUrl(allocator, "/discovery-splashes/{s}/{s}.{s}", .{ guild_id, splash_hash, ext });
}

pub fn roleIcon(
    allocator: std.mem.Allocator,
    role_id: []const u8,
    icon_hash: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = resolveFormat(icon_hash, options);
    if (options.size) |s| {
        return sizedUrl(allocator, "/role-icons/{s}/{s}.{s}?size={d}", .{ role_id, icon_hash, ext, s });
    }
    return sizedUrl(allocator, "/role-icons/{s}/{s}.{s}", .{ role_id, icon_hash, ext });
}

pub fn emoji(
    allocator: std.mem.Allocator,
    emoji_id: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = if (options.format) |f| f.extension() else "png";
    if (options.size) |s| {
        return sizedUrl(allocator, "/emojis/{s}.{s}?size={d}", .{ emoji_id, ext, s });
    }
    return sizedUrl(allocator, "/emojis/{s}.{s}", .{ emoji_id, ext });
}

pub fn sticker(
    allocator: std.mem.Allocator,
    sticker_id: []const u8,
    options: ImageOptions,
) ![]u8 {
    const ext = if (options.format) |f| f.extension() else "png";
    if (options.size) |s| {
        return sizedUrl(allocator, "/stickers/{s}.{s}?size={d}", .{ sticker_id, ext, s });
    }
    return sizedUrl(allocator, "/stickers/{s}.{s}", .{ sticker_id, ext });
}

pub const guildBanner = banner;

pub const CDN = struct {
    pub const avatar = @This().avatar;
    pub const defaultAvatar = @This().defaultAvatar;
    pub const guildMemberAvatar = @This().guildMemberAvatar;
    pub const banner = @This().banner;
    pub const guildBanner = @This().banner;
    pub const guildIcon = @This().guildIcon;
    pub const guildSplash = @This().guildSplash;
    pub const guildDiscoverySplash = @This().guildDiscoverySplash;
    pub const roleIcon = @This().roleIcon;
    pub const emoji = @This().emoji;
    pub const sticker = @This().sticker;
};
