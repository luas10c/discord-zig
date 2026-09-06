const std = @import("std");
const schema = @import("./schema.zig");

pub const max_title_len = 256;
pub const max_description_len = 4096;
pub const max_fields = 25;
pub const max_field_name_len = 256;
pub const max_field_value_len = 1024;
pub const max_footer_len = 2048;
pub const max_author_name_len = 256;
pub const max_total_len = 6000;

pub const BuildError = error{
    TitleTooLong,
    DescriptionTooLong,
    TooManyFields,
    FieldNameTooLong,
    FieldValueTooLong,
    FooterTooLong,
    AuthorNameTooLong,
    EmbedTooLarge,
} || std.mem.Allocator.Error;

pub const FieldInput = struct {
    name: []const u8,
    value: []const u8,
    @"inline": bool = false,
};

pub const Builder = struct {
    arena: std.heap.ArenaAllocator,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    color: ?u32 = null,
    author_name: ?[]const u8 = null,
    author_url: ?[]const u8 = null,
    author_icon_url: ?[]const u8 = null,
    footer_text: ?[]const u8 = null,
    footer_icon_url: ?[]const u8 = null,
    image_url: ?[]const u8 = null,
    thumbnail_url: ?[]const u8 = null,
    timestamp: ?[]const u8 = null,
    fields: std.ArrayListUnmanaged(schema.EmbedField) = .empty,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *Builder) void {
        self.fields.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    fn dupe(self: *Builder, text: []const u8) ![]const u8 {
        return self.arena.allocator().dupe(u8, text);
    }

    pub fn setTitle(self: *Builder, title: []const u8) !void {
        self.title = try self.dupe(title);
    }

    pub fn setDescription(self: *Builder, description: []const u8) !void {
        self.description = try self.dupe(description);
    }

    pub fn setUrl(self: *Builder, url: []const u8) !void {
        self.url = try self.dupe(url);
    }

    pub fn setColor(self: *Builder, color: u32) void {
        self.color = color;
    }

    pub fn setAuthor(self: *Builder, name: []const u8, url: ?[]const u8, icon_url: ?[]const u8) !void {
        self.author_name = try self.dupe(name);
        if (url) |u| self.author_url = try self.dupe(u);
        if (icon_url) |u| self.author_icon_url = try self.dupe(u);
    }

    pub fn setFooter(self: *Builder, text: []const u8, icon_url: ?[]const u8) !void {
        self.footer_text = try self.dupe(text);
        if (icon_url) |u| self.footer_icon_url = try self.dupe(u);
    }

    pub fn setImage(self: *Builder, url: []const u8) !void {
        self.image_url = try self.dupe(url);
    }

    pub fn setThumbnail(self: *Builder, url: []const u8) !void {
        self.thumbnail_url = try self.dupe(url);
    }

    pub fn setTimestamp(self: *Builder, timestamp: []const u8) !void {
        self.timestamp = try self.dupe(timestamp);
    }

    pub fn addField(self: *Builder, name: []const u8, value: []const u8, @"inline": bool) !void {
        try self.fields.append(self.arena.allocator(), .{
            .name = try self.dupe(name),
            .value = try self.dupe(value),
            .@"inline" = @"inline",
        });
    }

    pub fn setFields(self: *Builder, inputs: []const FieldInput) !void {
        self.fields.clearRetainingCapacity();
        for (inputs) |in| try self.addField(in.name, in.value, in.@"inline");
    }

    pub fn build(self: *Builder) BuildError!schema.Embed {
        if (self.fields.items.len > max_fields) return error.TooManyFields;
        var total: usize = 0;
        if (self.title) |t| {
            if (t.len > max_title_len) return error.TitleTooLong;
            total += t.len;
        }
        if (self.description) |d| {
            if (d.len > max_description_len) return error.DescriptionTooLong;
            total += d.len;
        }
        if (self.author_name) |n| {
            if (n.len > max_author_name_len) return error.AuthorNameTooLong;
            total += n.len;
        }
        if (self.footer_text) |t| {
            if (t.len > max_footer_len) return error.FooterTooLong;
            total += t.len;
        }
        for (self.fields.items) |f| {
            if (f.name.len > max_field_name_len) return error.FieldNameTooLong;
            if (f.value.len > max_field_value_len) return error.FieldValueTooLong;
            total += f.name.len + f.value.len;
        }
        if (total > max_total_len) return error.EmbedTooLarge;

        var embed = schema.Embed{
            .title = self.title,
            .description = self.description,
            .url = self.url,
            .color = self.color,
            .fields = self.fields.items,
            .timestamp = self.timestamp,
        };
        if (self.author_name) |n| {
            embed.author = .{ .name = n, .url = self.author_url, .icon_url = self.author_icon_url };
        }
        if (self.footer_text) |t| {
            embed.footer = .{ .text = t, .icon_url = self.footer_icon_url };
        }
        if (self.image_url) |u| embed.image = .{ .url = u };
        if (self.thumbnail_url) |u| embed.thumbnail = .{ .url = u };
        return embed;
    }
};

pub fn embedLength(embed: schema.Embed) usize {
    var total: usize = 0;
    if (embed.title) |t| total += t.len;
    if (embed.description) |d| total += d.len;
    if (embed.author) |a| total += a.name.len;
    if (embed.footer) |f| total += f.text.len;
    for (embed.fields) |field| total += field.name.len + field.value.len;
    return total;
}
