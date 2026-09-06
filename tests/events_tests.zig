const std = @import("std");
const events = @import("discord-zig").events;

test "classify events" {
    try std.testing.expectEqual(events.Type.ready, events.classify("READY"));
    try std.testing.expectEqual(events.Type.message_create, events.classify("MESSAGE_CREATE"));
    try std.testing.expectEqual(events.Type.message_reaction_add, events.classify("MESSAGE_REACTION_ADD"));
    try std.testing.expectEqual(events.Type.message_reaction_remove, events.classify("MESSAGE_REACTION_REMOVE"));
    try std.testing.expectEqual(events.Type.message_reaction_remove_all, events.classify("MESSAGE_REACTION_REMOVE_ALL"));
    try std.testing.expectEqual(events.Type.message_reaction_remove_emoji, events.classify("MESSAGE_REACTION_REMOVE_EMOJI"));
    try std.testing.expectEqual(events.Type.message_delete, events.classify("MESSAGE_DELETE"));
    try std.testing.expectEqual(events.Type.channel_delete, events.classify("CHANNEL_DELETE"));
    try std.testing.expectEqual(events.Type.interaction_create, events.classify("INTERACTION_CREATE"));
    try std.testing.expectEqual(events.Type.guild_member_add, events.classify("GUILD_MEMBER_ADD"));
    try std.testing.expectEqual(events.Type.guild_member_update, events.classify("GUILD_MEMBER_UPDATE"));
    try std.testing.expectEqual(events.Type.guild_member_remove, events.classify("GUILD_MEMBER_REMOVE"));
    try std.testing.expectEqual(events.Type.unknown, events.classify("SOMETHING_NEW"));
    try std.testing.expectEqual(events.Type.unknown, events.classify(null));
}

test "discord.js names" {
    try std.testing.expectEqualStrings("clientReady", events.discordName(.ready));
    try std.testing.expectEqualStrings("messageCreate", events.discordName(.message_create));
    try std.testing.expectEqualStrings("channelDelete", events.discordName(.channel_delete));
    try std.testing.expectEqualStrings("interactionCreate", events.discordName(.interaction_create));
    try std.testing.expectEqualStrings("guildMemberAdd", events.discordName(.guild_member_add));
    try std.testing.expectEqualStrings("guildMemberRemove", events.discordName(.guild_member_remove));
}

test "normalize accepts enum and strings" {
    try std.testing.expectEqual(events.Type.message_create, events.normalize(.message_create));
    try std.testing.expectEqual(events.Type.message_create, events.normalize("messageCreate"));
    try std.testing.expectEqual(events.Type.message_create, events.normalize("message_create"));
    try std.testing.expectEqual(events.Type.ready, events.normalize("clientReady"));
    try std.testing.expectEqual(events.Type.ready, events.normalize("ready"));
    try std.testing.expectEqual(events.Type.guild_member_add, events.normalize("guildMemberAdd"));
    try std.testing.expectEqual(events.Type.guild_member_remove, events.normalize(.guild_member_remove));
    try std.testing.expectEqual(events.Type.message_reaction_add, events.normalize("messageReactionAdd"));
    try std.testing.expectEqual(events.Type.message_reaction_remove_emoji, events.normalize(.message_reaction_remove_emoji));
}

test "normalize accepts Events enum" {
    try std.testing.expectEqual(events.Type.ready, events.normalize(events.Events.ClientReady));
    try std.testing.expectEqual(events.Type.message_create, events.normalize(events.Events.MessageCreate));
    try std.testing.expectEqual(events.Type.message_reaction_add, events.normalize(events.Events.MessageReactionAdd));
    try std.testing.expectEqual(events.Type.interaction_create, events.normalize(events.Events.InteractionCreate));
}

test "unknown stays reachable as internal escape hatch" {
    try std.testing.expectEqual(events.Type.unknown, events.normalize(.unknown));
    try std.testing.expectEqual(events.Type.unknown, events.normalize("unknown"));
}

test "fromEvents covers every Type" {
    try std.testing.expectEqual(events.Type.message_delete_bulk, events.fromEvents(.MessageDeleteBulk));
    try std.testing.expectEqual(events.Type.guild_member_update, events.fromEvents(.GuildMemberUpdate));
    try std.testing.expectEqual(events.Type.user_update, events.fromEvents(.UserUpdate));
}

test "payload types" {
    try std.testing.expect(events.Payload(.message_create) == @import("discord-zig").schema.Message);
    try std.testing.expect(events.Payload(.ready) == @import("discord-zig").schema.Ready);
    try std.testing.expect(events.Payload(.resumed) == void);
    try std.testing.expect(events.Payload(.guild_create) == std.json.Value);
    try std.testing.expect(events.Payload(.message_reaction_add) == @import("discord-zig").schema.MessageReaction);
    try std.testing.expect(events.Payload(.message_reaction_remove_all) == @import("discord-zig").schema.ReactionRemoveAll);
    try std.testing.expect(events.Payload(.message_reaction_remove_emoji) == @import("discord-zig").schema.ReactionRemoveEmoji);
    try std.testing.expect(events.Payload(.message_poll_vote_add) == @import("discord-zig").schema.MessagePollVote);
    try std.testing.expect(events.Payload(.message_poll_vote_remove) == @import("discord-zig").schema.MessagePollVote);
}

test "classify new gateway events" {
    try std.testing.expectEqual(events.Type.guild_members_chunk, events.classify("GUILD_MEMBERS_CHUNK"));
    try std.testing.expectEqual(events.Type.typing_start, events.classify("TYPING_START"));
    try std.testing.expectEqual(events.Type.voice_state_update, events.classify("VOICE_STATE_UPDATE"));
    try std.testing.expectEqual(events.Type.voice_server_update, events.classify("VOICE_SERVER_UPDATE"));
    try std.testing.expectEqual(events.Type.voice_channel_effect_send, events.classify("VOICE_CHANNEL_EFFECT_SEND"));
    try std.testing.expectEqual(events.Type.webhooks_update, events.classify("WEBHOOKS_UPDATE"));
    try std.testing.expectEqual(events.Type.thread_create, events.classify("THREAD_CREATE"));
    try std.testing.expectEqual(events.Type.thread_members_update, events.classify("THREAD_MEMBERS_UPDATE"));
    try std.testing.expectEqual(events.Type.presence_update, events.classify("PRESENCE_UPDATE"));
    try std.testing.expectEqual(events.Type.guild_ban_add, events.classify("GUILD_BAN_ADD"));
    try std.testing.expectEqual(events.Type.guild_ban_remove, events.classify("GUILD_BAN_REMOVE"));
    try std.testing.expectEqual(events.Type.guild_role_create, events.classify("GUILD_ROLE_CREATE"));
    try std.testing.expectEqual(events.Type.guild_role_delete, events.classify("GUILD_ROLE_DELETE"));
    try std.testing.expectEqual(events.Type.invite_create, events.classify("INVITE_CREATE"));
    try std.testing.expectEqual(events.Type.invite_delete, events.classify("INVITE_DELETE"));
    try std.testing.expectEqual(events.Type.message_poll_vote_add, events.classify("MESSAGE_POLL_VOTE_ADD"));
    try std.testing.expectEqual(events.Type.channel_pins_update, events.classify("CHANNEL_PINS_UPDATE"));
    try std.testing.expectEqual(events.Type.auto_moderation_action_execution, events.classify("AUTO_MODERATION_ACTION_EXECUTION"));
    try std.testing.expectEqual(events.Type.auto_moderation_rule_create, events.classify("AUTO_MODERATION_RULE_CREATE"));
    try std.testing.expectEqual(events.Type.entitlement_create, events.classify("ENTITLEMENT_CREATE"));
    try std.testing.expectEqual(events.Type.guild_scheduled_event_create, events.classify("GUILD_SCHEDULED_EVENT_CREATE"));
    try std.testing.expectEqual(events.Type.guild_scheduled_event_user_remove, events.classify("GUILD_SCHEDULED_EVENT_USER_REMOVE"));
    try std.testing.expectEqual(events.Type.stage_instance_delete, events.classify("STAGE_INSTANCE_DELETE"));
    try std.testing.expectEqual(events.Type.guild_soundboard_sounds_update, events.classify("GUILD_SOUNDBOARD_SOUNDS_UPDATE"));
    try std.testing.expectEqual(events.Type.application_command_permissions_update, events.classify("APPLICATION_COMMAND_PERMISSIONS_UPDATE"));
    try std.testing.expectEqual(events.Type.subscription_create, events.classify("SUBSCRIPTION_CREATE"));
    try std.testing.expectEqual(events.Type.guild_emojis_update, events.classify("GUILD_EMOJIS_UPDATE"));
    try std.testing.expectEqual(events.Type.guild_stickers_update, events.classify("GUILD_STICKERS_UPDATE"));
    try std.testing.expectEqual(events.Type.guild_audit_log_entry_create, events.classify("GUILD_AUDIT_LOG_ENTRY_CREATE"));
    try std.testing.expectEqual(events.Type.guild_integrations_update, events.classify("GUILD_INTEGRATIONS_UPDATE"));
}

test "new payload types" {
    const schema = @import("discord-zig").schema;
    try std.testing.expect(events.Payload(.guild_members_chunk) == schema.GuildMembersChunk);
    try std.testing.expect(events.Payload(.typing_start) == schema.TypingStart);
    try std.testing.expect(events.Payload(.voice_state_update) == schema.VoiceState);
    try std.testing.expect(events.Payload(.voice_server_update) == schema.VoiceServerUpdate);
    try std.testing.expect(events.Payload(.webhooks_update) == schema.WebhooksUpdate);
    try std.testing.expect(events.Payload(.guild_role_create) == schema.Role);
    try std.testing.expect(events.Payload(.guild_role_delete) == events.RoleDelete);
    try std.testing.expect(events.Payload(.guild_ban_add) == schema.GuildBan);
    try std.testing.expect(events.Payload(.thread_create) == std.json.Value);
    try std.testing.expect(events.Payload(.presence_update) == schema.Presence);
}

test "new discord.js names and normalize" {
    try std.testing.expectEqualStrings("guildMembersChunk", events.discordName(.guild_members_chunk));
    try std.testing.expectEqualStrings("typingStart", events.discordName(.typing_start));
    try std.testing.expectEqualStrings("voiceStateUpdate", events.discordName(.voice_state_update));
    try std.testing.expectEqualStrings("threadCreate", events.discordName(.thread_create));
    try std.testing.expectEqualStrings("guildBanAdd", events.discordName(.guild_ban_add));
    try std.testing.expectEqual(events.Type.guild_members_chunk, events.normalize("guildMembersChunk"));
    try std.testing.expectEqual(events.Type.typing_start, events.normalize(events.Events.TypingStart));
    try std.testing.expectEqual(events.Type.thread_create, events.normalize(events.Events.ThreadCreate));
    try std.testing.expectEqual(events.Type.guild_role_delete, events.normalize(events.Events.GuildRoleDelete));
}

test "members chunk parses and feeds member cache" {
    const cache_mod = @import("discord-zig").cache;
    const schema = @import("discord-zig").schema;
    const body = "{\"guild_id\":\"10\",\"members\":[{\"user\":{\"id\":\"1\",\"username\":\"a\"}},{\"user\":{\"id\":\"2\",\"username\":\"b\"}}],\"chunk_index\":0,\"chunk_count\":1}";
    var chunk = try schema.parse(schema.GuildMembersChunk, std.testing.allocator, body);
    defer chunk.deinit();
    try std.testing.expectEqualStrings("10", chunk.value.guild_id);
    try std.testing.expectEqual(@as(usize, 2), chunk.value.members.len);

    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    var v = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{});
    defer v.deinit();
    try c.update(.guild_members_chunk, v.value);
    try std.testing.expectEqual(@as(usize, 2), c.members.count());
}
