const std = @import("std");
const schema = @import("./schema.zig");

pub const create_instant_invite: u64 = 1 << 0;
pub const kick_members: u64 = 1 << 1;
pub const ban_members: u64 = 1 << 2;
pub const administrator: u64 = 1 << 3;
pub const manage_channels: u64 = 1 << 4;
pub const manage_guild: u64 = 1 << 5;
pub const add_reactions: u64 = 1 << 6;
pub const view_audit_log: u64 = 1 << 7;
pub const priority_speaker: u64 = 1 << 8;
pub const stream: u64 = 1 << 9;
pub const view_channel: u64 = 1 << 10;
pub const send_messages: u64 = 1 << 11;
pub const send_tts_messages: u64 = 1 << 12;
pub const manage_messages: u64 = 1 << 13;
pub const embed_links: u64 = 1 << 14;
pub const attach_files: u64 = 1 << 15;
pub const read_message_history: u64 = 1 << 16;
pub const mention_everyone: u64 = 1 << 17;
pub const use_external_emojis: u64 = 1 << 18;
pub const view_guild_insights: u64 = 1 << 19;
pub const connect: u64 = 1 << 20;
pub const speak: u64 = 1 << 21;
pub const mute_members: u64 = 1 << 22;
pub const deafen_members: u64 = 1 << 23;
pub const move_members: u64 = 1 << 24;
pub const use_vad: u64 = 1 << 25;
pub const change_nickname: u64 = 1 << 26;
pub const manage_nicknames: u64 = 1 << 27;
pub const manage_roles: u64 = 1 << 28;
pub const manage_webhooks: u64 = 1 << 29;
pub const manage_guild_expressions: u64 = 1 << 30;
pub const use_application_commands: u64 = 1 << 31;
pub const request_to_speak: u64 = 1 << 32;
pub const manage_events: u64 = 1 << 33;
pub const manage_threads: u64 = 1 << 34;
pub const create_public_threads: u64 = 1 << 35;
pub const create_private_threads: u64 = 1 << 36;
pub const use_external_stickers: u64 = 1 << 37;
pub const send_messages_in_threads: u64 = 1 << 38;
pub const use_embedded_activities: u64 = 1 << 39;
pub const moderate_members: u64 = 1 << 40;
pub const view_creator_monetization_analytics: u64 = 1 << 41;
pub const use_soundboard: u64 = 1 << 42;
pub const create_guild_expressions: u64 = 1 << 43;
pub const create_events: u64 = 1 << 44;
pub const use_external_sounds: u64 = 1 << 45;
pub const send_voice_messages: u64 = 1 << 46;
pub const set_voice_channel_status: u64 = 1 << 48;
pub const send_polls: u64 = 1 << 49;
pub const use_external_apps: u64 = 1 << 50;
pub const pin_messages: u64 = 1 << 51;
pub const bypass_slowmode: u64 = 1 << 52;

pub const Bits = enum(u64) {
    create_instant_invite = 1 << 0,
    kick_members = 1 << 1,
    ban_members = 1 << 2,
    administrator = 1 << 3,
    manage_channels = 1 << 4,
    manage_guild = 1 << 5,
    add_reactions = 1 << 6,
    view_audit_log = 1 << 7,
    priority_speaker = 1 << 8,
    stream = 1 << 9,
    view_channel = 1 << 10,
    send_messages = 1 << 11,
    send_tts_messages = 1 << 12,
    manage_messages = 1 << 13,
    embed_links = 1 << 14,
    attach_files = 1 << 15,
    read_message_history = 1 << 16,
    mention_everyone = 1 << 17,
    use_external_emojis = 1 << 18,
    view_guild_insights = 1 << 19,
    connect = 1 << 20,
    speak = 1 << 21,
    mute_members = 1 << 22,
    deafen_members = 1 << 23,
    move_members = 1 << 24,
    use_vad = 1 << 25,
    change_nickname = 1 << 26,
    manage_nicknames = 1 << 27,
    manage_roles = 1 << 28,
    manage_webhooks = 1 << 29,
    manage_guild_expressions = 1 << 30,
    use_application_commands = 1 << 31,
    request_to_speak = 1 << 32,
    manage_events = 1 << 33,
    manage_threads = 1 << 34,
    create_public_threads = 1 << 35,
    create_private_threads = 1 << 36,
    use_external_stickers = 1 << 37,
    send_messages_in_threads = 1 << 38,
    use_embedded_activities = 1 << 39,
    moderate_members = 1 << 40,
    view_creator_monetization_analytics = 1 << 41,
    use_soundboard = 1 << 42,
    create_guild_expressions = 1 << 43,
    create_events = 1 << 44,
    use_external_sounds = 1 << 45,
    send_voice_messages = 1 << 46,
    set_voice_channel_status = 1 << 48,
    send_polls = 1 << 49,
    use_external_apps = 1 << 50,
    pin_messages = 1 << 51,
    bypass_slowmode = 1 << 52,
};

pub const PermissionFlagsBits = struct {
    pub const CreateInstantInvite: u64 = create_instant_invite;
    pub const KickMembers: u64 = kick_members;
    pub const BanMembers: u64 = ban_members;
    pub const Administrator: u64 = administrator;
    pub const ManageChannels: u64 = manage_channels;
    pub const ManageGuild: u64 = manage_guild;
    pub const AddReactions: u64 = add_reactions;
    pub const ViewAuditLog: u64 = view_audit_log;
    pub const PrioritySpeaker: u64 = priority_speaker;
    pub const Stream: u64 = stream;
    pub const ViewChannel: u64 = view_channel;
    pub const SendMessages: u64 = send_messages;
    pub const SendTTSMessages: u64 = send_tts_messages;
    pub const ManageMessages: u64 = manage_messages;
    pub const EmbedLinks: u64 = embed_links;
    pub const AttachFiles: u64 = attach_files;
    pub const ReadMessageHistory: u64 = read_message_history;
    pub const MentionEveryone: u64 = mention_everyone;
    pub const UseExternalEmojis: u64 = use_external_emojis;
    pub const ViewGuildInsights: u64 = view_guild_insights;
    pub const Connect: u64 = connect;
    pub const Speak: u64 = speak;
    pub const MuteMembers: u64 = mute_members;
    pub const DeafenMembers: u64 = deafen_members;
    pub const MoveMembers: u64 = move_members;
    pub const UseVAD: u64 = use_vad;
    pub const ChangeNickname: u64 = change_nickname;
    pub const ManageNicknames: u64 = manage_nicknames;
    pub const ManageRoles: u64 = manage_roles;
    pub const ManageWebhooks: u64 = manage_webhooks;
    pub const ManageGuildExpressions: u64 = manage_guild_expressions;
    pub const UseApplicationCommands: u64 = use_application_commands;
    pub const RequestToSpeak: u64 = request_to_speak;
    pub const ManageEvents: u64 = manage_events;
    pub const ManageThreads: u64 = manage_threads;
    pub const CreatePublicThreads: u64 = create_public_threads;
    pub const CreatePrivateThreads: u64 = create_private_threads;
    pub const UseExternalStickers: u64 = use_external_stickers;
    pub const SendMessagesInThreads: u64 = send_messages_in_threads;
    pub const UseEmbeddedActivities: u64 = use_embedded_activities;
    pub const ModerateMembers: u64 = moderate_members;
    pub const ViewCreatorMonetizationAnalytics: u64 = view_creator_monetization_analytics;
    pub const UseSoundboard: u64 = use_soundboard;
    pub const CreateGuildExpressions: u64 = create_guild_expressions;
    pub const CreateEvents: u64 = create_events;
    pub const UseExternalSounds: u64 = use_external_sounds;
    pub const SendVoiceMessages: u64 = send_voice_messages;
    pub const SetVoiceChannelStatus: u64 = set_voice_channel_status;
    pub const SendPolls: u64 = send_polls;
    pub const UseExternalApps: u64 = use_external_apps;
    pub const PinMessages: u64 = pin_messages;
    pub const BypassSlowmode: u64 = bypass_slowmode;
};

pub const PermissionsBitField = struct {
    pub const Flags = PermissionFlagsBits;
};

pub fn of(comptime flags: anytype) u64 {
    const info = @typeInfo(@TypeOf(flags));
    if (info == .array or (info == .@"struct" and info.@"struct".is_tuple)) {
        var out: u64 = 0;
        inline for (flags) |f| out |= toBits(f);
        return out;
    }
    return toBits(flags);
}

fn toBits(comptime f: anytype) u64 {
    const FT = @TypeOf(f);
    if (FT == Bits) return @intFromEnum(f);
    if (FT == u64 or FT == comptime_int) return f;
    const b: Bits = f;
    return @intFromEnum(b);
}

pub fn has(value: u64, flag: u64) bool {
    return value & flag != 0;
}

pub fn all() u64 {
    return std.math.maxInt(u64);
}

pub fn parse(text: []const u8) u64 {
    return std.fmt.parseInt(u64, text, 10) catch 0;
}

pub fn applyOverwrite(bits: u64, allow: u64, deny: u64) u64 {
    return (bits & ~deny) | allow;
}

pub fn compareRolePositions(a: schema.Role, b: schema.Role) std.math.Order {
    if (a.position != b.position) return std.math.order(a.position, b.position);
    // Snowflakes são decimais sem zeros à esquerda: o mais longo é o maior;
    // em igual comprimento, a ordem lexicográfica equivale à numérica.
    // Evita parseInt por comparação (comparador de sort é caminho quente).
    if (a.id.len != b.id.len) return std.math.order(a.id.len, b.id.len);
    return std.mem.order(u8, a.id, b.id);
}

pub fn resolveChannelPermissions(base: u64, user_id: []const u8, role_ids: []const []const u8, guild_id: []const u8, overwrites: []const schema.PermissionOverwrite) u64 {
    if (has(base, administrator)) return all();
    var bits = base;
    for (overwrites) |o| {
        if (o.@"type" != @intFromEnum(schema.OverwriteType.role)) continue;
        if (!std.mem.eql(u8, o.id, guild_id)) continue;
        bits = applyOverwrite(bits, parse(o.allow), parse(o.deny));
    }
    var allow: u64 = 0;
    var deny: u64 = 0;
    for (role_ids) |role_id| {
        for (overwrites) |o| {
            if (o.@"type" != @intFromEnum(schema.OverwriteType.role)) continue;
            if (!std.mem.eql(u8, o.id, role_id)) continue;
            allow |= parse(o.allow);
            deny |= parse(o.deny);
        }
    }
    bits = (bits & ~deny) | allow;
    for (overwrites) |o| {
        if (o.@"type" != @intFromEnum(schema.OverwriteType.member)) continue;
        if (!std.mem.eql(u8, o.id, user_id)) continue;
        bits = applyOverwrite(bits, parse(o.allow), parse(o.deny));
    }
    return bits;
}

pub fn resolveMember(roles: []const schema.Role, member: schema.GuildMember, owner_id: []const u8) u64 {
    const user = member.user orelse return 0;
    if (std.mem.eql(u8, user.id, owner_id)) return all();
    var bits: u64 = 0;
    for (member.roles) |role_id| {
        for (roles) |role| {
            if (std.mem.eql(u8, role.id, role_id)) {
                bits |= parse(role.permissions);
                break;
            }
        }
    }
    if (has(bits, administrator)) return all();
    return bits;
}

pub const Flags = struct {
    bits: u64 = 0,

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
