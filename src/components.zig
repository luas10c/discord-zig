const std = @import("std");
const schema = @import("./schema.zig");

pub const max_row_children = 5;
pub const max_button_label_len = 80;
pub const max_custom_id_len = 100;
pub const max_select_options = 25;
pub const max_option_label_len = 100;
pub const max_option_value_len = 100;
pub const max_option_description_len = 100;
pub const max_select_placeholder_len = 150;
pub const max_text_label_len = 45;
pub const max_text_placeholder_len = 100;
pub const max_modal_title_len = 45;
pub const max_modal_rows = 5;

pub const BuildError = error{
    MissingCustomId,
    MissingLabel,
    MissingUrl,
    UnexpectedUrl,
    LabelTooLong,
    CustomIdTooLong,
    TooManyChildren,
    MixedRowChildren,
    ModalRowMustBeTextInput,
    TooManyOptions,
    OptionLabelTooLong,
    OptionValueTooLong,
    OptionDescriptionTooLong,
    PlaceholderTooLong,
    TitleTooLong,
    TooManyRows,
    MissingAccessory,
    MissingChild,
    InvalidSpacing,
    MissingSkuId,
    UnexpectedSkuId,
    UrlTooLong,
    RequiredZeroMinValues,
} || std.mem.Allocator.Error;

pub const OptionInput = struct {
    label: []const u8,
    value: []const u8,
    description: ?[]const u8 = null,
    emoji_name: ?[]const u8 = null,
    default: bool = false,
};

fn dupeComponent(allocator: std.mem.Allocator, c: schema.Component) !schema.Component {
    var out = c;
    if (c.custom_id) |v| out.custom_id = try allocator.dupe(u8, v);
    if (c.label) |v| out.label = try allocator.dupe(u8, v);
    if (c.url) |v| out.url = try allocator.dupe(u8, v);
    if (c.sku_id) |v| out.sku_id = try allocator.dupe(u8, v);
    if (c.placeholder) |v| out.placeholder = try allocator.dupe(u8, v);
    if (c.value) |v| out.value = try allocator.dupe(u8, v);
    if (c.content) |v| out.content = try allocator.dupe(u8, v);
    if (c.description) |v| out.description = try allocator.dupe(u8, v);
    if (c.media_url) |v| out.media_url = try allocator.dupe(u8, v);
    if (c.file_url) |v| out.file_url = try allocator.dupe(u8, v);
    if (c.file_name) |v| out.file_name = try allocator.dupe(u8, v);
    if (c.emoji) |e| {
        var emoji = e;
        if (e.id) |v| emoji.id = try allocator.dupe(u8, v);
        if (e.name) |v| emoji.name = try allocator.dupe(u8, v);
        out.emoji = emoji;
    }
    if (c.options.len > 0) {
        const opts = try allocator.alloc(schema.SelectOption, c.options.len);
        for (c.options, 0..) |o, i| {
            var opt = o;
            opt.label = try allocator.dupe(u8, o.label);
            opt.value = try allocator.dupe(u8, o.value);
            if (o.description) |v| opt.description = try allocator.dupe(u8, v);
            if (o.emoji) |e| {
                var emoji = e;
                if (e.id) |v| emoji.id = try allocator.dupe(u8, v);
                if (e.name) |v| emoji.name = try allocator.dupe(u8, v);
                opt.emoji = emoji;
            }
            opts[i] = opt;
        }
        out.options = opts;
    }
    if (c.channel_types.len > 0) out.channel_types = try allocator.dupe(i64, c.channel_types);
    if (c.default_values.len > 0) {
        const dvs = try allocator.alloc(schema.SelectDefaultValue, c.default_values.len);
        for (c.default_values, 0..) |dv, i| {
            dvs[i] = .{
                .id = try allocator.dupe(u8, dv.id),
                .@"type" = try allocator.dupe(u8, dv.@"type"),
            };
        }
        out.default_values = dvs;
    }
    if (c.items.len > 0) {
        const items = try allocator.alloc(schema.MediaGalleryItem, c.items.len);
        for (c.items, 0..) |item, i| {
            var copy = item;
            copy.media.url = try allocator.dupe(u8, item.media.url);
            if (item.description) |v| copy.description = try allocator.dupe(u8, v);
            items[i] = copy;
        }
        out.items = items;
    }
    if (c.accessory) |a| {
        const owned = try allocator.create(schema.Component);
        owned.* = try dupeComponent(allocator, a.*);
        out.accessory = owned;
    }
    if (c.component) |inner| {
        const owned = try allocator.create(schema.Component);
        owned.* = try dupeComponent(allocator, inner.*);
        out.component = owned;
    }
    if (c.components.len > 0) {
        const kids = try allocator.alloc(schema.Component, c.components.len);
        for (c.components, 0..) |k, i| kids[i] = try dupeComponent(allocator, k);
        out.components = kids;
    }
    return out;
}

pub const ActionRowBuilder = struct {
    arena: std.heap.ArenaAllocator,
    children: std.ArrayListUnmanaged(schema.Component) = .empty,

    pub fn init(allocator: std.mem.Allocator) ActionRowBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *ActionRowBuilder) void {
        self.children.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn add(self: *ActionRowBuilder, child: schema.Component) !void {
        try self.children.append(self.arena.allocator(), try dupeComponent(self.arena.allocator(), child));
    }

    pub fn build(self: *ActionRowBuilder) BuildError!schema.Component {
        const kids = self.children.items;
        if (kids.len == 0 or kids.len > max_row_children) return error.TooManyChildren;
        var selects: usize = 0;
        var inputs: usize = 0;
        for (kids) |k| {
            const t: schema.ComponentType = @enumFromInt(k.type);
            switch (t) {
                .button, .string_select, .user_select, .role_select, .mentionable_select, .channel_select, .text_input => {},
                else => return error.MixedRowChildren,
            }
            switch (t) {
                .button => {},
                .text_input => inputs += 1,
                else => selects += 1,
            }
        }
        if (selects > 0 and (selects > 1 or kids.len > 1)) return error.MixedRowChildren;
        if (inputs > 0 and (inputs > 1 or kids.len > 1)) return error.MixedRowChildren;
        if (selects > 0 and inputs > 0) return error.MixedRowChildren;
        return .{ .type = @intFromEnum(schema.ComponentType.action_row), .components = kids };
    }
};

pub const ButtonBuilder = struct {
    arena: std.heap.ArenaAllocator,
    style: schema.ButtonStyle = .primary,
    label: ?[]const u8 = null,
    custom_id: ?[]const u8 = null,
    url: ?[]const u8 = null,
    sku_id: ?[]const u8 = null,
    disabled: bool = false,
    emoji_name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) ButtonBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *ButtonBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    fn dupe(self: *ButtonBuilder, text: []const u8) ![]const u8 {
        return self.arena.allocator().dupe(u8, text);
    }

    pub fn setStyle(self: *ButtonBuilder, style: schema.ButtonStyle) void {
        self.style = style;
    }

    pub fn setLabel(self: *ButtonBuilder, label: []const u8) !void {
        self.label = try self.dupe(label);
    }

    pub fn setCustomId(self: *ButtonBuilder, custom_id: []const u8) !void {
        self.custom_id = try self.dupe(custom_id);
    }

    pub fn setUrl(self: *ButtonBuilder, url: []const u8) !void {
        self.url = try self.dupe(url);
    }

    pub fn setSkuId(self: *ButtonBuilder, sku_id: []const u8) !void {
        self.sku_id = try self.dupe(sku_id);
    }

    pub fn setDisabled(self: *ButtonBuilder, disabled: bool) void {
        self.disabled = disabled;
    }

    pub fn setEmoji(self: *ButtonBuilder, name: []const u8) !void {
        self.emoji_name = try self.dupe(name);
    }

    pub fn build(self: *ButtonBuilder) BuildError!schema.Component {
        if (self.label) |l| {
            if (l.len == 0 or l.len > max_button_label_len) return error.LabelTooLong;
        }
        if (self.url) |u| {
            if (u.len > max_url_len) return error.UrlTooLong;
        }
        if (self.style == .premium) {
            const sku = self.sku_id orelse return error.MissingSkuId;
            if (self.custom_id != null or self.url != null or self.label != null or self.emoji_name != null) return error.UnexpectedSkuId;
            return .{
                .type = @intFromEnum(schema.ComponentType.button),
                .style = @intFromEnum(self.style),
                .sku_id = sku,
                .disabled = self.disabled,
            };
        }
        if (self.sku_id != null) return error.UnexpectedSkuId;
        if (self.style == .link) {
            const url = self.url orelse return error.MissingUrl;
            _ = url;
            if (self.custom_id != null) return error.UnexpectedUrl;
            return .{
                .type = @intFromEnum(schema.ComponentType.button),
                .style = @intFromEnum(self.style),
                .label = self.label,
                .url = self.url,
                .disabled = self.disabled,
                .emoji = if (self.emoji_name) |n| .{ .name = n } else null,
            };
        }
        const custom_id = self.custom_id orelse return error.MissingCustomId;
        if (custom_id.len == 0 or custom_id.len > max_custom_id_len) return error.CustomIdTooLong;
        if (self.url != null) return error.UnexpectedUrl;
        return .{
            .type = @intFromEnum(schema.ComponentType.button),
            .style = @intFromEnum(self.style),
            .label = self.label,
            .custom_id = custom_id,
            .disabled = self.disabled,
            .emoji = if (self.emoji_name) |n| .{ .name = n } else null,
        };
    }
};

pub const StringSelectBuilder = struct {
    arena: std.heap.ArenaAllocator,
    custom_id: ?[]const u8 = null,
    placeholder: ?[]const u8 = null,
    min_values: ?u32 = null,
    max_values: ?u32 = null,
    required: ?bool = null,
    disabled: bool = false,
    options: std.ArrayListUnmanaged(schema.SelectOption) = .empty,

    pub fn init(allocator: std.mem.Allocator) StringSelectBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *StringSelectBuilder) void {
        self.options.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    fn dupe(self: *StringSelectBuilder, text: []const u8) ![]const u8 {
        return self.arena.allocator().dupe(u8, text);
    }

    pub fn setCustomId(self: *StringSelectBuilder, custom_id: []const u8) !void {
        self.custom_id = try self.dupe(custom_id);
    }

    pub fn setPlaceholder(self: *StringSelectBuilder, placeholder: []const u8) !void {
        self.placeholder = try self.dupe(placeholder);
    }

    pub fn setMinValues(self: *StringSelectBuilder, n: u32) void {
        self.min_values = n;
    }

    pub fn setMaxValues(self: *StringSelectBuilder, n: u32) void {
        self.max_values = n;
    }

    pub fn setRequired(self: *StringSelectBuilder, required: bool) void {
        self.required = required;
    }

    pub fn setDisabled(self: *StringSelectBuilder, disabled: bool) void {
        self.disabled = disabled;
    }

    pub fn addOption(self: *StringSelectBuilder, opt: OptionInput) !void {
        try self.options.append(self.arena.allocator(), .{
            .label = try self.dupe(opt.label),
            .value = try self.dupe(opt.value),
            .description = if (opt.description) |d| try self.dupe(d) else null,
            .emoji = if (opt.emoji_name) |n| .{ .name = try self.dupe(n) } else null,
            .default = opt.default,
        });
    }

    pub fn build(self: *StringSelectBuilder) BuildError!schema.Component {
        const custom_id = self.custom_id orelse return error.MissingCustomId;
        if (custom_id.len == 0 or custom_id.len > max_custom_id_len) return error.CustomIdTooLong;
        if (self.placeholder) |p| {
            if (p.len > max_select_placeholder_len) return error.PlaceholderTooLong;
        }
        if (self.options.items.len == 0 or self.options.items.len > max_select_options) return error.TooManyOptions;
        for (self.options.items) |o| {
            if (o.label.len == 0 or o.label.len > max_option_label_len) return error.OptionLabelTooLong;
            if (o.value.len == 0 or o.value.len > max_option_value_len) return error.OptionValueTooLong;
            if (o.description) |d| {
                if (d.len > max_option_description_len) return error.OptionDescriptionTooLong;
            }
        }
        if (self.required != null and self.required.? and self.min_values != null and self.min_values.? == 0) {
            return error.RequiredZeroMinValues;
        }
        var req = self.required;
        if (req == null and self.min_values != null and self.min_values.? == 0) {
            req = false;
        }
        return .{
            .type = @intFromEnum(schema.ComponentType.string_select),
            .custom_id = custom_id,
            .placeholder = self.placeholder,
            .min_values = self.min_values,
            .max_values = self.max_values,
            .required = req,
            .disabled = self.disabled,
            .options = self.options.items,
        };
    }
};

pub const EntitySelectBuilder = struct {
    arena: std.heap.ArenaAllocator,
    kind: schema.ComponentType = .user_select,
    custom_id: ?[]const u8 = null,
    placeholder: ?[]const u8 = null,
    min_values: ?u32 = null,
    max_values: ?u32 = null,
    required: ?bool = null,
    disabled: bool = false,
    channel_types: std.ArrayListUnmanaged(i64) = .empty,
    default_values: std.ArrayListUnmanaged(schema.SelectDefaultValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, kind: schema.ComponentType) EntitySelectBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator), .kind = kind };
    }

    pub fn deinit(self: *EntitySelectBuilder) void {
        self.channel_types.deinit(self.arena.allocator());
        self.default_values.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setCustomId(self: *EntitySelectBuilder, custom_id: []const u8) !void {
        self.custom_id = try self.arena.allocator().dupe(u8, custom_id);
    }

    pub fn setPlaceholder(self: *EntitySelectBuilder, placeholder: []const u8) !void {
        self.placeholder = try self.arena.allocator().dupe(u8, placeholder);
    }

    pub fn setMinValues(self: *EntitySelectBuilder, n: u32) void {
        self.min_values = n;
    }

    pub fn setMaxValues(self: *EntitySelectBuilder, n: u32) void {
        self.max_values = n;
    }

    pub fn setRequired(self: *EntitySelectBuilder, required: bool) void {
        self.required = required;
    }

    pub fn setDisabled(self: *EntitySelectBuilder, disabled: bool) void {
        self.disabled = disabled;
    }

    pub fn addChannelType(self: *EntitySelectBuilder, channel_type: schema.ChannelType) !void {
        try self.channel_types.append(self.arena.allocator(), @intFromEnum(channel_type));
    }

    pub fn setChannelTypes(self: *EntitySelectBuilder, types: []const schema.ChannelType) !void {
        for (types) |t| {
            try self.addChannelType(t);
        }
    }

    pub fn addDefaultValue(self: *EntitySelectBuilder, id: []const u8, kind: []const u8) !void {
        const aa = self.arena.allocator();
        try self.default_values.append(aa, .{
            .id = try aa.dupe(u8, id),
            .@"type" = try aa.dupe(u8, kind),
        });
    }

    pub fn build(self: *EntitySelectBuilder) BuildError!schema.Component {
        switch (self.kind) {
            .user_select, .role_select, .mentionable_select, .channel_select => {},
            else => return error.MixedRowChildren,
        }
        const custom_id = self.custom_id orelse return error.MissingCustomId;
        if (custom_id.len == 0 or custom_id.len > max_custom_id_len) return error.CustomIdTooLong;
        if (self.placeholder) |p| {
            if (p.len > max_select_placeholder_len) return error.PlaceholderTooLong;
        }
        if (self.required != null and self.required.? and self.min_values != null and self.min_values.? == 0) {
            return error.RequiredZeroMinValues;
        }
        var req = self.required;
        if (req == null and self.min_values != null and self.min_values.? == 0) {
            req = false;
        }
        return .{
            .type = @intFromEnum(self.kind),
            .custom_id = custom_id,
            .placeholder = self.placeholder,
            .min_values = self.min_values,
            .max_values = self.max_values,
            .required = req,
            .disabled = self.disabled,
            .channel_types = self.channel_types.items,
            .default_values = self.default_values.items,
        };
    }
};

pub const TextInputBuilder = struct {
    arena: std.heap.ArenaAllocator,
    custom_id: ?[]const u8 = null,
    style: schema.TextInputStyle = .short,
    label: ?[]const u8 = null,
    min_length: ?u32 = null,
    max_length: ?u32 = null,
    required: bool = true,
    value: ?[]const u8 = null,
    placeholder: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) TextInputBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *TextInputBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    fn dupe(self: *TextInputBuilder, text: []const u8) ![]const u8 {
        return self.arena.allocator().dupe(u8, text);
    }

    pub fn setCustomId(self: *TextInputBuilder, custom_id: []const u8) !void {
        self.custom_id = try self.dupe(custom_id);
    }

    pub fn setStyle(self: *TextInputBuilder, style: schema.TextInputStyle) void {
        self.style = style;
    }

    pub fn setLabel(self: *TextInputBuilder, label: []const u8) !void {
        self.label = try self.dupe(label);
    }

    pub fn setMinLength(self: *TextInputBuilder, n: u32) void {
        self.min_length = n;
    }

    pub fn setMaxLength(self: *TextInputBuilder, n: u32) void {
        self.max_length = n;
    }

    pub fn setRequired(self: *TextInputBuilder, required: bool) void {
        self.required = required;
    }

    pub fn setValue(self: *TextInputBuilder, value: []const u8) !void {
        self.value = try self.dupe(value);
    }

    pub fn setPlaceholder(self: *TextInputBuilder, placeholder: []const u8) !void {
        self.placeholder = try self.dupe(placeholder);
    }

    pub fn build(self: *TextInputBuilder) BuildError!schema.Component {
        const custom_id = self.custom_id orelse return error.MissingCustomId;
        if (custom_id.len == 0 or custom_id.len > max_custom_id_len) return error.CustomIdTooLong;
        const label = self.label orelse return error.MissingLabel;
        if (label.len == 0 or label.len > max_text_label_len) return error.LabelTooLong;
        if (self.placeholder) |p| {
            if (p.len > max_text_placeholder_len) return error.PlaceholderTooLong;
        }
        return .{
            .type = @intFromEnum(schema.ComponentType.text_input),
            .custom_id = custom_id,
            .style = @intFromEnum(self.style),
            .label = label,
            .min_length = self.min_length,
            .max_length = self.max_length,
            .required = self.required,
            .value = self.value,
            .placeholder = self.placeholder,
        };
    }
};

pub const ModalBuilder = struct {
    arena: std.heap.ArenaAllocator,
    custom_id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    rows: std.ArrayListUnmanaged(schema.Component) = .empty,

    pub fn init(allocator: std.mem.Allocator) ModalBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *ModalBuilder) void {
        self.rows.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setCustomId(self: *ModalBuilder, custom_id: []const u8) !void {
        self.custom_id = try self.arena.allocator().dupe(u8, custom_id);
    }

    pub fn setTitle(self: *ModalBuilder, title: []const u8) !void {
        self.title = try self.arena.allocator().dupe(u8, title);
    }

    pub fn addRow(self: *ModalBuilder, row: schema.Component) !void {
        try self.rows.append(self.arena.allocator(), try dupeComponent(self.arena.allocator(), row));
    }

    pub fn build(self: *ModalBuilder) BuildError!schema.Modal {
        const custom_id = self.custom_id orelse return error.MissingCustomId;
        if (custom_id.len == 0 or custom_id.len > max_custom_id_len) return error.CustomIdTooLong;
        const title = self.title orelse return error.MissingLabel;
        if (title.len == 0 or title.len > max_modal_title_len) return error.TitleTooLong;
        if (self.rows.items.len == 0 or self.rows.items.len > max_modal_rows) return error.TooManyRows;
        for (self.rows.items) |row| {
            const t: schema.ComponentType = @enumFromInt(row.type);
            if (t == .label) continue;
            if (t != .action_row) return error.ModalRowMustBeTextInput;
            if (row.components.len != 1) return error.ModalRowMustBeTextInput;
            const inner: schema.ComponentType = @enumFromInt(row.components[0].type);
            if (inner != .text_input) return error.ModalRowMustBeTextInput;
        }
        return .{ .title = title, .custom_id = custom_id, .components = self.rows.items };
    }
};

pub const max_text_display_len = 4000;
pub const max_gallery_items = 10;
pub const max_section_texts = 3;
pub const max_url_len = 512;

pub const TextDisplayBuilder = struct {
    arena: std.heap.ArenaAllocator,
    content: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) TextDisplayBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *TextDisplayBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setContent(self: *TextDisplayBuilder, content: []const u8) !void {
        self.content = try self.arena.allocator().dupe(u8, content);
    }

    pub fn build(self: *TextDisplayBuilder) BuildError!schema.Component {
        const content = self.content orelse return error.MissingLabel;
        if (content.len == 0 or content.len > max_text_display_len) return error.LabelTooLong;
        return .{ .type = @intFromEnum(schema.ComponentType.text_display), .content = content };
    }
};

pub const ThumbnailBuilder = struct {
    arena: std.heap.ArenaAllocator,
    media_url: ?[]const u8 = null,
    description: ?[]const u8 = null,
    spoiler: ?bool = null,

    pub fn init(allocator: std.mem.Allocator) ThumbnailBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *ThumbnailBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setMediaUrl(self: *ThumbnailBuilder, url: []const u8) !void {
        self.media_url = try self.arena.allocator().dupe(u8, url);
    }

    pub fn setDescription(self: *ThumbnailBuilder, description: []const u8) !void {
        self.description = try self.arena.allocator().dupe(u8, description);
    }

    pub fn setSpoiler(self: *ThumbnailBuilder, spoiler: bool) void {
        self.spoiler = spoiler;
    }

    pub fn build(self: *ThumbnailBuilder) BuildError!schema.Component {
        return .{
            .type = @intFromEnum(schema.ComponentType.thumbnail),
            .media_url = self.media_url orelse return error.MissingUrl,
            .description = self.description,
            .spoiler = self.spoiler,
        };
    }
};

pub const GalleryItemInput = struct {
    media_url: []const u8,
    description: ?[]const u8 = null,
    spoiler: ?bool = null,
};

pub const MediaGalleryBuilder = struct {
    arena: std.heap.ArenaAllocator,
    items: std.ArrayListUnmanaged(schema.MediaGalleryItem) = .empty,

    pub fn init(allocator: std.mem.Allocator) MediaGalleryBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *MediaGalleryBuilder) void {
        self.items.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn addItem(self: *MediaGalleryBuilder, item: GalleryItemInput) !void {
        const aa = self.arena.allocator();
        try self.items.append(aa, .{
            .media = .{ .url = try aa.dupe(u8, item.media_url) },
            .description = if (item.description) |d| try aa.dupe(u8, d) else null,
            .spoiler = item.spoiler,
        });
    }

    pub fn build(self: *MediaGalleryBuilder) BuildError!schema.Component {
        if (self.items.items.len == 0 or self.items.items.len > max_gallery_items) return error.TooManyChildren;
        return .{ .type = @intFromEnum(schema.ComponentType.media_gallery), .items = self.items.items };
    }
};

pub const FileBuilder = struct {
    arena: std.heap.ArenaAllocator,
    file_url: ?[]const u8 = null,
    name: ?[]const u8 = null,
    spoiler: ?bool = null,

    pub fn init(allocator: std.mem.Allocator) FileBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *FileBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setFileUrl(self: *FileBuilder, url: []const u8) !void {
        self.file_url = try self.arena.allocator().dupe(u8, url);
    }

    pub fn setName(self: *FileBuilder, name: []const u8) !void {
        self.name = try self.arena.allocator().dupe(u8, name);
    }

    pub fn setSpoiler(self: *FileBuilder, spoiler: bool) void {
        self.spoiler = spoiler;
    }

    pub fn build(self: *FileBuilder) BuildError!schema.Component {
        return .{
            .type = @intFromEnum(schema.ComponentType.file),
            .file_url = self.file_url orelse return error.MissingUrl,
            .file_name = self.name,
            .spoiler = self.spoiler,
        };
    }
};

pub const SeparatorBuilder = struct {
    divider: ?bool = null,
    spacing: ?u8 = null,

    pub fn init() SeparatorBuilder {
        return .{};
    }

    pub fn setDivider(self: *SeparatorBuilder, divider: bool) void {
        self.divider = divider;
    }

    pub fn setSpacing(self: *SeparatorBuilder, spacing: u8) void {
        self.spacing = spacing;
    }

    pub fn build(self: *SeparatorBuilder) BuildError!schema.Component {
        if (self.spacing) |s| {
            if (s != 1 and s != 2) return error.InvalidSpacing;
        }
        return .{ .type = @intFromEnum(schema.ComponentType.separator), .divider = self.divider, .spacing = self.spacing };
    }
};

pub const SectionBuilder = struct {
    arena: std.heap.ArenaAllocator,
    texts: std.ArrayListUnmanaged(schema.Component) = .empty,
    accessory: ?schema.Component = null,

    pub fn init(allocator: std.mem.Allocator) SectionBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *SectionBuilder) void {
        self.texts.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn addText(self: *SectionBuilder, text: schema.Component) !void {
        try self.texts.append(self.arena.allocator(), try dupeComponent(self.arena.allocator(), text));
    }

    pub fn setAccessory(self: *SectionBuilder, accessory: schema.Component) !void {
        const owned = try self.arena.allocator().create(schema.Component);
        owned.* = try dupeComponent(self.arena.allocator(), accessory);
        self.accessory = owned.*;
    }

    pub fn build(self: *SectionBuilder) BuildError!schema.Component {
        if (self.texts.items.len == 0 or self.texts.items.len > max_section_texts) return error.TooManyChildren;
        for (self.texts.items) |t| {
            const kind: schema.ComponentType = @enumFromInt(t.type);
            if (kind != .text_display) return error.MixedRowChildren;
        }
        const accessory = self.accessory orelse return error.MissingAccessory;
        const kind: schema.ComponentType = @enumFromInt(accessory.type);
        switch (kind) {
            .button, .thumbnail => {},
            else => return error.MixedRowChildren,
        }
        const owned = try self.arena.allocator().create(schema.Component);
        owned.* = accessory;
        return .{
            .type = @intFromEnum(schema.ComponentType.section),
            .components = self.texts.items,
            .accessory = owned,
        };
    }
};

pub const ContainerBuilder = struct {
    arena: std.heap.ArenaAllocator,
    accent_color: ?u32 = null,
    spoiler: ?bool = null,
    children: std.ArrayListUnmanaged(schema.Component) = .empty,

    pub fn init(allocator: std.mem.Allocator) ContainerBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *ContainerBuilder) void {
        self.children.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setAccentColor(self: *ContainerBuilder, color: u32) void {
        self.accent_color = color;
    }

    pub fn setSpoiler(self: *ContainerBuilder, spoiler: bool) void {
        self.spoiler = spoiler;
    }

    pub fn add(self: *ContainerBuilder, child: schema.Component) !void {
        try self.children.append(self.arena.allocator(), try dupeComponent(self.arena.allocator(), child));
    }

    pub fn build(self: *ContainerBuilder) BuildError!schema.Component {
        if (self.children.items.len == 0) return error.TooManyChildren;
        for (self.children.items) |c| {
            const kind: schema.ComponentType = @enumFromInt(c.type);
            switch (kind) {
                .action_row, .text_display, .section, .media_gallery, .separator, .file => {},
                else => return error.MixedRowChildren,
            }
        }
        return .{
            .type = @intFromEnum(schema.ComponentType.container),
            .accent_color = self.accent_color,
            .spoiler = self.spoiler,
            .components = self.children.items,
        };
    }
};

pub const LabelBuilder = struct {
    arena: std.heap.ArenaAllocator,
    label: ?[]const u8 = null,
    description: ?[]const u8 = null,
    child: ?schema.Component = null,

    pub fn init(allocator: std.mem.Allocator) LabelBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *LabelBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setLabel(self: *LabelBuilder, label: []const u8) !void {
        self.label = try self.arena.allocator().dupe(u8, label);
    }

    pub fn setDescription(self: *LabelBuilder, description: []const u8) !void {
        self.description = try self.arena.allocator().dupe(u8, description);
    }

    pub fn setChild(self: *LabelBuilder, child: schema.Component) !void {
        const owned = try self.arena.allocator().create(schema.Component);
        owned.* = try dupeComponent(self.arena.allocator(), child);
        self.child = owned.*;
    }

    pub fn build(self: *LabelBuilder) BuildError!schema.Component {
        const label = self.label orelse return error.MissingLabel;
        if (label.len == 0) return error.MissingLabel;
        const child = self.child orelse return error.MissingChild;
        const kind: schema.ComponentType = @enumFromInt(child.type);
        switch (kind) {
            .text_input, .string_select, .user_select, .role_select, .mentionable_select, .channel_select, .text_display => {},
            else => return error.MixedRowChildren,
        }
        const owned = try self.arena.allocator().create(schema.Component);
        owned.* = child;
        return .{
            .type = @intFromEnum(schema.ComponentType.label),
            .label = label,
            .description = self.description,
            .component = owned,
        };
    }
};

pub const StringSelectMenuBuilder = StringSelectBuilder;

pub const UserSelectMenuBuilder = struct {
    pub fn init(allocator: std.mem.Allocator) EntitySelectBuilder {
        return EntitySelectBuilder.init(allocator, .user_select);
    }
};

pub const RoleSelectMenuBuilder = struct {
    pub fn init(allocator: std.mem.Allocator) EntitySelectBuilder {
        return EntitySelectBuilder.init(allocator, .role_select);
    }
};

pub const MentionableSelectMenuBuilder = struct {
    pub fn init(allocator: std.mem.Allocator) EntitySelectBuilder {
        return EntitySelectBuilder.init(allocator, .mentionable_select);
    }
};

pub const ChannelSelectMenuBuilder = struct {
    pub fn init(allocator: std.mem.Allocator) EntitySelectBuilder {
        return EntitySelectBuilder.init(allocator, .channel_select);
    }
};

pub const ButtonStyle = struct {
    pub const Primary = schema.ButtonStyle.primary;
    pub const Secondary = schema.ButtonStyle.secondary;
    pub const Success = schema.ButtonStyle.success;
    pub const Danger = schema.ButtonStyle.danger;
    pub const Link = schema.ButtonStyle.link;
    pub const Premium = schema.ButtonStyle.premium;
};

pub const TextInputStyle = struct {
    pub const Short = schema.TextInputStyle.short;
    pub const Paragraph = schema.TextInputStyle.paragraph;
};

pub const ComponentType = struct {
    pub const ActionRow = schema.ComponentType.action_row;
    pub const Button = schema.ComponentType.button;
    pub const StringSelect = schema.ComponentType.string_select;
    pub const TextInput = schema.ComponentType.text_input;
    pub const UserSelect = schema.ComponentType.user_select;
    pub const RoleSelect = schema.ComponentType.role_select;
    pub const MentionableSelect = schema.ComponentType.mentionable_select;
    pub const ChannelSelect = schema.ComponentType.channel_select;
    pub const Section = schema.ComponentType.section;
    pub const TextDisplay = schema.ComponentType.text_display;
    pub const Thumbnail = schema.ComponentType.thumbnail;
    pub const MediaGallery = schema.ComponentType.media_gallery;
    pub const File = schema.ComponentType.file;
    pub const Separator = schema.ComponentType.separator;
    pub const Container = schema.ComponentType.container;
    pub const Label = schema.ComponentType.label;
};
