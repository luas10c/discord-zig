const std = @import("std");
const intents = @import("discord-zig").intents;

test "defaults include guilds and messages" {
    const v = intents.defaults();
    try std.testing.expect(intents.has(v, intents.guilds));
    try std.testing.expect(intents.has(v, intents.guild_messages));
    try std.testing.expect(!intents.has(v, intents.message_content));
}

test "privileged detection" {
    try std.testing.expect(intents.requiresApproval(intents.message_content));
    try std.testing.expect(!intents.requiresApproval(intents.guilds));
}

test "of combines flags like discord.js array" {
    const GIB = intents.GatewayIntentBits;
    const v = intents.of(.{ GIB.Guilds, GIB.GuildMessages, GIB.MessageContent });
    try std.testing.expectEqual(intents.guilds | intents.guild_messages | intents.message_content, v);
}

test "of accepts single flag and mixed values" {
    const GIB = intents.GatewayIntentBits;
    try std.testing.expectEqual(intents.guilds, intents.of(GIB.Guilds));
    try std.testing.expectEqual(
        intents.guilds | intents.guild_invites,
        intents.of(.{ GIB.Guilds, GIB.GuildInvites }),
    );
}

test "of empty is zero and falls back to defaults" {
    try std.testing.expectEqual(@as(u32, 0), intents.of(.{}));
}

test "GatewayIntentBits enum has exact parity with intents constants" {
    const GIB = intents.GatewayIntentBits;
    try std.testing.expectEqual(intents.guilds, @intFromEnum(GIB.Guilds));
    try std.testing.expectEqual(intents.guild_members, @intFromEnum(GIB.GuildMembers));
    try std.testing.expectEqual(intents.guild_moderation, @intFromEnum(GIB.GuildModeration));
    try std.testing.expectEqual(intents.guild_expressions, @intFromEnum(GIB.GuildExpressions));
    try std.testing.expectEqual(intents.guild_integrations, @intFromEnum(GIB.GuildIntegrations));
    try std.testing.expectEqual(intents.guild_webhooks, @intFromEnum(GIB.GuildWebhooks));
    try std.testing.expectEqual(intents.guild_invites, @intFromEnum(GIB.GuildInvites));
    try std.testing.expectEqual(intents.guild_voice_states, @intFromEnum(GIB.GuildVoiceStates));
    try std.testing.expectEqual(intents.guild_presences, @intFromEnum(GIB.GuildPresences));
    try std.testing.expectEqual(intents.guild_messages, @intFromEnum(GIB.GuildMessages));
    try std.testing.expectEqual(intents.guild_message_reactions, @intFromEnum(GIB.GuildMessageReactions));
    try std.testing.expectEqual(intents.guild_message_typing, @intFromEnum(GIB.GuildMessageTyping));
    try std.testing.expectEqual(intents.direct_messages, @intFromEnum(GIB.DirectMessages));
    try std.testing.expectEqual(intents.direct_message_reactions, @intFromEnum(GIB.DirectMessageReactions));
    try std.testing.expectEqual(intents.direct_message_typing, @intFromEnum(GIB.DirectMessageTyping));
    try std.testing.expectEqual(intents.message_content, @intFromEnum(GIB.MessageContent));
    try std.testing.expectEqual(intents.guild_scheduled_events, @intFromEnum(GIB.GuildScheduledEvents));
    try std.testing.expectEqual(intents.auto_moderation_configuration, @intFromEnum(GIB.AutoModerationConfiguration));
    try std.testing.expectEqual(intents.auto_moderation_execution, @intFromEnum(GIB.AutoModerationExecution));
    try std.testing.expectEqual(intents.guild_message_polls, @intFromEnum(GIB.GuildMessagePolls));
    try std.testing.expectEqual(intents.direct_message_polls, @intFromEnum(GIB.DirectMessagePolls));
}

test "GatewayIntentBits discord.js PascalCase and alias parity" {
    const GIB = intents.GatewayIntentBits;
    try std.testing.expectEqual(GIB.GuildModeration, GIB.GuildBans);
    try std.testing.expectEqual(GIB.GuildExpressions, GIB.GuildEmojisAndStickers);
}

test "of accepts GatewayIntentBits tuple discord.js style" {
    const GIB = intents.GatewayIntentBits;
    const v = intents.of(.{
        GIB.Guilds,
        GIB.GuildMessages,
        GIB.MessageContent,
    });
    try std.testing.expectEqual(intents.guilds | intents.guild_messages | intents.message_content, v);
}

test "discord root exports GatewayIntentBits" {
    const discord = @import("discord-zig");
    try std.testing.expectEqual(intents.GatewayIntentBits, discord.GatewayIntentBits);
}
