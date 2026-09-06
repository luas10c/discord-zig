const std = @import("std");
const schema = @import("./schema.zig");
const client_mod = @import("./client.zig");
const message_mod = @import("./message.zig");
const collector_mod = @import("./collector.zig");

pub const Channels = struct {
    _slot: usize = 0,

    fn client(self: *Channels) *client_mod.Client {
        return @alignCast(@fieldParentPtr("channels", self));
    }

    pub fn fetch(self: *Channels, id: []const u8) !Channel {
        const c = self.client();
        const key = std.fmt.parseInt(u64, id, 10) catch null;
        if (key) |k| {
            if (c.cache.channels.get(k) != null) return Channel.init(c, id);
        }
        var fetched = try c.rest.getChannel(id);
        if (key) |k| {
            var owned: ?std.json.Parsed(schema.Channel) = fetched;
            errdefer if (owned) |*p| p.deinit();
            try c.cache.channels.putParsed(k, owned.?);
            owned = null;
        } else {
            fetched.deinit();
        }
        return Channel.init(c, id);
    }
};

pub const Channel = struct {
    client: *client_mod.Client,
    id: []const u8,
    messages: Messages = .{},
    permissionOverwrites: PermissionOverwrites = .{},
    invites: Invites = .{},
    threads: Threads = .{},
    webhooks: ChannelWebhooks = .{},

    pub fn init(client: *client_mod.Client, id: []const u8) Channel {
        return .{ .client = client, .id = id };
    }

    pub fn fetch(self: Channel) !std.json.Parsed(schema.Channel) {
        return self.client.rest.getChannel(self.id);
    }

    pub fn edit(self: Channel, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        return self.client.rest.editChannelFull(self.id, options, reason);
    }

    pub fn delete(self: Channel, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        return self.client.rest.deleteChannel(self.id, reason);
    }

    pub fn send(self: Channel, content: []const u8) !std.json.Parsed(schema.Message) {
        return self.client.rest.createMessage(self.id, content);
    }

    pub fn sendRich(self: Channel, opts: client_mod.Rest.MessageCreate) !std.json.Parsed(schema.Message) {
        return self.client.rest.createRichMessage(self.id, opts);
    }

    pub fn sendPoll(self: Channel, create: schema.PollCreate) !std.json.Parsed(schema.Message) {
        return self.client.rest.createPollMessage(self.id, create);
    }

    pub fn sendTyping(self: Channel) !void {
        return self.client.rest.typing(self.id);
    }

    pub fn bulkDelete(self: Channel, message_ids: []const []const u8) !void {
        return self.client.rest.deleteMessagesBulk(self.id, message_ids);
    }

    pub fn setStatus(self: Channel, status: []const u8, reason: ?[]const u8) !void {
        return self.client.rest.setVoiceChannelStatus(self.id, status, reason);
    }

    pub fn createMessageComponentCollector(self: Channel, options: collector_mod.InteractionCollectorOptions) !*collector_mod.InteractionCollector {
        return self.client.createMessageComponentCollector(options);
    }
};

pub const Messages = struct {
    _slot: usize = 0,

    fn channel(self: *Messages) *Channel {
        return @fieldParentPtr("messages", self);
    }

    pub fn message(self: *Messages, message_id: []const u8) message_mod.Message {
        const c = self.channel();
        return message_mod.Message.init(c.client, c.id, message_id);
    }

    pub fn fetch(self: *Messages, message_id: []const u8) !std.json.Parsed(schema.Message) {
        const c = self.channel();
        return c.client.rest.getMessage(c.id, message_id);
    }

    pub fn fetchMany(self: *Messages, limit: u32) !std.json.Parsed([]schema.Message) {
        const c = self.channel();
        return c.client.rest.listMessages(c.id, limit);
    }

    pub fn reply(self: *Messages, message_id: []const u8, content: []const u8) !std.json.Parsed(schema.Message) {
        const c = self.channel();
        return c.client.rest.replyTo(c.id, message_id, content);
    }

    pub fn edit(self: *Messages, message_id: []const u8, content: []const u8) !std.json.Parsed(schema.Message) {
        const c = self.channel();
        return c.client.rest.editMessage(c.id, message_id, content);
    }

    pub fn delete(self: *Messages, message_id: []const u8, reason: ?[]const u8) !void {
        const c = self.channel();
        return c.client.rest.deleteMessage(c.id, message_id, reason);
    }

    pub fn react(self: *Messages, message_id: []const u8, emoji: []const u8) !void {
        const c = self.channel();
        return c.client.rest.react(c.id, message_id, emoji);
    }

    pub fn unreact(self: *Messages, message_id: []const u8, emoji: []const u8) !void {
        const c = self.channel();
        return c.client.rest.unreact(c.id, message_id, emoji);
    }

    pub fn pin(self: *Messages, message_id: []const u8, reason: ?[]const u8) !void {
        const c = self.channel();
        return c.client.rest.pinMessage(c.id, message_id, reason);
    }

    pub fn unpin(self: *Messages, message_id: []const u8, reason: ?[]const u8) !void {
        const c = self.channel();
        return c.client.rest.unpinMessage(c.id, message_id, reason);
    }

    pub fn endPoll(self: *Messages, message_id: []const u8) !std.json.Parsed(schema.Message) {
        const c = self.channel();
        return c.client.rest.endPoll(c.id, message_id);
    }

    pub fn fetchPollAnswerVoters(self: *Messages, message_id: []const u8, answer_id: u64, after: ?[]const u8, limit: u32) !std.json.Parsed(schema.PollAnswerVoters) {
        const c = self.channel();
        return c.client.rest.fetchPollAnswerVoters(c.id, message_id, answer_id, after, limit);
    }
};

pub const PermissionOverwrite = struct {
    id: []const u8,
    kind: schema.OverwriteType = .role,
    allow: []const u64 = &.{},
    deny: []const u64 = &.{},
};
pub const Overwrite = PermissionOverwrite;

pub const PermissionOverwrites = struct {
    _slot: usize = 0,

    fn channel(self: *PermissionOverwrites) *Channel {
        return @fieldParentPtr("permissionOverwrites", self);
    }

    pub fn set(self: *PermissionOverwrites, overwrites: anytype, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        const c = self.channel();
        return c.client.rest.setChannelPermissions(c.id, overwrites, reason);
    }

    pub fn edit(self: *PermissionOverwrites, overwrites: anytype) !void {
        var parsed = try self.set(overwrites, null);
        parsed.deinit();
    }

    pub fn editTarget(self: *PermissionOverwrites, target_id: []const u8, kind: schema.OverwriteType, allow: u64, deny: u64, reason: ?[]const u8) !void {
        const c = self.channel();
        return c.client.rest.editChannelPermissions(c.id, target_id, kind, allow, deny, reason);
    }

    pub fn editOptions(self: *PermissionOverwrites, target_id: []const u8, options: anytype, reason: ?[]const u8) !void {
        const c = self.channel();
        const O = @TypeOf(options);
        const kind: schema.OverwriteType = if (@hasField(O, "kind")) blk: {
            const K = @TypeOf(options.kind);
            break :blk if (K == schema.OverwriteType) options.kind else @enumFromInt(options.kind);
        } else if (@hasField(O, "type")) blk: {
            const TP = @TypeOf(options.@"type");
            break :blk if (TP == schema.OverwriteType) options.@"type" else @enumFromInt(options.@"type");
        } else .role;
        const allow = if (@hasField(O, "allow")) client_mod.Rest.parsePermissionValue(options.allow) else 0;
        const deny = if (@hasField(O, "deny")) client_mod.Rest.parsePermissionValue(options.deny) else 0;
        return c.client.rest.editChannelPermissions(c.id, target_id, kind, allow, deny, reason);
    }

    pub fn delete(self: *PermissionOverwrites, target_id: []const u8, reason: ?[]const u8) !void {
        const c = self.channel();
        return c.client.rest.deleteChannelPermissions(c.id, target_id, reason);
    }
};

pub const Invites = struct {
    _slot: usize = 0,

    fn channel(self: *Invites) *Channel {
        return @fieldParentPtr("invites", self);
    }

    pub fn fetch(self: *Invites) !std.json.Parsed([]schema.Invite) {
        const c = self.channel();
        return c.client.rest.fetchInvites(c.id);
    }

    pub fn create(self: *Invites, max_age: u32, max_uses: u32) !std.json.Parsed(schema.Invite) {
        const c = self.channel();
        return c.client.rest.createInvite(c.id, max_age, max_uses);
    }

    pub fn delete(self: *Invites, code: []const u8, reason: ?[]const u8) !void {
        const c = self.channel();
        return c.client.rest.deleteInvite(code, reason);
    }
};

pub const Threads = struct {
    _slot: usize = 0,
    members: ThreadMembers = .{},

    fn channel(self: *Threads) *Channel {
        return @fieldParentPtr("threads", self);
    }

    pub fn startFromMessage(self: *Threads, message_id: []const u8, name: []const u8, auto_archive_minutes: u32) !std.json.Parsed(schema.Channel) {
        const c = self.channel();
        return c.client.rest.startThreadFromMessage(c.id, message_id, name, auto_archive_minutes);
    }

    pub fn start(self: *Threads, name: []const u8, kind: schema.ChannelType, auto_archive_minutes: u32) !std.json.Parsed(schema.Channel) {
        const c = self.channel();
        return c.client.rest.startThread(c.id, name, kind, auto_archive_minutes);
    }

    pub fn join(self: *Threads) !void {
        const c = self.channel();
        return c.client.rest.joinThread(c.id);
    }

    pub fn leave(self: *Threads) !void {
        const c = self.channel();
        return c.client.rest.leaveThread(c.id);
    }

    pub fn addMember(self: *Threads, user_id: []const u8) !void {
        const c = self.channel();
        return c.client.rest.addThreadMember(c.id, user_id);
    }

    pub fn removeMember(self: *Threads, user_id: []const u8) !void {
        const c = self.channel();
        return c.client.rest.removeThreadMember(c.id, user_id);
    }

    pub fn fetchMembers(self: *Threads, limit: u32, with_member: bool) !std.json.Parsed([]schema.ThreadMember) {
        const c = self.channel();
        return c.client.rest.listThreadMembers(c.id, limit, with_member);
    }

    pub fn fetchArchivedPublic(self: *Threads, before: ?[]const u8, limit: u32) !std.json.Parsed(schema.ThreadListActive) {
        const c = self.channel();
        return c.client.rest.fetchArchivedPublicThreads(c.id, before, limit);
    }

    pub fn fetchArchivedPrivate(self: *Threads, before: ?[]const u8, limit: u32) !std.json.Parsed(schema.ThreadListActive) {
        const c = self.channel();
        return c.client.rest.fetchArchivedPrivateThreads(c.id, before, limit);
    }

    pub fn fetchMember(self: *Threads, user_id: []const u8) !std.json.Parsed(schema.ThreadMember) {
        const c = self.channel();
        return c.client.rest.getThreadMember(c.id, user_id, false);
    }

    pub fn listMembers(self: *Threads, limit: u32) !std.json.Parsed([]schema.ThreadMember) {
        const c = self.channel();
        return c.client.rest.listThreadMembers(c.id, limit, false);
    }

    pub fn setArchived(self: *Threads, archived: bool) !std.json.Parsed(schema.Channel) {
        const c = self.channel();
        return c.client.rest.setThreadArchived(c.id, archived);
    }
};

pub const ThreadMembers = struct {
    _slot: usize = 0,

    fn threads(self: *ThreadMembers) *Threads {
        return @alignCast(@fieldParentPtr("members", self));
    }

    pub fn fetch(self: *ThreadMembers, user_id: []const u8) !std.json.Parsed(schema.ThreadMember) {
        return self.threads().fetchMember(user_id);
    }

    pub fn fetchAll(self: *ThreadMembers, limit: u32) !std.json.Parsed([]schema.ThreadMember) {
        return self.threads().listMembers(limit);
    }

    pub fn add(self: *ThreadMembers, user_id: []const u8) !void {
        return self.threads().addMember(user_id);
    }

    pub fn remove(self: *ThreadMembers, user_id: []const u8) !void {
        return self.threads().removeMember(user_id);
    }
};

pub const ChannelWebhooks = struct {
    _slot: usize = 0,

    fn channel(self: *ChannelWebhooks) *Channel {
        return @fieldParentPtr("webhooks", self);
    }

    pub fn fetch(self: *ChannelWebhooks) !std.json.Parsed([]schema.Webhook) {
        const c = self.channel();
        return c.client.rest.getChannelWebhooks(c.id);
    }

    pub fn create(self: *ChannelWebhooks, name: []const u8) !std.json.Parsed(schema.Webhook) {
        const c = self.channel();
        return c.client.rest.createWebhook(c.id, name);
    }
};
