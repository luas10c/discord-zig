const std = @import("std");
const schema = @import("./schema.zig");

pub const InteractionCollectorOptions = struct {
    filter: ?*const fn (schema.Interaction) bool = null,
    message_id: ?[]const u8 = null,
    custom_id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    component_type: ?u8 = null,
    time_ms: ?u64 = null,
    max: ?u32 = null,
};

pub const InteractionCollector = struct {
    allocator: std.mem.Allocator,
    options: InteractionCollectorOptions,
    collected_count: u32 = 0,
    created_at_ms: i64,
    ended: bool = false,
    end_reason: []const u8 = "",

    on_collect: ?*const fn (*InteractionCollector, schema.Interaction) void = null,
    on_end: ?*const fn (*InteractionCollector, []const u8) void = null,

    pub fn init(allocator: std.mem.Allocator, options: InteractionCollectorOptions, now_ms: i64) InteractionCollector {
        return .{
            .allocator = allocator,
            .options = options,
            .created_at_ms = now_ms,
        };
    }

    pub fn stop(self: *InteractionCollector, reason: []const u8) void {
        if (self.ended) return;
        self.ended = true;
        self.end_reason = reason;
        if (self.on_end) |cb| cb(self, reason);
    }

    pub fn checkExpired(self: *InteractionCollector, now_ms: i64) bool {
        if (self.ended) return true;
        if (self.options.time_ms) |timeout| {
            if (now_ms - self.created_at_ms >= timeout) {
                self.stop("time");
                return true;
            }
        }
        return false;
    }

    pub fn handleInteraction(self: *InteractionCollector, interaction: schema.Interaction, now_ms: i64) bool {
        if (self.checkExpired(now_ms)) return false;

        if (self.options.filter) |f| {
            if (!f(interaction)) return false;
        }

        if (self.options.user_id) |uid| {
            const inter_uid = if (interaction.user) |u|
                u.id
            else if (interaction.member) |m|
                if (m.user) |mu| mu.id else null
            else
                null;
            if (inter_uid == null or !std.mem.eql(u8, inter_uid.?, uid)) return false;
        }

        if (self.options.message_id) |mid| {
            if (interaction.message) |msg| {
                if (!std.mem.eql(u8, msg.id, mid)) return false;
            } else {
                return false;
            }
        }

        if (self.options.custom_id) |cid| {
            if (interaction.data) |d| {
                if (d.custom_id) |c| {
                    if (!std.mem.eql(u8, c, cid)) return false;
                } else return false;
            } else return false;
        }

        if (self.options.component_type) |ct| {
            if (interaction.data) |d| {
                if (d.component_type) |t| {
                    if (t != ct) return false;
                } else return false;
            } else return false;
        }

        self.collected_count += 1;
        if (self.on_collect) |cb| cb(self, interaction);

        if (self.options.max) |m| {
            if (self.collected_count >= m) {
                self.stop("limit");
            }
        }

        return true;
    }
};
