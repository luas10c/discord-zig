const std = @import("std");

fn asOwnedString(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => |s| try allocator.dupe(u8, s),
        .integer => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        else => error.UnexpectedToken,
    };
}

fn asOwnedOptString(allocator: std.mem.Allocator, v: std.json.Value) !?[]const u8 {
    return switch (v) {
        .null => null,
        .string => |s| try allocator.dupe(u8, s),
        .integer => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        else => error.UnexpectedToken,
    };
}

fn asOwnedStringOrEmpty(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    return switch (v) {
        .null => "",
        .string => |s| try allocator.dupe(u8, s),
        .integer => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        else => error.UnexpectedToken,
    };
}

fn asOwnedStringOrZero(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    return switch (v) {
        .null => "0",
        .string => |s| try allocator.dupe(u8, s),
        .integer => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        else => error.UnexpectedToken,
    };
}

fn asOptInt(comptime T: type, v: std.json.Value) !?T {
    return switch (v) {
        .null => null,
        .integer => |n| blk: {
            if (n < 0 or n > std.math.maxInt(T)) return error.Overflow;
            break :blk @as(T, @intCast(n));
        },
        .string => |s| std.fmt.parseInt(T, s, 10) catch error.UnexpectedToken,
        else => error.UnexpectedToken,
    };
}

fn asIntOrDefault(comptime T: type, v: std.json.Value, default_val: T) !T {
    return switch (v) {
        .null => default_val,
        .integer => |n| blk: {
            if (n < 0 or n > std.math.maxInt(T)) return error.Overflow;
            break :blk @as(T, @intCast(n));
        },
        .string => |s| std.fmt.parseInt(T, s, 10) catch default_val,
        else => error.UnexpectedToken,
    };
}

fn asBoolOrDefault(v: std.json.Value, default_val: bool) !bool {
    return switch (v) {
        .null => default_val,
        .bool => |b| b,
        else => error.UnexpectedToken,
    };
}

pub const User = struct {
    id: []const u8 = "",
    username: []const u8 = "",
    discriminator: []const u8 = "0",
    global_name: ?[]const u8 = null,
    avatar: ?[]const u8 = null,
    bot: bool = false,
    system: bool = false,

    pub fn tag(self: User, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}#{s}", .{ self.username, self.discriminator });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !User {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !User {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = User{};
        if (obj.get("id")) |v| out.id = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("username")) |v| out.username = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("discriminator")) |v| out.discriminator = try asOwnedStringOrZero(allocator, v);
        if (obj.get("global_name")) |v| out.global_name = try asOwnedOptString(allocator, v);
        if (obj.get("avatar")) |v| out.avatar = try asOwnedOptString(allocator, v);
        if (obj.get("bot")) |v| out.bot = try asBoolOrDefault(v, false);
        if (obj.get("system")) |v| out.system = try asBoolOrDefault(v, false);
        return out;
    }
};

pub const GuildMember = struct {
    user: ?User = null,
    nick: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    joined_at: []const u8 = "",
    guild_id: []const u8 = "",

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !GuildMember {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !GuildMember {
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = GuildMember{};
        if (obj.get("user")) |v| {
            out.user = switch (v) {
                .null => null,
                .object => try User.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("nick")) |v| out.nick = try asOwnedOptString(allocator, v);
        if (obj.get("roles")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const roles_arr = try allocator.alloc([]const u8, a.items.len);
                    for (a.items, 0..) |item, i| {
                        roles_arr[i] = try asOwnedStringOrEmpty(allocator, item);
                    }
                    out.roles = roles_arr;
                },
                else => return error.UnexpectedToken,
            }
        }
        if (obj.get("joined_at")) |v| out.joined_at = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("guild_id")) |v| out.guild_id = try asOwnedStringOrEmpty(allocator, v);
        return out;
    }
};

pub const Guild = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    description: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    owner_id: []const u8 = "",
    member_count: u64 = 0,
};

pub const ChannelType = enum(u8) {
    GuildText = 0,
    DM = 1,
    GuildVoice = 2,
    GroupDM = 3,
    GuildCategory = 4,
    GuildAnnouncement = 5,
    AnnouncementThread = 10,
    PublicThread = 11,
    PrivateThread = 12,
    GuildStageVoice = 13,
    GuildDirectory = 14,
    GuildForum = 15,
    GuildMedia = 16,
    _,

    // Discord.js 14.22.1 aliases
    pub const GuildNews: ChannelType = .GuildAnnouncement;
    pub const GuildNewsThread: ChannelType = .AnnouncementThread;
    pub const GuildPublicThread: ChannelType = .PublicThread;
    pub const GuildPrivateThread: ChannelType = .PrivateThread;

    // Zig snake_case aliases for backwards compatibility
    pub const guild_text: ChannelType = .GuildText;
    pub const dm: ChannelType = .DM;
    pub const guild_voice: ChannelType = .GuildVoice;
    pub const group_dm: ChannelType = .GroupDM;
    pub const guild_category: ChannelType = .GuildCategory;
    pub const guild_announcement: ChannelType = .GuildAnnouncement;
    pub const announcement_thread: ChannelType = .AnnouncementThread;
    pub const public_thread: ChannelType = .PublicThread;
    pub const private_thread: ChannelType = .PrivateThread;
    pub const guild_stage_voice: ChannelType = .GuildStageVoice;
    pub const guild_directory: ChannelType = .GuildDirectory;
    pub const guild_forum: ChannelType = .GuildForum;
    pub const guild_media: ChannelType = .GuildMedia;
};

pub const OverwriteType = enum(u8) {
    role = 0,
    member = 1,
    _,
};

pub const PermissionOverwrite = struct {
    id: []const u8 = "",
    @"type": u8 = 0,
    allow: []const u8 = "0",
    deny: []const u8 = "0",
};

pub const Channel = struct {
    id: []const u8,
    channel_type: ChannelType = .GuildText,
    guild_id: ?[]const u8 = null,
    name: ?[]const u8 = null,
    topic: ?[]const u8 = null,
    permission_overwrites: []const PermissionOverwrite = &.{},

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Channel {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = Channel{ .id = "" };
        if (obj.get("id")) |v| out.id = try asOwnedString(allocator, v);
        const type_val = obj.get("type") orelse obj.get("channel_type");
        if (type_val) |v| {
            const n = switch (v) {
                .integer => |i| i,
                else => return error.UnexpectedToken,
            };
            if (n < 0 or n > std.math.maxInt(u8)) return error.Overflow;
            out.channel_type = @enumFromInt(@as(u8, @intCast(n)));
        }
        if (obj.get("guild_id")) |v| out.guild_id = try asOwnedOptString(allocator, v);
        if (obj.get("name")) |v| out.name = try asOwnedOptString(allocator, v);
        if (obj.get("topic")) |v| out.topic = try asOwnedOptString(allocator, v);
        if (obj.get("permission_overwrites")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const overwrites = try allocator.alloc(PermissionOverwrite, a.items.len);
                    for (a.items, 0..) |item, i| {
                        const o = switch (item) {
                            .object => |o| o,
                            else => return error.UnexpectedToken,
                        };
                        const type_num = switch (o.get("type") orelse return error.UnexpectedToken) {
                            .integer => |n| n,
                            else => return error.UnexpectedToken,
                        };
                        if (type_num < 0 or type_num > std.math.maxInt(u8)) return error.Overflow;
                        overwrites[i] = .{
                            .id = try asOwnedString(allocator, o.get("id") orelse return error.UnexpectedToken),
                            .@"type" = @as(u8, @intCast(type_num)),
                            .allow = try asOwnedString(allocator, o.get("allow") orelse .{ .string = "0" }),
                            .deny = try asOwnedString(allocator, o.get("deny") orelse .{ .string = "0" }),
                        };
                    }
                    out.permission_overwrites = overwrites;
                },
                else => return error.UnexpectedToken,
            }
        }
        return out;
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Channel {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }
};

pub const Attachment = struct {
    id: []const u8 = "",
    filename: []const u8 = "",
    url: []const u8 = "",

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Attachment {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Attachment {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = Attachment{};
        if (obj.get("id")) |v| out.id = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("filename")) |v| out.filename = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("url")) |v| out.url = try asOwnedStringOrEmpty(allocator, v);
        return out;
    }
};

pub const Embed = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    color: ?u32 = null,
    author: ?EmbedAuthor = null,
    footer: ?EmbedFooter = null,
    image: ?EmbedImage = null,
    thumbnail: ?EmbedImage = null,
    fields: []const EmbedField = &.{},
    timestamp: ?[]const u8 = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Embed {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Embed {
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = Embed{};
        if (obj.get("title")) |v| out.title = try asOwnedOptString(allocator, v);
        if (obj.get("description")) |v| out.description = try asOwnedOptString(allocator, v);
        if (obj.get("url")) |v| out.url = try asOwnedOptString(allocator, v);
        if (obj.get("color")) |v| out.color = try asOptInt(u32, v);
        if (obj.get("timestamp")) |v| out.timestamp = try asOwnedOptString(allocator, v);
        if (obj.get("author")) |v| {
            out.author = switch (v) {
                .null => null,
                .object => try EmbedAuthor.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("footer")) |v| {
            out.footer = switch (v) {
                .null => null,
                .object => try EmbedFooter.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("image")) |v| {
            out.image = switch (v) {
                .null => null,
                .object => try EmbedImage.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("thumbnail")) |v| {
            out.thumbnail = switch (v) {
                .null => null,
                .object => try EmbedImage.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("fields")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const fields_arr = try allocator.alloc(EmbedField, a.items.len);
                    for (a.items, 0..) |item, i| {
                        fields_arr[i] = try EmbedField.jsonParseFromValue(allocator, item, options);
                    }
                    out.fields = fields_arr;
                },
                else => return error.UnexpectedToken,
            }
        }
        return out;
    }

    pub fn jsonStringify(self: Embed, jw: anytype) !void {
        try jw.beginObject();
        if (self.title) |t| {
            try jw.objectField("title");
            try jw.write(t);
        }
        if (self.description) |d| {
            try jw.objectField("description");
            try jw.write(d);
        }
        if (self.url) |u| {
            try jw.objectField("url");
            try jw.write(u);
        }
        if (self.timestamp) |ts| {
            try jw.objectField("timestamp");
            try jw.write(ts);
        }
        if (self.color) |c| {
            try jw.objectField("color");
            try jw.write(c);
        }
        if (self.footer) |f| {
            try jw.objectField("footer");
            try jw.write(f);
        }
        if (self.image) |img| {
            try jw.objectField("image");
            try jw.write(img);
        }
        if (self.thumbnail) |th| {
            try jw.objectField("thumbnail");
            try jw.write(th);
        }
        if (self.author) |a| {
            try jw.objectField("author");
            try jw.write(a);
        }
        if (self.fields.len > 0) {
            try jw.objectField("fields");
            try jw.write(self.fields);
        }
        try jw.endObject();
    }
};

pub const EmbedAuthor = struct {
    name: []const u8 = "",
    url: ?[]const u8 = null,
    icon_url: ?[]const u8 = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !EmbedAuthor {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !EmbedAuthor {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = EmbedAuthor{};
        if (obj.get("name")) |v| out.name = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("url")) |v| out.url = try asOwnedOptString(allocator, v);
        if (obj.get("icon_url")) |v| out.icon_url = try asOwnedOptString(allocator, v);
        return out;
    }

    pub fn jsonStringify(self: EmbedAuthor, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("name");
        try jw.write(self.name);
        if (self.url) |u| {
            try jw.objectField("url");
            try jw.write(u);
        }
        if (self.icon_url) |i| {
            try jw.objectField("icon_url");
            try jw.write(i);
        }
        try jw.endObject();
    }
};

pub const EmbedFooter = struct {
    text: []const u8 = "",
    icon_url: ?[]const u8 = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !EmbedFooter {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !EmbedFooter {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = EmbedFooter{};
        if (obj.get("text")) |v| out.text = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("icon_url")) |v| out.icon_url = try asOwnedOptString(allocator, v);
        return out;
    }

    pub fn jsonStringify(self: EmbedFooter, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("text");
        try jw.write(self.text);
        if (self.icon_url) |i| {
            try jw.objectField("icon_url");
            try jw.write(i);
        }
        try jw.endObject();
    }
};

pub const EmbedImage = struct {
    url: []const u8 = "",

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !EmbedImage {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !EmbedImage {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = EmbedImage{};
        if (obj.get("url")) |v| out.url = try asOwnedStringOrEmpty(allocator, v);
        return out;
    }

    pub fn jsonStringify(self: EmbedImage, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("url");
        try jw.write(self.url);
        try jw.endObject();
    }
};

pub const EmbedField = struct {
    name: []const u8 = "",
    value: []const u8 = "",
    @"inline": bool = false,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !EmbedField {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !EmbedField {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = EmbedField{};
        if (obj.get("name")) |v| out.name = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("value")) |v| out.value = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("inline")) |v| out.@"inline" = try asBoolOrDefault(v, false);
        return out;
    }

    pub fn jsonStringify(self: EmbedField, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("name");
        try jw.write(self.name);
        try jw.objectField("value");
        try jw.write(self.value);
        if (self.@"inline") {
            try jw.objectField("inline");
            try jw.write(true);
        }
        try jw.endObject();
    }
};

pub const Message = struct {
    id: []const u8 = "",
    channel_id: []const u8 = "",
    guild_id: ?[]const u8 = null,
    author: User = .{},
    content: []const u8 = "",
    timestamp: []const u8 = "",
    tts: bool = false,
    mention_everyone: bool = false,
    embeds: []const Embed = &.{},
    attachments: []const Attachment = &.{},
    flags: u32 = 0,
    poll: ?Poll = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Message {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Message {
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = Message{};
        if (obj.get("id")) |v| out.id = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("channel_id")) |v| out.channel_id = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("guild_id")) |v| out.guild_id = try asOwnedOptString(allocator, v);
        if (obj.get("author")) |v| {
            out.author = switch (v) {
                .null => .{},
                .object => try User.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("content")) |v| out.content = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("timestamp")) |v| out.timestamp = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("tts")) |v| out.tts = try asBoolOrDefault(v, false);
        if (obj.get("mention_everyone")) |v| out.mention_everyone = try asBoolOrDefault(v, false);
        if (obj.get("embeds")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const embeds_arr = try allocator.alloc(Embed, a.items.len);
                    for (a.items, 0..) |item, i| {
                        embeds_arr[i] = try Embed.jsonParseFromValue(allocator, item, options);
                    }
                    out.embeds = embeds_arr;
                },
                else => return error.UnexpectedToken,
            }
        }
        if (obj.get("attachments")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const atts_arr = try allocator.alloc(Attachment, a.items.len);
                    for (a.items, 0..) |item, i| {
                        atts_arr[i] = try Attachment.jsonParseFromValue(allocator, item, options);
                    }
                    out.attachments = atts_arr;
                },
                else => return error.UnexpectedToken,
            }
        }
        if (obj.get("flags")) |v| out.flags = try asIntOrDefault(u32, v, 0);
        if (obj.get("poll")) |v| {
            out.poll = switch (v) {
                .null => null,
                .object => try std.json.parseFromValueLeaky(Poll, allocator, v, .{ .ignore_unknown_fields = true }),
                else => return error.UnexpectedToken,
            };
        }
        return out;
    }
};

pub const GatewayBot = struct {
    url: []const u8,
    shards: u32,
    total: u32,
    remaining: u32,
    reset_after: u64,
    max_concurrency: u32,
};

pub const Ready = struct {
    session_id: []const u8 = "",
    resume_gateway_url: []const u8 = "",
    user: User = .{},
};

pub const InteractionType = enum(u8) {
    ping = 1,
    application_command = 2,
    message_component = 3,
    application_command_autocomplete = 4,
    modal_submit = 5,
    _,
};

pub const Interaction = struct {
    id: []const u8,
    application_id: []const u8,
    type: u8 = 0,
    token: []const u8 = "",
    version: u8 = 1,
    channel_id: ?[]const u8 = null,
    guild_id: ?[]const u8 = null,
    data: ?InteractionData = null,
    message: ?Message = null,
    user: ?User = null,
    member: ?GuildMember = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Interaction {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Interaction {
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = Interaction{
            .id = "",
            .application_id = "",
        };
        if (obj.get("id")) |v| out.id = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("application_id")) |v| out.application_id = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("type")) |v| out.type = try asIntOrDefault(u8, v, 0);
        if (obj.get("token")) |v| out.token = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("version")) |v| out.version = try asIntOrDefault(u8, v, 1);
        if (obj.get("channel_id")) |v| out.channel_id = try asOwnedOptString(allocator, v);
        if (obj.get("guild_id")) |v| out.guild_id = try asOwnedOptString(allocator, v);
        if (obj.get("data")) |v| {
            out.data = switch (v) {
                .null => null,
                .object => try InteractionData.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("message")) |v| {
            out.message = switch (v) {
                .null => null,
                .object => try Message.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("user")) |v| {
            out.user = switch (v) {
                .null => null,
                .object => try User.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("member")) |v| {
            out.member = switch (v) {
                .null => null,
                .object => try GuildMember.jsonParseFromValue(allocator, v, options),
                else => return error.UnexpectedToken,
            };
        }
        return out;
    }

    pub fn kind(self: Interaction) InteractionType {
        return @enumFromInt(self.type);
    }

    pub fn isPing(self: Interaction) bool {
        return self.type == @intFromEnum(InteractionType.ping);
    }

    pub fn isChatInput(self: Interaction) bool {
        if (self.type != @intFromEnum(InteractionType.application_command)) return false;
        const data = self.data orelse return true;
        return data.type == 1;
    }

    pub fn isAutocomplete(self: Interaction) bool {
        return self.type == @intFromEnum(InteractionType.application_command_autocomplete);
    }

    pub fn isComponent(self: Interaction) bool {
        return self.type == @intFromEnum(InteractionType.message_component);
    }

    pub fn isModalSubmit(self: Interaction) bool {
        return self.type == @intFromEnum(InteractionType.modal_submit);
    }
};

pub const InteractionData = struct {
    id: ?[]const u8 = null,
    name: []const u8 = "",
    type: u8 = 0,
    custom_id: ?[]const u8 = null,
    component_type: ?u8 = null,
    values: []const []const u8 = &.{},
    resolved: ?std.json.Value = null,
    options: []const InteractionOption = &.{},
    components: []const ModalRow = &.{},

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !InteractionData {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !InteractionData {
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = InteractionData{};
        if (obj.get("id")) |v| out.id = try asOwnedOptString(allocator, v);
        if (obj.get("name")) |v| out.name = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("type")) |v| out.type = try asIntOrDefault(u8, v, 0);
        if (obj.get("custom_id")) |v| out.custom_id = try asOwnedOptString(allocator, v);
        if (obj.get("component_type")) |v| out.component_type = try asOptInt(u8, v);
        if (obj.get("values")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const out_values = try allocator.alloc([]const u8, a.items.len);
                    for (a.items, 0..) |item, i| {
                        out_values[i] = try asOwnedStringOrEmpty(allocator, item);
                    }
                    out.values = out_values;
                },
                else => return error.UnexpectedToken,
            }
        }
        if (obj.get("resolved")) |v| {
            out.resolved = switch (v) {
                .null => null,
                else => v,
            };
        }
        if (obj.get("options")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const opts = try allocator.alloc(InteractionOption, a.items.len);
                    for (a.items, 0..) |item, i| {
                        opts[i] = try InteractionOption.jsonParseFromValue(allocator, item, options);
                    }
                    out.options = opts;
                },
                else => return error.UnexpectedToken,
            }
        }
        if (obj.get("components")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const rows = try allocator.alloc(ModalRow, a.items.len);
                    for (a.items, 0..) |item, i| {
                        rows[i] = try ModalRow.jsonParseFromValue(allocator, item, options);
                    }
                    out.components = rows;
                },
                else => return error.UnexpectedToken,
            }
        }
        return out;
    }

    pub fn get(self: InteractionData, name: []const u8) ?InteractionOption {
        for (self.options) |o| {
            if (std.mem.eql(u8, o.name, name)) return o;
        }
        return null;
    }

    pub fn getFocused(self: InteractionData) ?InteractionOption {
        for (self.options) |o| {
            if (o.focused) return o;
            for (o.options) |sub| {
                if (sub.focused) return sub;
            }
        }
        return null;
    }

    pub fn getTextInput(self: InteractionData, custom_id: []const u8) ?[]const u8 {
        for (self.components) |row| {
            if (row.type == @intFromEnum(ComponentType.label)) {
                const input = row.label_child orelse continue;
                if (input.type != @intFromEnum(ComponentType.text_input)) continue;
                if (std.mem.eql(u8, input.custom_id, custom_id)) return input.value;
                continue;
            }
            for (row.components) |input| {
                if (std.mem.eql(u8, input.custom_id, custom_id)) return input.value;
            }
        }
        return null;
    }

    pub fn getSelectedValues(self: InteractionData, custom_id: []const u8) ?[]const []const u8 {
        for (self.components) |row| {
            if (row.type != @intFromEnum(ComponentType.label)) continue;
            const input = row.label_child orelse continue;
            const kind: ComponentType = @enumFromInt(input.type);
            switch (kind) {
                .string_select, .user_select, .role_select, .mentionable_select, .channel_select => {},
                else => continue,
            }
            if (!std.mem.eql(u8, input.custom_id, custom_id)) continue;
            return input.values;
        }
        return null;
    }
};

pub const ModalRow = struct {
    type: u8 = 1,
    components: []const ModalInput = &.{},
    label_child: ?ModalInput = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !ModalRow {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !ModalRow {
        _ = options;
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = ModalRow{};
        if (obj.get("type")) |v| {
            out.type = switch (v) {
                .integer => |n| blk: {
                    if (n < 0 or n > std.math.maxInt(u8)) return error.Overflow;
                    break :blk @as(u8, @intCast(n));
                },
                .null => 1,
                else => return error.UnexpectedToken,
            };
        }
        if (obj.get("components")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const inputs = try allocator.alloc(ModalInput, a.items.len);
                    for (a.items, 0..) |item, i| {
                        inputs[i] = try innerModalInput(allocator, item);
                    }
                    out.components = inputs;
                },
                else => return error.UnexpectedToken,
            }
        }
        if (obj.get("component")) |v| {
            switch (v) {
                .null => {},
                .object => {
                    out.label_child = try innerModalInput(allocator, v);
                },
                else => return error.UnexpectedToken,
            }
        }
        return out;
    }
};

fn innerModalInput(allocator: std.mem.Allocator, source: std.json.Value) !ModalInput {
    const obj = switch (source) {
        .object => |o| o,
        else => return error.UnexpectedToken,
    };
    var out = ModalInput{};
    if (obj.get("type")) |v| {
        out.type = switch (v) {
            .integer => |n| blk: {
                if (n < 0 or n > std.math.maxInt(u8)) return error.Overflow;
                break :blk @as(u8, @intCast(n));
            },
            .null => 4,
            else => return error.UnexpectedToken,
        };
    }
    if (obj.get("custom_id")) |v| {
        out.custom_id = try asOwnedStringOrEmpty(allocator, v);
    }
    if (obj.get("value")) |v| {
        out.value = try asOwnedStringOrEmpty(allocator, v);
    }
    if (obj.get("values")) |v| {
        switch (v) {
            .null => {},
            .array => |a| {
                const out_values = try allocator.alloc([]const u8, a.items.len);
                for (a.items, 0..) |item, i| {
                    out_values[i] = try asOwnedStringOrEmpty(allocator, item);
                }
                out.values = out_values;
            },
            else => return error.UnexpectedToken,
        }
    }
    return out;
}

pub const ModalInput = struct {
    type: u8 = 4,
    custom_id: []const u8 = "",
    value: []const u8 = "",
    values: []const []const u8 = &.{},
};

pub const ComponentType = enum(u8) {
    action_row = 1,
    button = 2,
    string_select = 3,
    text_input = 4,
    user_select = 5,
    role_select = 6,
    mentionable_select = 7,
    channel_select = 8,
    section = 9,
    text_display = 10,
    thumbnail = 11,
    media_gallery = 12,
    file = 13,
    separator = 14,
    container = 17,
    label = 18,
    _,
};

pub const ButtonStyle = enum(u8) {
    primary = 1,
    secondary = 2,
    success = 3,
    danger = 4,
    link = 5,
    premium = 6,
    _,
};

pub const TextInputStyle = enum(u8) {
    short = 1,
    paragraph = 2,
    _,
};

pub const SelectOption = struct {
    label: []const u8 = "",
    value: []const u8 = "",
    description: ?[]const u8 = null,
    emoji: ?Emoji = null,
    default: bool = false,
};

pub const SelectDefaultValue = struct {
    id: []const u8 = "",
    @"type": []const u8 = "",
};

pub const UnfurledMedia = struct {
    url: []const u8 = "",
};

pub const MediaGalleryItem = struct {
    media: UnfurledMedia = .{},
    description: ?[]const u8 = null,
    spoiler: ?bool = null,
};

pub const Component = struct {
    type: u8 = 1,
    custom_id: ?[]const u8 = null,
    disabled: bool = false,
    style: ?u8 = null,
    label: ?[]const u8 = null,
    url: ?[]const u8 = null,
    sku_id: ?[]const u8 = null,
    emoji: ?Emoji = null,
    options: []const SelectOption = &.{},
    channel_types: []const i64 = &.{},
    min_values: ?u32 = null,
    max_values: ?u32 = null,
    min_length: ?u32 = null,
    max_length: ?u32 = null,
    placeholder: ?[]const u8 = null,
    value: ?[]const u8 = null,
    required: ?bool = null,
    default_values: []const SelectDefaultValue = &.{},
    content: ?[]const u8 = null,
    description: ?[]const u8 = null,
    divider: ?bool = null,
    spacing: ?u8 = null,
    accent_color: ?u32 = null,
    spoiler: ?bool = null,
    media_url: ?[]const u8 = null,
    file_url: ?[]const u8 = null,
    file_name: ?[]const u8 = null,
    accessory: ?*const Component = null,
    component: ?*const Component = null,
    items: []const MediaGalleryItem = &.{},
    components: []const Component = &.{},

    pub fn jsonStringify(self: Component, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write(self.type);
        switch (@as(ComponentType, @enumFromInt(self.type))) {
            .action_row => {
                try jw.objectField("components");
                try jw.beginArray();
                for (self.components) |c| try jw.write(c);
                try jw.endArray();
            },
            .button => {
                if (self.style) |s| {
                    try jw.objectField("style");
                    try jw.write(s);
                }
                if (self.label) |l| {
                    try jw.objectField("label");
                    try jw.write(l);
                }
                if (self.custom_id) |id| {
                    try jw.objectField("custom_id");
                    try jw.write(id);
                }
                if (self.url) |u| {
                    try jw.objectField("url");
                    try jw.write(u);
                }
                if (self.sku_id) |sku| {
                    try jw.objectField("sku_id");
                    try jw.write(sku);
                }
                try jw.objectField("disabled");
                try jw.write(self.disabled);
                if (self.emoji) |e| {
                    try jw.objectField("emoji");
                    try writeEmoji(jw, e);
                }
            },
            .string_select, .user_select, .role_select, .mentionable_select, .channel_select => {
                if (self.custom_id) |id| {
                    try jw.objectField("custom_id");
                    try jw.write(id);
                }
                if (self.options.len > 0) {
                    try jw.objectField("options");
                    try jw.beginArray();
                    for (self.options) |o| try writeSelectOption(jw, o);
                    try jw.endArray();
                }
                if (self.channel_types.len > 0) {
                    try jw.objectField("channel_types");
                    try jw.beginArray();
                    for (self.channel_types) |ct| try jw.write(ct);
                    try jw.endArray();
                }
                if (self.placeholder) |p| {
                    try jw.objectField("placeholder");
                    try jw.write(p);
                }
                if (self.min_values) |n| {
                    try jw.objectField("min_values");
                    try jw.write(n);
                }
                if (self.max_values) |n| {
                    try jw.objectField("max_values");
                    try jw.write(n);
                }
                if (self.required) |req| {
                    try jw.objectField("required");
                    try jw.write(req);
                }
                if (self.default_values.len > 0) {
                    try jw.objectField("default_values");
                    try jw.beginArray();
                    for (self.default_values) |dv| {
                        try jw.beginObject();
                        try jw.objectField("id");
                        try jw.write(dv.id);
                        try jw.objectField("type");
                        try jw.write(dv.@"type");
                        try jw.endObject();
                    }
                    try jw.endArray();
                }
                try jw.objectField("disabled");
                try jw.write(self.disabled);
            },
            .text_input => {
                if (self.custom_id) |id| {
                    try jw.objectField("custom_id");
                    try jw.write(id);
                }
                if (self.style) |s| {
                    try jw.objectField("style");
                    try jw.write(s);
                }
                if (self.label) |l| {
                    try jw.objectField("label");
                    try jw.write(l);
                }
                if (self.min_length) |n| {
                    try jw.objectField("min_length");
                    try jw.write(n);
                }
                if (self.max_length) |n| {
                    try jw.objectField("max_length");
                    try jw.write(n);
                }
                if (self.required) |req| {
                    try jw.objectField("required");
                    try jw.write(req);
                }
                if (self.value) |v| {
                    try jw.objectField("value");
                    try jw.write(v);
                }
                if (self.placeholder) |p| {
                    try jw.objectField("placeholder");
                    try jw.write(p);
                }
            },
            .section => {
                try jw.objectField("components");
                try jw.beginArray();
                for (self.components) |c| try jw.write(c);
                try jw.endArray();
                if (self.accessory) |a| {
                    try jw.objectField("accessory");
                    try jw.write(a.*);
                }
            },
            .text_display => {
                if (self.content) |c| {
                    try jw.objectField("content");
                    try jw.write(c);
                }
            },
            .thumbnail => {
                if (self.media_url) |u| {
                    try jw.objectField("media");
                    try writeUnfurledMedia(jw, u);
                }
                if (self.description) |d| {
                    try jw.objectField("description");
                    try jw.write(d);
                }
                if (self.spoiler) |s| {
                    try jw.objectField("spoiler");
                    try jw.write(s);
                }
            },
            .media_gallery => {
                try jw.objectField("items");
                try jw.beginArray();
                for (self.items) |item| {
                    try jw.beginObject();
                    try jw.objectField("media");
                    try writeUnfurledMedia(jw, item.media.url);
                    if (item.description) |d| {
                        try jw.objectField("description");
                        try jw.write(d);
                    }
                    if (item.spoiler) |s| {
                        try jw.objectField("spoiler");
                        try jw.write(s);
                    }
                    try jw.endObject();
                }
                try jw.endArray();
            },
            .file => {
                if (self.spoiler) |s| {
                    try jw.objectField("spoiler");
                    try jw.write(s);
                }
                if (self.file_name) |n| {
                    try jw.objectField("name");
                    try jw.write(n);
                }
                if (self.file_url) |u| {
                    try jw.objectField("file");
                    try writeUnfurledMedia(jw, u);
                }
            },
            .separator => {
                if (self.divider) |d| {
                    try jw.objectField("divider");
                    try jw.write(d);
                }
                if (self.spacing) |s| {
                    try jw.objectField("spacing");
                    try jw.write(s);
                }
            },
            .container => {
                if (self.accent_color) |c| {
                    try jw.objectField("accent_color");
                    try jw.write(c);
                }
                if (self.spoiler) |s| {
                    try jw.objectField("spoiler");
                    try jw.write(s);
                }
                try jw.objectField("components");
                try jw.beginArray();
                for (self.components) |c| try jw.write(c);
                try jw.endArray();
            },
            .label => {
                if (self.label) |l| {
                    try jw.objectField("label");
                    try jw.write(l);
                }
                if (self.description) |d| {
                    try jw.objectField("description");
                    try jw.write(d);
                }
                if (self.component) |c| {
                    try jw.objectField("component");
                    try jw.write(c.*);
                }
            },
            _ => {},
        }
        try jw.endObject();
    }
};

fn writeUnfurledMedia(jw: anytype, url: []const u8) !void {
    try jw.beginObject();
    try jw.objectField("url");
    try jw.write(url);
    try jw.endObject();
}

fn writeEmoji(jw: anytype, e: Emoji) !void {
    try jw.beginObject();
    if (e.id) |id| {
        try jw.objectField("id");
        try jw.write(id);
    }
    if (e.name) |name| {
        try jw.objectField("name");
        try jw.write(name);
    }
    try jw.endObject();
}

fn writeSelectOption(jw: anytype, o: SelectOption) !void {
    try jw.beginObject();
    try jw.objectField("label");
    try jw.write(o.label);
    try jw.objectField("value");
    try jw.write(o.value);
    if (o.description) |d| {
        try jw.objectField("description");
        try jw.write(d);
    }
    if (o.emoji) |e| {
        try jw.objectField("emoji");
        try writeEmoji(jw, e);
    }
    try jw.objectField("default");
    try jw.write(o.default);
    try jw.endObject();
}

pub const Modal = struct {
    title: []const u8 = "",
    custom_id: []const u8 = "",
    components: []const Component = &.{},
};

pub const InteractionCallbackResource = struct {
    type: u8 = 0,
    message: ?Message = null,
};

pub const InteractionCallbackResponse = struct {
    resource: ?InteractionCallbackResource = null,
};

pub const InteractionOption = struct {
    name: []const u8 = "",
    type: u8 = 0,
    value: ?std.json.Value = null,
    focused: bool = false,
    options: []const InteractionOption = &.{},

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !InteractionOption {
        const v = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, v, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !InteractionOption {
        const obj = switch (source) {
            .object => |o| o,
            else => return error.UnexpectedToken,
        };
        var out = InteractionOption{};
        if (obj.get("name")) |v| out.name = try asOwnedStringOrEmpty(allocator, v);
        if (obj.get("type")) |v| out.type = try asIntOrDefault(u8, v, 0);
        if (obj.get("value")) |v| {
            out.value = switch (v) {
                .null => null,
                else => v,
            };
        }
        if (obj.get("focused")) |v| out.focused = try asBoolOrDefault(v, false);
        if (obj.get("options")) |v| {
            switch (v) {
                .null => {},
                .array => |a| {
                    const sub_opts = try allocator.alloc(InteractionOption, a.items.len);
                    for (a.items, 0..) |item, i| {
                        sub_opts[i] = try jsonParseFromValue(allocator, item, options);
                    }
                    out.options = sub_opts;
                },
                else => return error.UnexpectedToken,
            }
        }
        return out;
    }

    pub fn asString(self: InteractionOption) ?[]const u8 {
        const v = self.value orelse return null;
        return switch (v) {
            .string => |s| s,
            else => null,
        };
    }

    pub fn asInteger(self: InteractionOption) ?i64 {
        const v = self.value orelse return null;
        return switch (v) {
            .integer => |i| i,
            else => null,
        };
    }

    pub fn asBool(self: InteractionOption) ?bool {
        const v = self.value orelse return null;
        return switch (v) {
            .bool => |b| b,
            else => null,
        };
    }

    pub fn asFloat(self: InteractionOption) ?f64 {
        const v = self.value orelse return null;
        return switch (v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
};

pub const ApplicationCommand = struct {
    id: ?[]const u8 = null,
    application_id: ?[]const u8 = null,
    name: []const u8 = "",
    description: []const u8 = "",
    type: u8 = 1,
    options: []const CommandOption = &.{},
};

pub const ApplicationCommandCreate = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    type: u8 = 1,
    options: []const CommandOption = &.{},
    default_member_permissions: ?[]const u8 = null,
    nsfw: ?bool = null,
    contexts: ?[]const i64 = null,
    integration_types: ?[]const i64 = null,
    name_localizations: ?std.json.Value = null,
    description_localizations: ?std.json.Value = null,
};

pub const CommandOption = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    type: u8 = 3,
    required: bool = false,
    choices: []const CommandChoice = &.{},
    options: []const CommandOption = &.{},
    channel_types: []const i64 = &.{},
    autocomplete: bool = false,
    min_value: ?f64 = null,
    max_value: ?f64 = null,
    min_length: ?u32 = null,
    max_length: ?u32 = null,
};

pub const CommandChoice = struct {
    name: []const u8 = "",
    value: std.json.Value = .null,
};

pub const Emoji = struct {
    id: ?[]const u8 = null,
    name: ?[]const u8 = null,
    animated: bool = false,

    pub fn jsonStringify(self: Emoji, jw: anytype) !void {
        try jw.beginObject();
        if (self.id) |id| {
            try jw.objectField("id");
            try jw.write(id);
        }
        if (self.name) |name| {
            try jw.objectField("name");
            try jw.write(name);
        }
        if (self.animated) {
            try jw.objectField("animated");
            try jw.write(self.animated);
        }
        try jw.endObject();
    }
};

pub const MessageReaction = struct {
    user_id: []const u8 = "",
    channel_id: []const u8 = "",
    message_id: []const u8 = "",
    guild_id: ?[]const u8 = null,
    emoji: Emoji = .{},
    burst: bool = false,
};

pub const Role = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    permissions: []const u8 = "",
    color: u32 = 0,
    hoist: bool = false,
    mentionable: bool = false,
    managed: bool = false,
    position: i32 = 0,
};

pub const GuildBan = struct {
    guild_id: []const u8 = "",
    user: User = .{},
};

pub const BanEntry = struct {
    reason: ?[]const u8 = null,
    user: User = .{},
};

pub const Invite = struct {
    code: []const u8 = "",
    max_age: u64 = 0,
    max_uses: u64 = 0,
    temporary: bool = false,
    uses: u64 = 0,
    channel_id: ?[]const u8 = null,
    guild_id: ?[]const u8 = null,
};

pub const PresenceUser = struct {
    id: []const u8 = "",
};

pub const Presence = struct {
    user: PresenceUser = .{},
    guild_id: ?[]const u8 = null,
    status: []const u8 = "",
};

pub const ThreadListActive = struct {
    threads: []const Channel = &.{},
    members: []const ThreadMember = &.{},
    has_more: bool = false,
};

pub const ThreadMember = struct {
    id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    join_timestamp: []const u8 = "",
};

pub const GuildScheduledEventUser = struct {
    guild_scheduled_event_id: []const u8 = "",
    user: User = .{},
    member: ?GuildMember = null,
};

pub const AuditLogEntry = struct {
    id: []const u8 = "",
    user_id: ?[]const u8 = null,
    action_type: u64 = 0,
    target_id: ?[]const u8 = null,
    reason: ?[]const u8 = null,
};

pub const AuditLog = struct {
    entries: []const AuditLogEntry = &.{},
    users: []const User = &.{},
};

pub const Onboarding = struct {
    default_channel_ids: []const []const u8 = &.{},
    enabled: bool = false,
    mode: u64 = 0,
};

pub const Template = struct {
    code: []const u8 = "",
    name: []const u8 = "",
    description: ?[]const u8 = null,
};

pub const Webhook = struct {
    id: []const u8 = "",
    guild_id: ?[]const u8 = null,
    channel_id: ?[]const u8 = null,
    user: ?User = null,
    name: ?[]const u8 = null,
    avatar: ?[]const u8 = null,
    token: ?[]const u8 = null,
};

pub const CommandPermissions = struct {
    id: []const u8 = "",
    application_id: []const u8 = "",
    guild_id: []const u8 = "",
    permissions: []const CommandPermissionEntry = &.{},
};

pub const CommandPermissionEntry = struct {
    id: []const u8 = "",
    kind: u8 = 1,
    permission: bool = false,
};

pub const PollMedia = struct {
    text: ?[]const u8 = null,
    emoji: ?Emoji = null,

    pub fn jsonStringify(self: PollMedia, jw: anytype) !void {
        try jw.beginObject();
        if (self.text) |t| {
            try jw.objectField("text");
            try jw.write(t);
        }
        if (self.emoji) |e| {
            try jw.objectField("emoji");
            try jw.write(e);
        }
        try jw.endObject();
    }
};

pub const PollAnswerCreate = struct {
    poll_media: PollMedia = .{},
};

pub const PollCreate = struct {
    question: PollMedia = .{},
    answers: []const PollAnswerCreate = &.{},
    duration: ?u32 = null,
    allow_multiselect: bool = false,
    layout_type: u32 = 1,

    pub fn jsonStringify(self: PollCreate, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("question");
        try jw.write(self.question);
        try jw.objectField("answers");
        try jw.write(self.answers);
        if (self.duration) |d| {
            try jw.objectField("duration");
            try jw.write(d);
        }
        try jw.objectField("allow_multiselect");
        try jw.write(self.allow_multiselect);
        try jw.objectField("layout_type");
        try jw.write(self.layout_type);
        try jw.endObject();
    }
};

pub const PollAnswer = struct {
    answer_id: u64 = 0,
    poll_media: PollMedia = .{},
};

pub const PollAnswerCount = struct {
    id: u64 = 0,
    count: u64 = 0,
    me_voted: bool = false,
};

pub const PollResults = struct {
    is_finalized: bool = false,
    answer_counts: []const PollAnswerCount = &.{},
};

pub const Poll = struct {
    question: PollMedia = .{},
    answers: []const PollAnswer = &.{},
    expiry: ?[]const u8 = null,
    allow_multiselect: bool = false,
    layout_type: u32 = 1,
    results: ?PollResults = null,

    pub fn totalVotes(self: Poll) u64 {
        var total: u64 = 0;
        if (self.results) |res| {
            for (res.answer_counts) |ac| {
                total += ac.count;
            }
        }
        return total;
    }

    pub fn getAnswer(self: Poll, answer_id: u64) ?PollAnswer {
        for (self.answers) |a| {
            if (a.answer_id == answer_id) return a;
        }
        return null;
    }
};

pub const PollAnswerVoters = struct {
    users: []const User = &.{},
};

pub const MessagePollVote = struct {
    user_id: []const u8 = "",
    channel_id: []const u8 = "",
    message_id: []const u8 = "",
    guild_id: ?[]const u8 = null,
    answer_id: u32 = 0,
};

pub const GuildMembersChunk = struct {
    guild_id: []const u8 = "",
    members: []const GuildMember = &.{},
    chunk_index: u32 = 0,
    chunk_count: u32 = 0,
    nonce: ?[]const u8 = null,
};

pub const TypingStart = struct {
    channel_id: []const u8 = "",
    user_id: []const u8 = "",
    guild_id: ?[]const u8 = null,
    timestamp: []const u8 = "",
    member: ?GuildMember = null,
};

pub const VoiceState = struct {
    guild_id: ?[]const u8 = null,
    channel_id: ?[]const u8 = null,
    user_id: []const u8 = "",
    session_id: []const u8 = "",
    deaf: bool = false,
    mute: bool = false,
    self_deaf: bool = false,
    self_mute: bool = false,
    suppress: bool = false,
};

pub const VoiceServerUpdate = struct {
    token: []const u8 = "",
    guild_id: []const u8 = "",
    endpoint: ?[]const u8 = null,
};

pub const WebhooksUpdate = struct {
    guild_id: []const u8 = "",
    channel_id: []const u8 = "",
};

pub const ReactionRemoveAll = struct {
    channel_id: []const u8 = "",
    message_id: []const u8 = "",
    guild_id: ?[]const u8 = null,
};

pub const ReactionRemoveEmoji = struct {
    channel_id: []const u8 = "",
    message_id: []const u8 = "",
    guild_id: ?[]const u8 = null,
    emoji: Emoji = .{},
};

pub const GuildEmoji = struct {
    id: ?[]const u8 = null,
    name: ?[]const u8 = null,
    roles: []const []const u8 = &.{},
    user: ?User = null,
    require_colons: bool = false,
    managed: bool = false,
    animated: bool = false,
    available: bool = true,
};

pub const GuildSticker = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    description: ?[]const u8 = null,
    tags: []const u8 = "",
    @"type": u32 = 1,
    format_type: u32 = 1,
    available: bool = true,
    guild_id: ?[]const u8 = null,
    user: ?User = null,
};

pub const GuildScheduledEvent = struct {
    id: []const u8 = "",
    guild_id: []const u8 = "",
    channel_id: ?[]const u8 = null,
    creator_id: ?[]const u8 = null,
    name: []const u8 = "",
    description: ?[]const u8 = null,
    scheduled_start_time: []const u8 = "",
    scheduled_end_time: ?[]const u8 = null,
    privacy_level: u32 = 2,
    status: u32 = 1,
    entity_type: u32 = 1,
    entity_id: ?[]const u8 = null,
    user_count: ?u32 = null,
};

pub const AutoModerationAction = struct {
    @"type": u32 = 1,
    metadata: ?std.json.Value = null,
};

pub const AutoModerationRule = struct {
    id: []const u8 = "",
    guild_id: []const u8 = "",
    name: []const u8 = "",
    creator_id: []const u8 = "",
    event_type: u32 = 1,
    trigger_type: u32 = 1,
    actions: []const AutoModerationAction = &.{},
    enabled: bool = true,
    exempt_roles: []const []const u8 = &.{},
    exempt_channels: []const []const u8 = &.{},
};

pub const StageInstance = struct {
    id: []const u8 = "",
    guild_id: []const u8 = "",
    channel_id: []const u8 = "",
    topic: []const u8 = "",
    privacy_level: u32 = 1,
};

pub const SoundboardSound = struct {
    name: []const u8 = "",
    sound_id: []const u8 = "",
    volume: f64 = 1.0,
    available: bool = true,
    guild_id: ?[]const u8 = null,
};

pub const SoundboardList = struct {
    items: []const SoundboardSound = &.{},
};

pub const WelcomeChannel = struct {
    channel_id: []const u8 = "",
    description: []const u8 = "",
    emoji_id: ?[]const u8 = null,
    emoji_name: ?[]const u8 = null,
};

pub const WelcomeScreen = struct {
    description: ?[]const u8 = null,
    welcome_channels: []const WelcomeChannel = &.{},
};

pub const WidgetSettings = struct {
    enabled: bool = false,
    channel_id: ?[]const u8 = null,
};

pub const Widget = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    presence_count: u64 = 0,
};

pub const VanityUrl = struct {
    code: ?[]const u8 = null,
    uses: u64 = 0,
};

pub const BulkBanResult = struct {
    banned_users: []const []const u8 = &.{},
};

pub const PruneResult = struct {
    pruned: ?u64 = null,
};

pub const Application = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    icon: ?[]const u8 = null,
    description: []const u8 = "",
    bot_public: bool = true,
    bot_require_code_grant: bool = false,
    bot: ?User = null,
    flags: ?u64 = null,
};

pub const VoiceStatus = struct {
    status: ?[]const u8 = null,
};

pub const EntitlementType = enum(u8) {
    Purchase = 1,
    PremiumSubscription = 2,
    DeveloperGift = 3,
    TestModePurchase = 4,
    FreePurchase = 5,
    UserGift = 6,
    PremiumPurchase = 7,
    ApplicationSubscription = 8,
    _,
};

pub const Entitlement = struct {
    id: []const u8,
    sku_id: []const u8,
    application_id: []const u8,
    user_id: ?[]const u8 = null,
    type: u8 = 8,
    deleted: bool = false,
    starts_at: ?[]const u8 = null,
    ends_at: ?[]const u8 = null,
    guild_id: ?[]const u8 = null,
    consumed: ?bool = null,
};

pub fn parse(comptime T: type, allocator: std.mem.Allocator, body: []const u8) !std.json.Parsed(T) {
    // alloc_always: o default empresta strings sem escape do input; como o
    // buffer (ex. res.body do Rest) costuma ser liberado em seguida, o
    // resultado precisa ser dono de todas as strings.
    return std.json.parseFromSlice(T, allocator, body, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}

pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false });
}
