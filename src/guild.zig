const std = @import("std");
const schema = @import("./schema.zig");
const client_mod = @import("./client.zig");
const channel_mod = @import("./channel.zig");
const voice_mod = @import("./voice.zig");

pub const Guilds = struct {
    _slot: usize = 0,

    fn client(self: *Guilds) *client_mod.Client {
        return @alignCast(@fieldParentPtr("guilds", self));
    }

    pub fn fetch(self: *Guilds, id: []const u8) !Guild {
        const c = self.client();
        const key = std.fmt.parseInt(u64, id, 10) catch null;
        if (key) |k| {
            if (c.cache.guilds.get(k) != null) return Guild.init(c, id);
        }
        var fetched = try c.rest.getGuild(id);
        if (key) |k| {
            var owned: ?std.json.Parsed(schema.Guild) = fetched;
            errdefer if (owned) |*p| p.deinit();
            try c.cache.guilds.putParsed(k, owned.?);
            owned = null;
        } else {
            fetched.deinit();
        }
        return Guild.init(c, id);
    }

    pub fn fetchAll(self: *Guilds, limit: u32) !std.json.Parsed([]schema.Guild) {
        return self.client().rest.listGuilds(limit);
    }
};

pub const Guild = struct {
    client: *client_mod.Client,
    id: []const u8,
    members: Members = .{},
    roles: Roles = .{},
    channels: GuildChannels = .{},
    bans: Bans = .{},
    emojis: GuildEmojis = .{},
    stickers: GuildStickers = .{},
    scheduledEvents: GuildScheduledEvents = .{},
    autoModeration: GuildAutoModeration = .{},
    stageInstances: GuildStageInstances = .{},
    commands: GuildCommands = .{},
    invites: GuildInvites = .{},
    webhooks: GuildWebhooks = .{},
    voice: GuildVoice = .{},

    pub fn init(client: *client_mod.Client, id: []const u8) Guild {
        return .{ .client = client, .id = id };
    }

    pub fn fetch(self: Guild) !std.json.Parsed(schema.Guild) {
        return self.client.rest.getGuild(self.id);
    }

    pub fn fetchInvites(self: Guild) !std.json.Parsed([]schema.Invite) {
        return self.client.rest.fetchGuildInvites(self.id);
    }

    pub fn fetchActiveThreads(self: Guild) !std.json.Parsed(schema.ThreadListActive) {
        return self.client.rest.fetchActiveThreads(self.id);
    }

    pub fn edit(self: Guild, options: anytype) !std.json.Parsed(schema.Guild) {
        return self.client.rest.editGuild(self.id, options);
    }

    pub fn leave(self: Guild) !void {
        return self.client.rest.leaveGuild(self.id);
    }

    pub fn fetchOwner(self: Guild) !std.json.Parsed(schema.GuildMember) {
        var guild = try self.fetch();
        defer guild.deinit();
        if (guild.value.owner_id.len == 0) return error.MissingOwnerId;
        return self.client.rest.getMember(self.id, guild.value.owner_id);
    }

    pub fn pruneCount(self: Guild, days: u32, roles: []const []const u8) !std.json.Parsed(schema.PruneResult) {
        return self.client.rest.getPruneCount(self.id, days, roles);
    }

    pub fn prune(self: Guild, days: u32, roles: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.PruneResult) {
        return self.client.rest.beginPrune(self.id, days, roles, reason);
    }

    pub fn bulkBan(self: Guild, user_ids: []const []const u8, delete_message_seconds: u32, reason: ?[]const u8) !std.json.Parsed(schema.BulkBanResult) {
        return self.client.rest.bulkBan(self.id, user_ids, delete_message_seconds, reason);
    }

    pub fn searchMembers(self: Guild, query: []const u8, limit: u32) !std.json.Parsed([]schema.GuildMember) {
        return self.client.rest.searchMembers(self.id, query, limit);
    }

    pub fn fetchMe(self: Guild) !std.json.Parsed(schema.GuildMember) {
        return self.client.rest.fetchMe(self.id);
    }

    pub fn fetchWelcomeScreen(self: Guild) !std.json.Parsed(schema.WelcomeScreen) {
        return self.client.rest.fetchWelcomeScreen(self.id);
    }

    pub fn editWelcomeScreen(self: Guild, enabled: ?bool, description: ?[]const u8) !std.json.Parsed(schema.WelcomeScreen) {
        return self.client.rest.editWelcomeScreen(self.id, enabled, description);
    }

    pub fn fetchWidget(self: Guild) !std.json.Parsed(schema.Widget) {
        return self.client.rest.fetchWidget(self.id);
    }

    pub fn fetchWidgetSettings(self: Guild) !std.json.Parsed(schema.WidgetSettings) {
        return self.client.rest.fetchWidgetSettings(self.id);
    }

    pub fn editWidgetSettings(self: Guild, enabled: ?bool, channel_id: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.WidgetSettings) {
        return self.client.rest.editWidgetSettings(self.id, enabled, channel_id, reason);
    }

    pub fn fetchVanityUrl(self: Guild) !std.json.Parsed(schema.VanityUrl) {
        return self.client.rest.fetchVanityUrl(self.id);
    }

    pub fn fetchAuditLogs(self: Guild, limit: u32, action_type: ?u64, user_id: ?[]const u8) !std.json.Parsed(schema.AuditLog) {
        return self.client.rest.fetchAuditLog(self.id, limit, action_type, user_id);
    }

    pub fn fetchTemplates(self: Guild) !std.json.Parsed([]schema.Template) {
        return self.client.rest.fetchTemplates(self.id);
    }

    pub fn createTemplate(self: Guild, name: []const u8, description: ?[]const u8) !std.json.Parsed(schema.Template) {
        return self.client.rest.createTemplate(self.id, name, description);
    }

    pub fn fetchOnboarding(self: Guild) !std.json.Parsed(schema.Onboarding) {
        return self.client.rest.getOnboarding(self.id);
    }

    pub fn editOnboarding(self: Guild, enabled: ?bool, default_channel_ids: ?[]const []const u8) !std.json.Parsed(schema.Onboarding) {
        return self.client.rest.editOnboarding(self.id, enabled, default_channel_ids);
    }
};

pub const Members = struct {
    _slot: usize = 0,

    fn guild(self: *Members) *Guild {
        return @fieldParentPtr("members", self);
    }

    pub fn fetch(self: *Members, user_id: []const u8) !std.json.Parsed(schema.GuildMember) {
        const g = self.guild();
        return g.client.rest.getMember(g.id, user_id);
    }

    pub fn fetchMany(self: *Members, limit: u32, after: ?[]const u8) !std.json.Parsed([]schema.GuildMember) {
        const g = self.guild();
        return g.client.rest.listMembers(g.id, limit, after);
    }

    pub fn kick(self: *Members, user_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.kick(g.id, user_id, reason);
    }

    pub fn ban(self: *Members, user_id: []const u8, delete_message_seconds: u32, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.ban(g.id, user_id, delete_message_seconds, reason);
    }

    pub fn unban(self: *Members, user_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.unban(g.id, user_id, reason);
    }

    pub fn pruneCount(self: *Members, days: u32, roles: []const []const u8) !std.json.Parsed(schema.PruneResult) {
        const g = self.guild();
        return g.client.rest.getPruneCount(g.id, days, roles);
    }

    pub fn prune(self: *Members, days: u32, roles: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.PruneResult) {
        const g = self.guild();
        return g.client.rest.beginPrune(g.id, days, roles, reason);
    }

    pub fn bulkBan(self: *Members, user_ids: []const []const u8, delete_message_seconds: u32, reason: ?[]const u8) !std.json.Parsed(schema.BulkBanResult) {
        const g = self.guild();
        return g.client.rest.bulkBan(g.id, user_ids, delete_message_seconds, reason);
    }

    pub fn search(self: *Members, query: []const u8, limit: u32) !std.json.Parsed([]schema.GuildMember) {
        const g = self.guild();
        return g.client.rest.searchMembers(g.id, query, limit);
    }

    pub fn fetchMe(self: *Members) !std.json.Parsed(schema.GuildMember) {
        const g = self.guild();
        return g.client.rest.fetchMe(g.id);
    }
};

pub const Roles = struct {
    _slot: usize = 0,

    fn guild(self: *Roles) *Guild {
        return @fieldParentPtr("roles", self);
    }

    pub fn fetchAll(self: *Roles) !std.json.Parsed([]schema.Role) {
        const g = self.guild();
        return g.client.rest.listRoles(g.id);
    }

    pub fn create(self: *Roles, name: []const u8, reason: ?[]const u8) !std.json.Parsed(schema.Role) {
        const g = self.guild();
        return g.client.rest.createRole(g.id, name, reason);
    }

    pub fn edit(self: *Roles, role_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.Role) {
        const g = self.guild();
        return g.client.rest.editRole(g.id, role_id, options, reason);
    }

    pub fn setPositions(self: *Roles, positions: []const client_mod.Rest.RolePosition) !std.json.Parsed([]schema.Role) {
        const g = self.guild();
        return g.client.rest.setRolePositions(g.id, positions);
    }

    pub fn delete(self: *Roles, role_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.deleteRole(g.id, role_id, reason);
    }
};

pub const GuildChannels = struct {
    _slot: usize = 0,

    fn guild(self: *GuildChannels) *Guild {
        return @fieldParentPtr("channels", self);
    }

    pub fn fetch(self: *GuildChannels, id: []const u8) !channel_mod.Channel {
        const g = self.guild();
        const key = std.fmt.parseInt(u64, id, 10) catch null;
        if (key) |k| {
            if (g.client.cache.channels.get(k)) |cached| {
                if (cached.guild_id) |gid| {
                    if (std.mem.eql(u8, gid, g.id)) return channel_mod.Channel.init(g.client, id);
                }
            }
        }
        var fetched = try g.client.rest.getChannel(id);
        if (key) |k| {
            var owned: ?std.json.Parsed(schema.Channel) = fetched;
            errdefer if (owned) |*p| p.deinit();
            try g.client.cache.channels.putParsed(k, owned.?);
            owned = null;
        } else {
            fetched.deinit();
        }
        return channel_mod.Channel.init(g.client, id);
    }

    pub fn findByName(self: *GuildChannels, name: []const u8) ?channel_mod.Channel {
        const g = self.guild();
        var it = g.client.cache.channels.iterator();
        while (it.next()) |kv| {
            const chan = &kv.value_ptr.*.value;
            if (chan.guild_id) |gid| {
                if (!std.mem.eql(u8, gid, g.id)) continue;
            } else continue;
            if (chan.name) |n| {
                if (std.mem.eql(u8, n, name)) return channel_mod.Channel.init(g.client, chan.id);
            }
        }
        return null;
    }

    pub fn create(self: *GuildChannels, options: anytype) !std.json.Parsed(schema.Channel) {
        const g = self.guild();
        return g.client.rest.createChannel(g.id, options);
    }

    pub fn fetchAll(self: *GuildChannels) !std.json.Parsed([]schema.Channel) {
        const g = self.guild();
        return g.client.rest.listGuildChannels(g.id);
    }
};

pub const Bans = struct {
    _slot: usize = 0,

    fn guild(self: *Bans) *Guild {
        return @fieldParentPtr("bans", self);
    }

    pub fn fetch(self: *Bans, user_id: []const u8) !std.json.Parsed(schema.BanEntry) {
        const g = self.guild();
        return g.client.rest.getBan(g.id, user_id);
    }

    pub fn remove(self: *Bans, user_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.unban(g.id, user_id, reason);
    }
};

pub const GuildEmojis = struct {
    _slot: usize = 0,

    fn guild(self: *GuildEmojis) *Guild {
        return @fieldParentPtr("emojis", self);
    }

    pub fn fetch(self: *GuildEmojis, emoji_id: []const u8) !std.json.Parsed(schema.GuildEmoji) {
        const g = self.guild();
        return g.client.rest.getGuildEmoji(g.id, emoji_id);
    }

    pub fn fetchAll(self: *GuildEmojis) !std.json.Parsed([]schema.GuildEmoji) {
        const g = self.guild();
        return g.client.rest.listGuildEmojis(g.id);
    }

    pub fn create(self: *GuildEmojis, name: []const u8, image: []const u8, roles: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildEmoji) {
        const g = self.guild();
        return g.client.rest.createGuildEmoji(g.id, name, image, roles, reason);
    }

    pub fn edit(self: *GuildEmojis, emoji_id: []const u8, name: ?[]const u8, roles: ?[]const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildEmoji) {
        const g = self.guild();
        return g.client.rest.editGuildEmoji(g.id, emoji_id, name, roles, reason);
    }

    pub fn delete(self: *GuildEmojis, emoji_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.deleteGuildEmoji(g.id, emoji_id, reason);
    }
};

pub const GuildStickers = struct {
    _slot: usize = 0,

    fn guild(self: *GuildStickers) *Guild {
        return @fieldParentPtr("stickers", self);
    }

    pub fn fetch(self: *GuildStickers, sticker_id: []const u8) !std.json.Parsed(schema.GuildSticker) {
        const g = self.guild();
        return g.client.rest.getGuildSticker(g.id, sticker_id);
    }

    pub fn fetchAll(self: *GuildStickers) !std.json.Parsed([]schema.GuildSticker) {
        const g = self.guild();
        return g.client.rest.listGuildStickers(g.id);
    }

    pub fn delete(self: *GuildStickers, sticker_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.deleteGuildSticker(g.id, sticker_id, reason);
    }
};

pub const GuildScheduledEvents = struct {
    _slot: usize = 0,

    fn guild(self: *GuildScheduledEvents) *Guild {
        return @fieldParentPtr("scheduledEvents", self);
    }

    pub fn fetch(self: *GuildScheduledEvents, event_id: []const u8) !std.json.Parsed(schema.GuildScheduledEvent) {
        const g = self.guild();
        return g.client.rest.getScheduledEvent(g.id, event_id);
    }

    pub fn fetchAll(self: *GuildScheduledEvents) !std.json.Parsed([]schema.GuildScheduledEvent) {
        const g = self.guild();
        return g.client.rest.listScheduledEvents(g.id);
    }

    pub fn create(self: *GuildScheduledEvents, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.GuildScheduledEvent) {
        const g = self.guild();
        return g.client.rest.createScheduledEvent(g.id, options, reason);
    }

    pub fn edit(self: *GuildScheduledEvents, event_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.GuildScheduledEvent) {
        const g = self.guild();
        return g.client.rest.editScheduledEvent(g.id, event_id, options, reason);
    }

    pub fn delete(self: *GuildScheduledEvents, event_id: []const u8) !void {
        const g = self.guild();
        return g.client.rest.deleteScheduledEvent(g.id, event_id);
    }

    pub fn fetchSubscribers(self: *GuildScheduledEvents, event_id: []const u8, limit: u32) !std.json.Parsed([]schema.GuildScheduledEventUser) {
        const g = self.guild();
        return g.client.rest.getScheduledEventUsers(g.id, event_id, limit, true);
    }
};

pub const GuildAutoModeration = struct {
    _slot: usize = 0,

    fn guild(self: *GuildAutoModeration) *Guild {
        return @fieldParentPtr("autoModeration", self);
    }

    pub fn fetch(self: *GuildAutoModeration, rule_id: []const u8) !std.json.Parsed(schema.AutoModerationRule) {
        const g = self.guild();
        return g.client.rest.getAutoModerationRule(g.id, rule_id);
    }

    pub fn fetchAll(self: *GuildAutoModeration) !std.json.Parsed([]schema.AutoModerationRule) {
        const g = self.guild();
        return g.client.rest.listAutoModerationRules(g.id);
    }

    pub fn create(self: *GuildAutoModeration, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.AutoModerationRule) {
        const g = self.guild();
        return g.client.rest.createAutoModerationRule(g.id, options, reason);
    }

    pub fn edit(self: *GuildAutoModeration, rule_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.AutoModerationRule) {
        const g = self.guild();
        return g.client.rest.editAutoModerationRule(g.id, rule_id, options, reason);
    }

    pub fn delete(self: *GuildAutoModeration, rule_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.deleteAutoModerationRule(g.id, rule_id, reason);
    }
};

pub const GuildStageInstances = struct {
    _slot: usize = 0,

    fn guild(self: *GuildStageInstances) *Guild {
        return @fieldParentPtr("stageInstances", self);
    }

    pub fn fetch(self: *GuildStageInstances, channel_id: []const u8) !std.json.Parsed(schema.StageInstance) {
        const g = self.guild();
        return g.client.rest.getStageInstance(channel_id);
    }

    pub fn create(self: *GuildStageInstances, channel_id: []const u8, topic: []const u8, privacy_level: u32, reason: ?[]const u8) !std.json.Parsed(schema.StageInstance) {
        const g = self.guild();
        return g.client.rest.createStageInstance(channel_id, topic, privacy_level, reason);
    }

    pub fn edit(self: *GuildStageInstances, channel_id: []const u8, topic: ?[]const u8, privacy_level: ?u32, reason: ?[]const u8) !std.json.Parsed(schema.StageInstance) {
        const g = self.guild();
        return g.client.rest.editStageInstance(channel_id, topic, privacy_level, reason);
    }

    pub fn delete(self: *GuildStageInstances, channel_id: []const u8, reason: ?[]const u8) !void {
        const g = self.guild();
        return g.client.rest.deleteStageInstance(channel_id, reason);
    }
};

pub const GuildCommands = struct {
    _slot: usize = 0,

    fn guild(self: *GuildCommands) *Guild {
        return @fieldParentPtr("commands", self);
    }

    pub fn set(self: *GuildCommands, application_id: []const u8, commands: anytype) !std.json.Parsed([]schema.ApplicationCommand) {
        const g = self.guild();
        const T = @TypeOf(commands);
        if (T == []const u8) {
            return g.client.rest.registerGuildCommands(application_id, g.id, commands);
        }
        const json = try std.json.Stringify.valueAlloc(g.client.allocator, commands, .{ .emit_null_optional_fields = false });
        defer g.client.allocator.free(json);
        return g.client.rest.registerGuildCommands(application_id, g.id, json);
    }

    pub fn fetchPermissions(self: *GuildCommands, application_id: []const u8) !std.json.Parsed([]schema.CommandPermissions) {
        const g = self.guild();
        return g.client.rest.fetchCommandPermissions(application_id, g.id);
    }
};

pub const GuildInvites = struct {
    _slot: usize = 0,

    fn guild(self: *GuildInvites) *Guild {
        return @fieldParentPtr("invites", self);
    }

    pub fn fetch(self: *GuildInvites) !std.json.Parsed([]schema.Invite) {
        const g = self.guild();
        return g.client.rest.fetchGuildInvites(g.id);
    }
};

pub const GuildWebhooks = struct {
    _slot: usize = 0,

    fn guild(self: *GuildWebhooks) *Guild {
        return @fieldParentPtr("webhooks", self);
    }

    pub fn fetch(self: *GuildWebhooks) !std.json.Parsed([]schema.Webhook) {
        const g = self.guild();
        return g.client.rest.getGuildWebhooks(g.id);
    }
};

pub const GuildVoice = struct {
    _slot: usize = 0,

    fn guild(self: *GuildVoice) *Guild {
        return @fieldParentPtr("voice", self);
    }

    pub fn join(self: *GuildVoice, channel_id: []const u8) !voice_mod.VoiceConnection {
        const g = self.guild();
        return g.client.joinVoiceChannel(.{
            .guild_id = g.id,
            .channel_id = channel_id,
        });
    }

    pub fn leave(self: *GuildVoice) !void {
        const g = self.guild();
        return g.client.leaveVoiceChannel(g.id);
    }
};
