pub const crossposted: u32 = 1 << 0;
pub const is_crossposted: u32 = 1 << 1;
pub const suppress_embeds: u32 = 1 << 2;
pub const source_message_deleted: u32 = 1 << 3;
pub const urgent: u32 = 1 << 4;
pub const has_thread: u32 = 1 << 5;
pub const ephemeral: u32 = 1 << 6;
pub const loading: u32 = 1 << 7;
pub const failed_to_mention_some_roles_in_thread: u32 = 1 << 8;
pub const suppress_notifications: u32 = 1 << 12;
pub const is_voice_message: u32 = 1 << 13;
pub const has_snapshot: u32 = 1 << 14;
pub const is_components_v2: u32 = 1 << 15;

pub const Bits = enum(u32) {
    crossposted = 1 << 0,
    is_crossposted = 1 << 1,
    suppress_embeds = 1 << 2,
    source_message_deleted = 1 << 3,
    urgent = 1 << 4,
    has_thread = 1 << 5,
    ephemeral = 1 << 6,
    loading = 1 << 7,
    failed_to_mention_some_roles_in_thread = 1 << 8,
    suppress_notifications = 1 << 12,
    is_voice_message = 1 << 13,
    has_snapshot = 1 << 14,
    is_components_v2 = 1 << 15,
};

pub const MessageFlags = struct {
    pub const Crossposted: u32 = crossposted;
    pub const IsCrossposted: u32 = is_crossposted;
    pub const SuppressEmbeds: u32 = suppress_embeds;
    pub const SourceMessageDeleted: u32 = source_message_deleted;
    pub const Urgent: u32 = urgent;
    pub const HasThread: u32 = has_thread;
    pub const Ephemeral: u32 = ephemeral;
    pub const Loading: u32 = loading;
    pub const FailedToMentionSomeRolesInThread: u32 = failed_to_mention_some_roles_in_thread;
    pub const SuppressNotifications: u32 = suppress_notifications;
    pub const IsVoiceMessage: u32 = is_voice_message;
    pub const HasSnapshot: u32 = has_snapshot;
    pub const IsComponentsV2: u32 = is_components_v2;
};

pub fn of(comptime flags: anytype) u32 {
    const info = @typeInfo(@TypeOf(flags));
    if (info == .array or (info == .@"struct" and info.@"struct".is_tuple)) {
        var out: u32 = 0;
        inline for (flags) |f| out |= toBits(f);
        return out;
    }
    return toBits(flags);
}

fn toBits(comptime f: anytype) u32 {
    const FT = @TypeOf(f);
    if (FT == Bits) return @intFromEnum(f);
    if (FT == u32 or FT == comptime_int) return f;
    @compileError("use message.MessageFlags.* or message.Bits.* instead of a bare flag literal");
}

pub fn has(value: u32, flag: u32) bool {
    return value & flag != 0;
}

pub const Flags = struct {
    bits: u32 = 0,

    pub fn init(comptime flags: anytype) Flags {
        return .{ .bits = of(flags) };
    }

    pub fn has(self: Flags, comptime flag: anytype) bool {
        return self.bits & toBits(flag) != 0;
    }

    pub fn add(self: *Flags, comptime flags: anytype) void {
        self.bits |= of(flags);
    }

    pub fn remove(self: *Flags, comptime flags: anytype) void {
        self.bits &= ~of(flags);
    }
};

const std = @import("std");
const schema = @import("./schema.zig");
const client_mod = @import("./client.zig");
const collector_mod = @import("./collector.zig");

pub const Message = struct {
    client: *client_mod.Client,
    channel_id: []const u8,
    id: []const u8,
    poll: MessagePoll = .{},
    reactions: MessageReactions = .{},

    pub fn init(client: *client_mod.Client, channel_id: []const u8, id: []const u8) Message {
        return .{ .client = client, .channel_id = channel_id, .id = id };
    }

    pub fn reply(self: Message, content: []const u8) !std.json.Parsed(schema.Message) {
        return self.client.rest.replyTo(self.channel_id, self.id, content);
    }

    pub fn edit(self: Message, content: []const u8) !std.json.Parsed(schema.Message) {
        return self.client.rest.editMessage(self.channel_id, self.id, content);
    }

    pub fn delete(self: Message) !void {
        return self.client.rest.deleteMessage(self.channel_id, self.id);
    }

    pub fn react(self: Message, emoji: []const u8) !void {
        return self.client.rest.addReaction(self.channel_id, self.id, emoji);
    }

    pub fn pin(self: Message) !void {
        return self.client.rest.pinMessage(self.channel_id, self.id);
    }

    pub fn unpin(self: Message) !void {
        return self.client.rest.unpinMessage(self.channel_id, self.id);
    }

    pub fn createMessageComponentCollector(self: Message, options: collector_mod.InteractionCollectorOptions) !*collector_mod.InteractionCollector {
        var opts = options;
        opts.message_id = self.id;
        return self.client.createMessageComponentCollector(opts);
    }
};

pub const MessagePoll = struct {
    _slot: usize = 0,

    fn message(self: *MessagePoll) *Message {
        return @alignCast(@fieldParentPtr("poll", self));
    }

    pub fn end(self: *MessagePoll) !std.json.Parsed(schema.Message) {
        const m = self.message();
        return m.client.rest.endPoll(m.channel_id, m.id);
    }

    pub fn getAnswerVoters(self: *MessagePoll, answer_id: u32, limit: u32) !std.json.Parsed(schema.PollAnswerVotersResponse) {
        const m = self.message();
        return m.client.rest.getPollAnswerVoters(m.channel_id, m.id, answer_id, limit);
    }
};

pub const MessageReactions = struct {
    _slot: usize = 0,

    fn message(self: *MessageReactions) *Message {
        return @alignCast(@fieldParentPtr("reactions", self));
    }

    pub fn add(self: *MessageReactions, emoji: []const u8) !void {
        const m = self.message();
        return m.client.rest.addReaction(m.channel_id, m.id, emoji);
    }

    pub fn remove(self: *MessageReactions, emoji: []const u8, user_id: ?[]const u8) !void {
        const m = self.message();
        if (user_id) |uid| {
            return m.client.rest.deleteUserReaction(m.channel_id, m.id, emoji, uid);
        }
        return m.client.rest.deleteReaction(m.channel_id, m.id, emoji);
    }

    pub fn removeAll(self: *MessageReactions) !void {
        const m = self.message();
        return m.client.rest.deleteAllReactions(m.channel_id, m.id);
    }

    pub fn removeEmoji(self: *MessageReactions, emoji: []const u8) !void {
        const m = self.message();
        return m.client.rest.deleteReactionEmoji(m.channel_id, m.id, emoji);
    }
};
