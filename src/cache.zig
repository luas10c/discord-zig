const std = @import("std");
const schema = @import("./schema.zig");
const snowflake = @import("./snowflake.zig");
const events = @import("./events.zig");

pub const default_message_limit: usize = 200;

pub const Limits = struct {
    guilds: ?usize = null,
    channels: ?usize = null,
    messages: ?usize = default_message_limit,
    guild_members: ?usize = null,
    users: ?usize = null,
    roles: ?usize = null,
    threads: ?usize = null,
    thread_members: ?usize = null,
    emojis: ?usize = null,
    stickers: ?usize = null,
    bans: ?usize = null,
    invites: ?usize = null,
    scheduled_events: ?usize = null,
    stage_instances: ?usize = null,
    presences: ?usize = null,
    voice_states: ?usize = null,
    application_commands: ?usize = null,
    auto_moderation_rules: ?usize = null,
    reactions: ?usize = null,
};

pub const valid_managers = [_][]const u8{
    "GuildMemberManager",
    "MessageManager",
    "GuildManager",
    "ChannelManager",
    "UserManager",
    "RoleManager",
    "ThreadManager",
    "ThreadMemberManager",
    "GuildEmojiManager",
    "BaseGuildEmojiManager",
    "GuildStickerManager",
    "GuildBanManager",
    "GuildInviteManager",
    "GuildScheduledEventManager",
    "StageInstanceManager",
    "PresenceManager",
    "VoiceStateManager",
    "ApplicationCommandManager",
    "AutoModerationRuleManager",
    "ReactionManager",
    "ReactionUserManager",
};

fn getLimitValue(comptime T: type, val: T, comptime name: []const u8) ?usize {
    if (@hasField(T, name)) {
        const raw = @field(val, name);
        const RT = @TypeOf(raw);
        if (RT == @TypeOf(null)) return null;
        if (RT == ?usize) return raw;
        if (@typeInfo(RT) == .optional) {
            if (raw) |u| return @as(usize, @intCast(u));
            return null;
        }
        return @as(usize, @intCast(raw));
    }
    return null;
}

fn isValidManager(comptime name: []const u8) bool {
    inline for (valid_managers) |valid| {
        if (std.mem.eql(u8, name, valid)) return true;
    }
    return false;
}

pub fn cacheWithLimits(options: anytype) Limits {
    const T = @TypeOf(options);
    if (T == Limits) return options;
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("cacheWithLimits expects an anonymous struct with Discord.js managers, e.g. cacheWithLimits(.{ .GuildMemberManager = 12000, .MessageManager = 50 })");
    }
    inline for (info.@"struct".fields) |f| {
        if (!comptime isValidManager(f.name)) {
            @compileError("Invalid manager '" ++ f.name ++ "' in cacheWithLimits. Only Discord.js manager names are permitted: GuildMemberManager, MessageManager, GuildManager, ChannelManager, UserManager, RoleManager, ThreadManager, ThreadMemberManager, GuildEmojiManager, GuildStickerManager, GuildBanManager, GuildInviteManager, GuildScheduledEventManager, StageInstanceManager, PresenceManager, VoiceStateManager, ApplicationCommandManager, AutoModerationRuleManager, ReactionManager, ReactionUserManager");
        }
    }
    var limits: Limits = .{};
    if (@hasField(T, "GuildMemberManager")) limits.guild_members = getLimitValue(T, options, "GuildMemberManager");
    if (@hasField(T, "MessageManager")) limits.messages = getLimitValue(T, options, "MessageManager");
    if (@hasField(T, "GuildManager")) limits.guilds = getLimitValue(T, options, "GuildManager");
    if (@hasField(T, "ChannelManager")) limits.channels = getLimitValue(T, options, "ChannelManager");
    if (@hasField(T, "UserManager")) limits.users = getLimitValue(T, options, "UserManager");
    if (@hasField(T, "RoleManager")) limits.roles = getLimitValue(T, options, "RoleManager");
    if (@hasField(T, "ThreadManager")) limits.threads = getLimitValue(T, options, "ThreadManager");
    if (@hasField(T, "ThreadMemberManager")) limits.thread_members = getLimitValue(T, options, "ThreadMemberManager");
    if (@hasField(T, "GuildEmojiManager")) limits.emojis = getLimitValue(T, options, "GuildEmojiManager")
    else if (@hasField(T, "BaseGuildEmojiManager")) limits.emojis = getLimitValue(T, options, "BaseGuildEmojiManager");
    if (@hasField(T, "GuildStickerManager")) limits.stickers = getLimitValue(T, options, "GuildStickerManager");
    if (@hasField(T, "GuildBanManager")) limits.bans = getLimitValue(T, options, "GuildBanManager");
    if (@hasField(T, "GuildInviteManager")) limits.invites = getLimitValue(T, options, "GuildInviteManager");
    if (@hasField(T, "GuildScheduledEventManager")) limits.scheduled_events = getLimitValue(T, options, "GuildScheduledEventManager");
    if (@hasField(T, "StageInstanceManager")) limits.stage_instances = getLimitValue(T, options, "StageInstanceManager");
    if (@hasField(T, "PresenceManager")) limits.presences = getLimitValue(T, options, "PresenceManager");
    if (@hasField(T, "VoiceStateManager")) limits.voice_states = getLimitValue(T, options, "VoiceStateManager");
    if (@hasField(T, "ApplicationCommandManager")) limits.application_commands = getLimitValue(T, options, "ApplicationCommandManager");
    if (@hasField(T, "AutoModerationRuleManager")) limits.auto_moderation_rules = getLimitValue(T, options, "AutoModerationRuleManager");
    if (@hasField(T, "ReactionManager")) limits.reactions = getLimitValue(T, options, "ReactionManager");
    if (@hasField(T, "ReactionUserManager")) limits.reactions = getLimitValue(T, options, "ReactionUserManager");
    return limits;
}

pub const parseLimits = cacheWithLimits;

pub const Options = struct {
    pub const cacheWithLimits = cache_mod_options_cacheWithLimits;
};

fn cache_mod_options_cacheWithLimits(val: anytype) Limits {
    return cacheWithLimits(val);
}

pub const Counts = struct {
    guilds: usize,
    channels: usize,
    messages: usize,
    members: usize,
    users: usize,
    roles: usize,
    threads: usize,
    emojis: usize,
    presences: usize,
};

pub fn Store(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        limit: ?usize,
        entries: std.AutoHashMapUnmanaged(K, std.json.Parsed(V)) = .empty,
        order: std.ArrayListUnmanaged(K) = .empty,

        pub fn init(allocator: std.mem.Allocator, limit: ?usize) Self {
            var self = Self{ .allocator = allocator, .limit = limit };
            // Pré-dimensiona a fila de evicção: evita reallocs no caminho
            // quente sem custo de rehash do mapa.
            if (limit) |l| {
                if (l > 0 and l <= 65536) {
                    self.order.ensureTotalCapacity(allocator, l) catch {};
                }
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                var owned = entry.*;
                owned.deinit();
            }
            self.entries.deinit(self.allocator);
            self.order.deinit(self.allocator);
        }

        pub fn setLimit(self: *Self, limit: ?usize) void {
            self.limit = limit;
            if (limit) |l| {
                if (l > 0 and l <= 65536) {
                    self.order.ensureTotalCapacity(self.allocator, l) catch {};
                }
            }
            self.enforce();
        }

        pub fn count(self: *const Self) usize {
            return self.entries.count();
        }

        pub fn size(self: *const Self) usize {
            return self.entries.count();
        }

        pub fn has(self: *const Self, key: K) bool {
            return self.entries.contains(key);
        }

        pub fn get(self: *const Self, key: K) ?*const V {
            const entry = self.entries.getPtr(key) orelse return null;
            return &entry.value;
        }

        pub fn first(self: *const Self) ?*const V {
            if (self.order.items.len == 0) return null;
            return self.get(self.order.items[0]);
        }

        pub fn last(self: *const Self) ?*const V {
            if (self.order.items.len == 0) return null;
            return self.get(self.order.items[self.order.items.len - 1]);
        }

        pub fn at(self: *const Self, index: usize) ?*const V {
            if (index >= self.order.items.len) return null;
            return self.get(self.order.items[index]);
        }

        pub fn find(self: *const Self, ctx: anytype, comptime match: fn (@TypeOf(ctx), *const V) bool) ?*const V {
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                if (match(ctx, &entry.*.value)) return &entry.*.value;
            }
            return null;
        }

        pub fn filter(
            self: *const Self,
            allocator: std.mem.Allocator,
            ctx: anytype,
            comptime predicate: fn (@TypeOf(ctx), *const V) bool,
        ) !std.ArrayListUnmanaged(*const V) {
            var result: std.ArrayListUnmanaged(*const V) = .empty;
            errdefer result.deinit(allocator);
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                if (predicate(ctx, &entry.*.value)) {
                    try result.append(allocator, &entry.*.value);
                }
            }
            return result;
        }

        pub fn map(
            self: *const Self,
            allocator: std.mem.Allocator,
            comptime R: type,
            ctx: anytype,
            comptime transform: fn (@TypeOf(ctx), *const V) R,
        ) !std.ArrayListUnmanaged(R) {
            var result: std.ArrayListUnmanaged(R) = .empty;
            errdefer result.deinit(allocator);
            try result.ensureTotalCapacity(allocator, self.entries.count());
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                result.appendAssumeCapacity(transform(ctx, &entry.*.value));
            }
            return result;
        }

        pub const PartitionResult = struct {
            matches: std.ArrayListUnmanaged(*const V),
            non_matches: std.ArrayListUnmanaged(*const V),

            pub fn deinit(self: *PartitionResult, allocator: std.mem.Allocator) void {
                self.matches.deinit(allocator);
                self.non_matches.deinit(allocator);
            }
        };

        pub fn partition(
            self: *const Self,
            allocator: std.mem.Allocator,
            ctx: anytype,
            comptime predicate: fn (@TypeOf(ctx), *const V) bool,
        ) !PartitionResult {
            var matches: std.ArrayListUnmanaged(*const V) = .empty;
            errdefer matches.deinit(allocator);
            var non_matches: std.ArrayListUnmanaged(*const V) = .empty;
            errdefer non_matches.deinit(allocator);

            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                if (predicate(ctx, &entry.*.value)) {
                    try matches.append(allocator, &entry.*.value);
                } else {
                    try non_matches.append(allocator, &entry.*.value);
                }
            }
            return .{
                .matches = matches,
                .non_matches = non_matches,
            };
        }

        pub fn every(
            self: *const Self,
            ctx: anytype,
            comptime predicate: fn (@TypeOf(ctx), *const V) bool,
        ) bool {
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                if (!predicate(ctx, &entry.*.value)) return false;
            }
            return true;
        }

        pub fn some(
            self: *const Self,
            ctx: anytype,
            comptime predicate: fn (@TypeOf(ctx), *const V) bool,
        ) bool {
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                if (predicate(ctx, &entry.*.value)) return true;
            }
            return false;
        }

        pub fn putParsed(self: *Self, key: K, parsed: std.json.Parsed(V)) !void {
            // Limite 0 = cache desabilitado: dispensa sem tocar no mapa.
            if (self.limit != null and self.limit.? == 0) {
                var tmp = parsed;
                tmp.deinit();
                return;
            }
            var owned: ?std.json.Parsed(V) = parsed;
            errdefer if (owned) |*p| p.deinit();
            if (self.entries.getPtr(key)) |existing| {
                try self.refresh(key);
                existing.deinit();
                existing.* = owned.?;
                owned = null;
            } else {
                try self.entries.put(self.allocator, key, owned.?);
                owned = null;
                errdefer {
                    if (self.entries.getPtr(key)) |e| {
                        var doomed = e.*;
                        doomed.deinit();
                    }
                    _ = self.entries.remove(key);
                }
                try self.order.append(self.allocator, key);
            }
            self.enforce();
        }

        pub fn remove(self: *Self, key: K) bool {
            const entry = self.entries.getPtr(key) orelse return false;
            var owned = entry.*;
            owned.deinit();
            _ = self.entries.remove(key);
            for (self.order.items, 0..) |k, i| {
                if (k == key) {
                    _ = self.order.orderedRemove(i);
                    break;
                }
            }
            return true;
        }

        pub fn clear(self: *Self) void {
            var it = self.entries.valueIterator();
            while (it.next()) |entry| {
                var owned = entry.*;
                owned.deinit();
            }
            self.entries.clearRetainingCapacity();
            self.order.clearRetainingCapacity();
        }

        pub fn sweep(self: *Self, ctx: anytype, comptime keep: fn (@TypeOf(ctx), *const V) bool) usize {
            var doomed: std.ArrayListUnmanaged(K) = .empty;
            defer doomed.deinit(self.allocator);
            var it = self.entries.iterator();
            while (it.next()) |kv| {
                if (!keep(ctx, &kv.value_ptr.*.value)) {
                    doomed.append(self.allocator, kv.key_ptr.*) catch break;
                }
            }
            for (doomed.items) |key| _ = self.remove(key);
            return doomed.items.len;
        }

        pub fn iterator(self: *Self) std.AutoHashMapUnmanaged(K, std.json.Parsed(V)).Iterator {
            return self.entries.iterator();
        }

        fn refresh(self: *Self, key: K) !void {
            for (self.order.items, 0..) |k, i| {
                if (k == key) {
                    _ = self.order.orderedRemove(i);
                    break;
                }
            }
            try self.order.append(self.allocator, key);
        }

        fn enforce(self: *Self) void {
            const limit = self.limit orelse return;
            // Evicção sempre pela cabeça (mais antigo): remove direto sem a
            // busca linear de `remove`, que seria O(n) por item evictado.
            while (self.entries.count() > limit) {
                if (self.order.items.len == 0) return;
                const oldest = self.order.items[0];
                if (self.entries.getPtr(oldest)) |entry| {
                    var owned = entry.*;
                    owned.deinit();
                }
                _ = self.entries.remove(oldest);
                _ = self.order.orderedRemove(0);
            }
        }
    };
}

pub fn memberKey(guild_id: u64, user_id: u64) u128 {
    return (@as(u128, guild_id) << 64) | user_id;
}

pub fn memberKeyGuild(key: u128) u64 {
    return @truncate(key >> 64);
}

pub fn memberKeyUser(key: u128) u64 {
    return @truncate(key);
}

pub const Cache = struct {
    allocator: std.mem.Allocator,
    limits: Limits,
    guilds: Store(u64, schema.Guild),
    channels: Store(u64, schema.Channel),
    messages: Store(u64, schema.Message),
    members: Store(u128, schema.GuildMember),
    users: Store(u64, schema.User),
    roles: Store(u64, schema.Role),
    threads: Store(u64, schema.Channel),
    emojis: Store(u64, schema.Emoji),
    presences: Store(u64, schema.Presence),

    pub fn init(allocator: std.mem.Allocator, limits: Limits) Cache {
        return .{
            .allocator = allocator,
            .limits = limits,
            .guilds = Store(u64, schema.Guild).init(allocator, limits.guilds),
            .channels = Store(u64, schema.Channel).init(allocator, limits.channels),
            .messages = Store(u64, schema.Message).init(allocator, limits.messages),
            .members = Store(u128, schema.GuildMember).init(allocator, limits.guild_members),
            .users = Store(u64, schema.User).init(allocator, limits.users),
            .roles = Store(u64, schema.Role).init(allocator, limits.roles),
            .threads = Store(u64, schema.Channel).init(allocator, limits.threads),
            .emojis = Store(u64, schema.Emoji).init(allocator, limits.emojis),
            .presences = Store(u64, schema.Presence).init(allocator, limits.presences),
        };
    }

    pub fn deinit(self: *Cache) void {
        self.guilds.deinit();
        self.channels.deinit();
        self.messages.deinit();
        self.members.deinit();
        self.users.deinit();
        self.roles.deinit();
        self.threads.deinit();
        self.emojis.deinit();
        self.presences.deinit();
    }

    pub fn setLimits(self: *Cache, limits: Limits) void {
        self.limits = limits;
        self.guilds.setLimit(limits.guilds);
        self.channels.setLimit(limits.channels);
        self.messages.setLimit(limits.messages);
        self.members.setLimit(limits.guild_members);
        self.users.setLimit(limits.users);
        self.roles.setLimit(limits.roles);
        self.threads.setLimit(limits.threads);
        self.emojis.setLimit(limits.emojis);
        self.presences.setLimit(limits.presences);
    }

    pub fn counts(self: *const Cache) Counts {
        return .{
            .guilds = self.guilds.count(),
            .channels = self.channels.count(),
            .messages = self.messages.count(),
            .members = self.members.count(),
            .users = self.users.count(),
            .roles = self.roles.count(),
            .threads = self.threads.count(),
            .emojis = self.emojis.count(),
            .presences = self.presences.count(),
        };
    }

    pub fn clear(self: *Cache) void {
        self.guilds.clear();
        self.channels.clear();
        self.messages.clear();
        self.members.clear();
        self.users.clear();
        self.roles.clear();
        self.threads.clear();
        self.emojis.clear();
        self.presences.clear();
    }

    pub fn update(self: *Cache, t: events.Type, d: std.json.Value) !void {
        switch (t) {
            .message_create, .message_update => {
                if (storeDisabled(self.messages.limit)) return;
                const parsed = try parseCached(schema.Message, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.Message) = parsed;
                defer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.id) orelse return;
                try self.messages.putParsed(id, owned.?);
                owned = null;
            },
            .message_delete => {
                if (storeDisabled(self.messages.limit)) return;
                const id = idOf(d) orelse return;
                _ = self.messages.remove(id);
            },
            .channel_create, .channel_update => {
                if (storeDisabled(self.channels.limit)) return;
                const parsed = try parseCached(schema.Channel, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.Channel) = parsed;
                defer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.id) orelse return;
                try self.channels.putParsed(id, owned.?);
                owned = null;
            },
            .channel_delete => {
                if (storeDisabled(self.channels.limit)) return;
                const id = idOf(d) orelse return;
                _ = self.channels.remove(id);
            },
            .guild_create, .guild_update => {
                if (storeDisabled(self.guilds.limit)) return;
                const parsed = try parseCached(schema.Guild, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.Guild) = parsed;
                defer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.id) orelse return;
                try self.guilds.putParsed(id, owned.?);
                owned = null;
            },
            .guild_delete => {
                if (storeDisabled(self.guilds.limit)) return;
                const id = idOf(d) orelse return;
                _ = self.guilds.remove(id);
            },
            .guild_member_add, .guild_member_update => {
                if (storeDisabled(self.members.limit)) return;
                const ids = memberIds(d) orelse return;
                const parsed = try parseCached(schema.GuildMember, self.allocator, d) orelse return;
                try self.members.putParsed(memberKey(ids.guild, ids.user), parsed);
            },
            .guild_member_remove => {
                if (storeDisabled(self.members.limit)) return;
                const parsed = try parseCached(events.GuildMemberRemove, self.allocator, d) orelse return;
                defer parsed.deinit();
                const guild = idFromString(parsed.value.guild_id) orelse return;
                const user = idFromString(parsed.value.user.id) orelse return;
                _ = self.members.remove(memberKey(guild, user));
            },
            .guild_members_chunk => {
                if (storeDisabled(self.members.limit)) return;
                const obj = switch (d) {
                    .object => |o| o,
                    else => return,
                };
                const guild_field = obj.get("guild_id") orelse return;
                const guild_id = switch (guild_field) {
                    .string => |s| idFromString(s) orelse return,
                    else => return,
                };
                const members_field = obj.get("members") orelse return;
                const items = switch (members_field) {
                    .array => |a| a.items,
                    else => return,
                };
                for (items) |item| {
                    const parsed = try parseCached(schema.GuildMember, self.allocator, item) orelse continue;
                    var owned: ?std.json.Parsed(schema.GuildMember) = parsed;
                    defer if (owned) |*p| p.deinit();
                    const user = owned.?.value.user orelse {
                        continue;
                    };
                    const user_id = idFromString(user.id) orelse {
                        continue;
                    };
                    try self.members.putParsed(memberKey(guild_id, user_id), owned.?);
                    owned = null;
                }
            },
            .user_update => {
                if (storeDisabled(self.users.limit)) return;
                const parsed = try parseCached(schema.User, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.User) = parsed;
                defer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.id) orelse return;
                try self.users.putParsed(id, owned.?);
                owned = null;
            },
            .presence_update => {
                if (storeDisabled(self.presences.limit)) return;
                const parsed = try parseCached(schema.Presence, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.Presence) = parsed;
                defer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.user.id) orelse return;
                try self.presences.putParsed(id, owned.?);
                owned = null;
            },
            .guild_role_create, .guild_role_update => {
                if (storeDisabled(self.roles.limit)) return;
                const parsed = try parseCached(schema.Role, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.Role) = parsed;
                defer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.id) orelse return;
                try self.roles.putParsed(id, owned.?);
                owned = null;
            },

            .guild_role_delete => {
                if (storeDisabled(self.roles.limit)) return;
                const parsed = try parseCached(events.RoleDelete, self.allocator, d) orelse return;
                defer parsed.deinit();
                const id = idFromString(parsed.value.role_id) orelse return;
                _ = self.roles.remove(id);
            },
            .thread_create, .thread_update => {
                if (storeDisabled(self.threads.limit)) return;
                const parsed = try parseCached(schema.Channel, self.allocator, d) orelse return;
                var owned: ?std.json.Parsed(schema.Channel) = parsed;
                errdefer if (owned) |*p| p.deinit();
                const id = idFromString(owned.?.value.id) orelse return;
                try self.threads.putParsed(id, owned.?);
                owned = null;
            },
            .thread_delete => {
                if (storeDisabled(self.threads.limit)) return;
                const id = idOf(d) orelse return;
                _ = self.threads.remove(id);
            },
            .guild_emojis_update => {
                if (storeDisabled(self.emojis.limit)) return;
                const obj = switch (d) {
                    .object => |o| o,
                    else => return,
                };
                const list = switch (obj.get("emojis") orelse return) {
                    .array => |a| a.items,
                    else => return,
                };
                for (list) |item| {
                    const parsed = try parseCached(schema.Emoji, self.allocator, item) orelse continue;
                    var owned: ?std.json.Parsed(schema.Emoji) = parsed;
                    errdefer if (owned) |*p| p.deinit();
                    const raw_id = owned.?.value.id orelse {
                        owned.?.deinit();
                        continue;
                    };
                    const id = idFromString(raw_id) orelse {
                        owned.?.deinit();
                        continue;
                    };
                    try self.emojis.putParsed(id, owned.?);
                    owned = null;
                }
            },
            else => {},
        }
    }

    pub fn sweepMessagesOlderThan(self: *Cache, now_ms: u64, max_age_ms: u64) usize {
        const Ctx = struct { now_ms: u64, max_age_ms: u64 };
        const keep = struct {
            fn f(ctx: Ctx, msg: *const schema.Message) bool {
                const id = std.fmt.parseInt(u64, msg.id, 10) catch return true;
                const ts = snowflake.Snowflake.fromValue(id).timestampMs();
                if (ts > ctx.now_ms) return true;
                return ctx.now_ms - ts <= ctx.max_age_ms;
            }
        }.f;
        return self.messages.sweep(Ctx{ .now_ms = now_ms, .max_age_ms = max_age_ms }, keep);
    }
};

fn storeDisabled(limit: ?usize) bool {
    return limit != null and limit.? == 0;
}

fn parseCached(comptime V: type, allocator: std.mem.Allocator, d: std.json.Value) !?std.json.Parsed(V) {
    // alloc_always: o `Parsed` guardado no cache sobrevive ao `Value` de
    // origem (arena do envelope do gateway, liberada ao fim do dispatch).
    // Sem isso, os slices do cache pendurariam no buffer reutilizado.
    return std.json.parseFromValue(V, allocator, d, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return null,
    };
}

fn idFromString(text: []const u8) ?u64 {
    return std.fmt.parseInt(u64, text, 10) catch null;
}

fn idOf(d: std.json.Value) ?u64 {
    const obj = switch (d) {
        .object => |o| o,
        else => return null,
    };
    const v = obj.get("id") orelse return null;
    const s = switch (v) {
        .string => |s| s,
        .number_string => |s| s,
        else => return null,
    };
    return idFromString(s);
}

const MemberIds = struct { guild: u64, user: u64 };

fn memberIds(d: std.json.Value) ?MemberIds {
    const obj = switch (d) {
        .object => |o| o,
        else => return null,
    };
    const guild = obj.get("guild_id") orelse return null;
    const user = obj.get("user") orelse return null;
    const guild_id = switch (guild) {
        .string => |s| idFromString(s),
        .number_string => |s| idFromString(s),
        else => null,
    } orelse return null;
    const user_obj = switch (user) {
        .object => |o| o,
        else => return null,
    };
    const uid = user_obj.get("id") orelse return null;
    const user_id = switch (uid) {
        .string => |s| idFromString(s),
        .number_string => |s| idFromString(s),
        else => return null,
    } orelse return null;
    return .{ .guild = guild_id, .user = user_id };
}
