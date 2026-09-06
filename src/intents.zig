pub const guilds: u32 = 1 << 0;
pub const guild_members: u32 = 1 << 1;
pub const guild_moderation: u32 = 1 << 2;
pub const guild_expressions: u32 = 1 << 3;
pub const guild_integrations: u32 = 1 << 4;
pub const guild_webhooks: u32 = 1 << 5;
pub const guild_invites: u32 = 1 << 6;
pub const guild_voice_states: u32 = 1 << 7;
pub const guild_presences: u32 = 1 << 8;
pub const guild_messages: u32 = 1 << 9;
pub const guild_message_reactions: u32 = 1 << 10;
pub const guild_message_typing: u32 = 1 << 11;
pub const direct_messages: u32 = 1 << 12;
pub const direct_message_reactions: u32 = 1 << 13;
pub const direct_message_typing: u32 = 1 << 14;
pub const message_content: u32 = 1 << 15;
pub const guild_scheduled_events: u32 = 1 << 16;
pub const auto_moderation_configuration: u32 = 1 << 20;
pub const auto_moderation_execution: u32 = 1 << 21;
pub const guild_message_polls: u32 = 1 << 24;
pub const direct_message_polls: u32 = 1 << 25;

pub const guild_bans: u32 = guild_moderation;
pub const guild_emojis_and_stickers: u32 = guild_expressions;

pub const privileged: u32 = guild_members | guild_presences | message_content;

pub const GatewayIntentBits = enum(u32) {
    Guilds = 1 << 0,
    GuildMembers = 1 << 1,
    GuildModeration = 1 << 2,
    GuildExpressions = 1 << 3,
    GuildIntegrations = 1 << 4,
    GuildWebhooks = 1 << 5,
    GuildInvites = 1 << 6,
    GuildVoiceStates = 1 << 7,
    GuildPresences = 1 << 8,
    GuildMessages = 1 << 9,
    GuildMessageReactions = 1 << 10,
    GuildMessageTyping = 1 << 11,
    DirectMessages = 1 << 12,
    DirectMessageReactions = 1 << 13,
    DirectMessageTyping = 1 << 14,
    MessageContent = 1 << 15,
    GuildScheduledEvents = 1 << 16,
    AutoModerationConfiguration = 1 << 20,
    AutoModerationExecution = 1 << 21,
    GuildMessagePolls = 1 << 24,
    DirectMessagePolls = 1 << 25,

    // Aliases matching discord.js
    pub const GuildBans = GatewayIntentBits.GuildModeration;
    pub const GuildEmojisAndStickers = GatewayIntentBits.GuildExpressions;
};

pub fn of(flags: anytype) u32 {
    const FT = @TypeOf(flags);
    if (FT == GatewayIntentBits) return @intFromEnum(flags);

    const info = @typeInfo(FT);
    if (info == .pointer) {
        if (info.pointer.size == .slice) {
            if (info.pointer.child != GatewayIntentBits) {
                @compileError("Intent slice elements must be GatewayIntentBits, found " ++ @typeName(info.pointer.child));
            }
            var out: u32 = 0;
            for (flags) |f| out |= @intFromEnum(f);
            return out;
        } else if (info.pointer.size == .one and @typeInfo(info.pointer.child) == .array) {
            return of(flags.*);
        }
    }
    if (info == .array) {
        if (info.array.child != GatewayIntentBits) {
            @compileError("Intent array elements must be GatewayIntentBits, found " ++ @typeName(info.array.child));
        }
        var out: u32 = 0;
        for (flags) |f| out |= @intFromEnum(f);
        return out;
    }
    if (info == .@"struct" and info.@"struct".is_tuple) {
        var out: u32 = 0;
        inline for (flags) |f| {
            if (@TypeOf(f) != GatewayIntentBits) {
                @compileError("Intent element in tuple must be GatewayIntentBits, found " ++ @typeName(@TypeOf(f)));
            }
            out |= @intFromEnum(f);
        }
        return out;
    }
    @compileError("Intents must be GatewayIntentBits or a tuple of GatewayIntentBits (e.g. .{ GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, ... }), found " ++ @typeName(FT));
}

pub fn defaults() u32 {
    return guilds | guild_messages | direct_messages;
}

pub fn withMessageContent(base: u32) u32 {
    return base | message_content;
}

pub fn has(value: u32, flag: u32) bool {
    return value & flag != 0;
}

pub fn requiresApproval(value: u32) bool {
    return value & privileged != 0;
}
