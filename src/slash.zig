const std = @import("std");
const schema = @import("./schema.zig");
const message = @import("./message.zig");
const client_mod = @import("./client.zig");
const fetch_mod = @import("./fetch.zig");
const poll_mod = @import("./poll.zig");
const attachment_mod = @import("./attachment.zig");

pub const max_name_len = 32;
pub const max_description_len = 100;
pub const max_options = 25;
pub const max_choices = 25;
pub const max_choice_name_len = 100;

pub const CommandType = enum(u8) {
    chat_input = 1,
    user = 2,
    message = 3,
};

pub const OptionType = enum(u8) {
    sub_command = 1,
    sub_command_group = 2,
    string = 3,
    integer = 4,
    boolean = 5,
    user = 6,
    channel = 7,
    role = 8,
    mentionable = 9,
    number = 10,
    attachment = 11,
};

pub const BuildError = error{
    NameInvalid,
    DescriptionInvalid,
    TooManyOptions,
    RequiredAfterOptional,
    SubcommandRequired,
    BadNesting,
    TooManyChoices,
    ChoiceOnWrongType,
    ChoiceNameInvalid,
    ChannelTypesOnWrongType,
    AutocompleteOnWrongType,
} || std.mem.Allocator.Error;

pub const ChoiceInput = struct {
    name: []const u8,
    value: std.json.Value,
};

pub const OptionInput = struct {
    name: []const u8,
    description: []const u8,
    kind: OptionType,
    required: bool = false,
    choices: []const ChoiceInput = &.{},
    options: []const OptionInput = &.{},
    channel_types: []const schema.ChannelType = &.{},
    autocomplete: bool = false,
    min_value: ?f64 = null,
    max_value: ?f64 = null,
    min_length: ?u32 = null,
    max_length: ?u32 = null,
};

fn isCommandChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_';
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > max_name_len) return false;
    for (name) |c| {
        if (!isCommandChar(c)) return false;
    }
    return true;
}

fn cloneValue(allocator: std.mem.Allocator, v: std.json.Value) !std.json.Value {
    return switch (v) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        else => error.InvalidChoiceValue,
    };
}

pub const Command = struct {
    arena: std.heap.ArenaAllocator,
    name: []const u8 = "",
    description: []const u8 = "",
    kind: CommandType = .chat_input,
    options: std.ArrayListUnmanaged(schema.CommandOption) = .empty,
    default_member_permissions: ?[]const u8 = null,
    nsfw: ?bool = null,
    contexts: ?[]const i64 = null,
    integration_types: ?[]const i64 = null,
    name_localizations: ?std.json.Value = null,
    description_localizations: ?std.json.Value = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !Command {
        var self = Command{ .arena = std.heap.ArenaAllocator.init(allocator) };
        errdefer self.deinit();
        self.name = try self.arena.allocator().dupe(u8, name);
        self.description = try self.arena.allocator().dupe(u8, description);
        return self;
    }

    pub fn deinit(self: *Command) void {
        self.options.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setType(self: *Command, kind: CommandType) void {
        self.kind = kind;
    }

    pub fn setDefaultPermissions(self: *Command, permissions: ?[]const u8) !void {
        self.default_member_permissions = if (permissions) |p| try self.arena.allocator().dupe(u8, p) else null;
    }

    pub fn setNsfw(self: *Command, nsfw: bool) void {
        self.nsfw = nsfw;
    }

    pub fn setContexts(self: *Command, contexts: []const i64) !void {
        self.contexts = try self.arena.allocator().dupe(i64, contexts);
    }

    pub fn setIntegrationTypes(self: *Command, integration_types: []const i64) !void {
        self.integration_types = try self.arena.allocator().dupe(i64, integration_types);
    }

    fn putLocalization(self: *Command, which: *?std.json.Value, locale: []const u8, value: []const u8) !void {
        const aa = self.arena.allocator();
        if (which.* == null) which.* = .{ .object = .empty };
        try which.*.?.object.put(aa, try aa.dupe(u8, locale), .{ .string = try aa.dupe(u8, value) });
    }

    pub fn setNameLocalization(self: *Command, locale: []const u8, name: []const u8) !void {
        try self.putLocalization(&self.name_localizations, locale, name);
    }

    pub fn setDescriptionLocalization(self: *Command, locale: []const u8, description: []const u8) !void {
        try self.putLocalization(&self.description_localizations, locale, description);
    }

    pub fn addOption(self: *Command, opt: OptionInput) !void {
        try self.options.append(self.arena.allocator(), try self.dupeOption(opt));
    }

    pub fn addStringOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .string, .required = required });
    }

    pub fn addIntegerOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .integer, .required = required });
    }

    pub fn addBooleanOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .boolean, .required = required });
    }

    pub fn addUserOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .user, .required = required });
    }

    pub fn addChannelOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .channel, .required = required });
    }

    pub fn addRoleOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .role, .required = required });
    }

    pub fn addNumberOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .number, .required = required });
    }

    pub fn addAttachmentOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .attachment, .required = required });
    }

    pub fn addSubcommand(self: *Command, name: []const u8, description: []const u8, sub: []const OptionInput) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .sub_command, .options = sub });
    }

    pub fn addSubcommandGroup(self: *Command, name: []const u8, description: []const u8, subs: []const OptionInput) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .sub_command_group, .options = subs });
    }

    pub fn addAutocompleteStringOption(self: *Command, name: []const u8, description: []const u8, required: bool) !void {
        try self.addOption(.{ .name = name, .description = description, .kind = .string, .required = required, .autocomplete = true });
    }

    pub fn addChoice(self: *Command, option_name: []const u8, choice_name: []const u8, value: std.json.Value) !void {
        const aa = self.arena.allocator();
        for (self.options.items) |*o| {
            if (!std.mem.eql(u8, o.name, option_name)) continue;
            const grown = try aa.alloc(schema.CommandChoice, o.choices.len + 1);
            @memcpy(grown[0..o.choices.len], o.choices);
            grown[o.choices.len] = .{
                .name = try aa.dupe(u8, choice_name),
                .value = try cloneValue(aa, value),
            };
            o.choices = grown;
            return;
        }
        return error.OptionNotFound;
    }

    pub fn build(self: *Command) BuildError!schema.ApplicationCommandCreate {
        const chat = self.kind == .chat_input;
        if (chat) {
            if (!validName(self.name)) return error.NameInvalid;
            if (self.description.len == 0 or self.description.len > max_description_len) return error.DescriptionInvalid;
        } else {
            if (self.name.len == 0 or self.name.len > max_name_len) return error.NameInvalid;
            if (self.description.len != 0) return error.DescriptionInvalid;
        }
        try checkOptions(self.options.items, 0);
        return .{
            .name = self.name,
            .description = self.description,
            .type = @intFromEnum(self.kind),
            .options = self.options.items,
            .default_member_permissions = self.default_member_permissions,
            .nsfw = self.nsfw,
            .contexts = self.contexts,
            .integration_types = self.integration_types,
            .name_localizations = self.name_localizations,
            .description_localizations = self.description_localizations,
        };
    }

    fn checkOptions(options: []const schema.CommandOption, depth: u8) BuildError!void {
        if (options.len > max_options) return error.TooManyOptions;
        var seen_optional = false;
        for (options) |o| {
            if (o.required) {
                if (seen_optional) return error.RequiredAfterOptional;
            } else {
                seen_optional = true;
            }
            const kind: OptionType = @enumFromInt(o.type);
            switch (kind) {
                .sub_command, .sub_command_group => {
                    if (o.required) return error.SubcommandRequired;
                    if (kind == .sub_command_group) {
                        if (depth > 0) return error.BadNesting;
                    } else if (depth > 1) {
                        return error.BadNesting;
                    }
                    for (o.options) |sub| {
                        const sk: OptionType = @enumFromInt(sub.type);
                        if (kind == .sub_command_group) {
                            if (sk != .sub_command) return error.BadNesting;
                        } else if (sk == .sub_command or sk == .sub_command_group) {
                            return error.BadNesting;
                        }
                    }
                    try checkOptions(o.options, depth + 1);
                },
                .string, .integer, .number => {
                    if (o.options.len != 0) return error.BadNesting;
                    if (o.choices.len > max_choices) return error.TooManyChoices;
                    for (o.choices) |c| {
                        if (c.name.len == 0 or c.name.len > max_choice_name_len) return error.ChoiceNameInvalid;
                    }
                },
                else => {
                    if (o.options.len != 0) return error.BadNesting;
                    if (o.choices.len != 0) return error.ChoiceOnWrongType;
                    if (o.autocomplete) return error.AutocompleteOnWrongType;
                },
            }
            if (o.channel_types.len != 0 and kind != .channel) return error.ChannelTypesOnWrongType;
        }
    }

    fn dupeOption(self: *Command, opt: OptionInput) !schema.CommandOption {
        const aa = self.arena.allocator();
        const choices = try aa.alloc(schema.CommandChoice, opt.choices.len);
        for (opt.choices, 0..) |c, i| {
            choices[i] = .{
                .name = try aa.dupe(u8, c.name),
                .value = try cloneValue(aa, c.value),
            };
        }
        const subs = try aa.alloc(schema.CommandOption, opt.options.len);
        for (opt.options, 0..) |s, i| subs[i] = try self.dupeOption(s);
        const channel_types = try aa.alloc(i64, opt.channel_types.len);
        for (opt.channel_types, 0..) |ct, i| channel_types[i] = @intFromEnum(ct);
        return .{
            .name = try aa.dupe(u8, opt.name),
            .description = try aa.dupe(u8, opt.description),
            .type = @intFromEnum(opt.kind),
            .required = opt.required,
            .choices = choices,
            .options = subs,
            .channel_types = channel_types,
            .autocomplete = opt.autocomplete,
            .min_value = opt.min_value,
            .max_value = opt.max_value,
            .min_length = opt.min_length,
            .max_length = opt.max_length,
        };
    }
};

fn toFlags(flags: anytype) u32 {
    return if (@TypeOf(flags) == u32) flags else message.of(flags);
}

fn optionsFlags(options: anytype) u32 {
    const O = @TypeOf(options);
    if (@hasField(O, "flags")) return toFlags(options.flags);
    return 0;
}

fn optionsEmbeds(options: anytype) []const schema.Embed {
    const O = @TypeOf(options);
    if (@hasField(O, "embeds")) return options.embeds;
    return &.{};
}

fn optionsContent(options: anytype) ?[]const u8 {
    const O = @TypeOf(options);
    if (@hasField(O, "content")) return options.content;
    return null;
}

fn optionsComponents(options: anytype) []const schema.Component {
    const O = @TypeOf(options);
    if (@hasField(O, "components")) return options.components;
    return &.{};
}

fn optionsPoll(options: anytype) ?schema.PollCreate {
    const O = @TypeOf(options);
    if (@hasField(O, "poll")) return options.poll;
    return null;
}

fn optionsAttachments(options: anytype) []const attachment_mod.Attachment {
    const O = @TypeOf(options);
    if (@hasField(O, "attachments")) return options.attachments;
    return &.{};
}

const FileParts = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayListUnmanaged([]u8),
    parts: std.ArrayListUnmanaged(fetch_mod.MultipartFile),

    fn deinit(self: *FileParts) void {
        for (self.names.items) |n| self.allocator.free(n);
        self.names.deinit(self.allocator);
        self.parts.deinit(self.allocator);
    }

    fn items(self: *FileParts) []fetch_mod.MultipartFile {
        return self.parts.items;
    }
};

fn fileParts(allocator: std.mem.Allocator, files: []const attachment_mod.Attachment) !FileParts {
    var out = FileParts{
        .allocator = allocator,
        .names = .empty,
        .parts = .empty,
    };
    errdefer out.deinit();
    for (files, 0..) |f, i| {
        const name = try std.fmt.allocPrint(allocator, "files[{d}]", .{i});
        try out.names.append(allocator, name);
        try out.parts.append(allocator, f.toMultipart(name));
    }
    return out;
}

fn writeMessageFields(jw: anytype, content: ?[]const u8, bits: u32, embeds: []const schema.Embed, components: []const schema.Component, poll: ?schema.PollCreate, files: []const attachment_mod.Attachment) !void {
    if (content) |c| {
        try jw.objectField("content");
        try jw.write(c);
    }
    if (bits != 0) {
        try jw.objectField("flags");
        try jw.write(bits);
    }
    if (embeds.len > 0) {
        try jw.objectField("embeds");
        try jw.write(embeds);
    }
    if (components.len > 0) {
        try jw.objectField("components");
        try jw.write(components);
    }
    if (poll) |p| {
        try jw.objectField("poll");
        try jw.write(p);
    }
    if (files.len > 0) {
        try jw.objectField("attachments");
        try jw.beginArray();
        for (files, 0..) |f, i| {
            try jw.beginObject();
            try jw.objectField("id");
            try jw.write(@as(u32, @intCast(i)));
            try jw.objectField("filename");
            try jw.write(f.filename);
            if (f.description) |d| {
                try jw.objectField("description");
                try jw.write(d);
            }
            try jw.endObject();
        }
        try jw.endArray();
    }
}

fn dataBody(allocator: std.mem.Allocator, content: ?[]const u8, bits: u32, embeds: []const schema.Embed, components: []const schema.Component, poll: ?schema.PollCreate, files: []const attachment_mod.Attachment) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .emit_null_optional_fields = false } };
    try jw.beginObject();
    try writeMessageFields(&jw, content, bits, embeds, components, poll, files);
    try jw.endObject();
    return out.toOwnedSlice();
}

fn callbackBody(allocator: std.mem.Allocator, response_type: u8, content: ?[]const u8, bits: u32, embeds: []const schema.Embed, components: []const schema.Component, poll: ?schema.PollCreate, files: []const attachment_mod.Attachment) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .emit_null_optional_fields = false } };
    try jw.beginObject();
    try jw.objectField("type");
    try jw.write(response_type);
    try jw.objectField("data");
    try jw.beginObject();
    try writeMessageFields(&jw, content, bits, embeds, components, poll, files);
    try jw.endObject();
    try jw.endObject();
    return out.toOwnedSlice();
}

fn replyBody(allocator: std.mem.Allocator, content: []const u8, bits: u32) ![]u8 {
    return replyRichBody(allocator, content, bits, &.{}, &.{}, null, &.{});
}

fn replyRichBody(allocator: std.mem.Allocator, content: ?[]const u8, bits: u32, embeds: []const schema.Embed, components: []const schema.Component, poll: ?schema.PollCreate, files: []const attachment_mod.Attachment) ![]u8 {
    return callbackBody(allocator, 4, content, bits, embeds, components, poll, files);
}

pub fn reply(allocator: std.mem.Allocator, content: []const u8, flags: anytype) ![]u8 {
    return replyBody(allocator, content, toFlags(flags));
}

pub fn deferReply(allocator: std.mem.Allocator, flags: anytype) ![]u8 {
    return deferReplyBody(allocator, toFlags(flags));
}

fn deferReplyBody(allocator: std.mem.Allocator, bits: u32) ![]u8 {
    if (bits == 0) {
        return std.json.Stringify.valueAlloc(allocator, .{ .type = 5 }, .{});
    }
    return std.json.Stringify.valueAlloc(allocator, .{
        .type = 5,
        .data = .{ .flags = bits },
    }, .{});
}

pub fn pongResponse(allocator: std.mem.Allocator) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .type = 1 }, .{});
}

pub fn autocompleteBody(allocator: std.mem.Allocator, choices: []const schema.CommandChoice) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .type = 8,
        .data = .{ .choices = choices },
    }, .{});
}

pub fn modalBody(allocator: std.mem.Allocator, modal: schema.Modal) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .type = 9,
        .data = modal,
    }, .{});
}

fn followUpBody(allocator: std.mem.Allocator, content: ?[]const u8, bits: u32, embeds: []const schema.Embed, components: []const schema.Component, poll: ?schema.PollCreate, files: []const attachment_mod.Attachment) ![]u8 {
    return dataBody(allocator, content, bits, embeds, components, poll, files);
}

fn editBody(allocator: std.mem.Allocator, content: ?[]const u8, bits: u32, embeds: []const schema.Embed, components: []const schema.Component, poll: ?schema.PollCreate, files: []const attachment_mod.Attachment) ![]u8 {
    return dataBody(allocator, content, bits, embeds, components, poll, files);
}

pub fn encodeCommands(allocator: std.mem.Allocator, cmds: []const schema.ApplicationCommandCreate) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, cmds, .{ .emit_null_optional_fields = false });
}

pub const ContextMenuCommandBuilder = struct {
    arena: std.heap.ArenaAllocator,
    name: []const u8 = "",
    kind: CommandType = .user,
    default_member_permissions: ?[]const u8 = null,
    nsfw: ?bool = null,
    contexts: ?[]const i64 = null,
    integration_types: ?[]const i64 = null,
    name_localizations: ?std.json.Value = null,

    pub fn init(allocator: std.mem.Allocator) ContextMenuCommandBuilder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *ContextMenuCommandBuilder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setName(self: *ContextMenuCommandBuilder, name: []const u8) !void {
        self.name = try self.arena.allocator().dupe(u8, name);
    }

    pub fn setType(self: *ContextMenuCommandBuilder, kind: CommandType) void {
        self.kind = kind;
    }

    pub fn setDefaultMemberPermissions(self: *ContextMenuCommandBuilder, permissions: ?[]const u8) !void {
        self.default_member_permissions = if (permissions) |p| try self.arena.allocator().dupe(u8, p) else null;
    }

    pub fn setNsfw(self: *ContextMenuCommandBuilder, nsfw: bool) void {
        self.nsfw = nsfw;
    }

    pub fn setContexts(self: *ContextMenuCommandBuilder, contexts: []const i64) !void {
        self.contexts = try self.arena.allocator().dupe(i64, contexts);
    }

    pub fn setIntegrationTypes(self: *ContextMenuCommandBuilder, integration_types: []const i64) !void {
        self.integration_types = try self.arena.allocator().dupe(i64, integration_types);
    }

    pub fn setNameLocalization(self: *ContextMenuCommandBuilder, locale: []const u8, name: []const u8) !void {
        const aa = self.arena.allocator();
        if (self.name_localizations == null) self.name_localizations = .{ .object = .empty };
        try self.name_localizations.?.object.put(aa, try aa.dupe(u8, locale), .{ .string = try aa.dupe(u8, name) });
    }

    pub fn build(self: *ContextMenuCommandBuilder) BuildError!schema.ApplicationCommandCreate {
        if (self.name.len == 0 or self.name.len > max_name_len) return error.NameInvalid;
        if (self.kind != .user and self.kind != .message) return error.NameInvalid;
        return .{
            .name = self.name,
            .description = "",
            .type = @intFromEnum(self.kind),
            .options = &.{},
            .default_member_permissions = self.default_member_permissions,
            .nsfw = self.nsfw,
            .contexts = self.contexts,
            .integration_types = self.integration_types,
            .name_localizations = self.name_localizations,
        };
    }
};

pub const ApplicationCommands = struct {
    rest: *client_mod.Rest,
    application_id: []const u8,

    pub fn init(rest: *client_mod.Rest, application_id: []const u8) ApplicationCommands {
        return .{ .rest = rest, .application_id = application_id };
    }

    pub fn set(self: ApplicationCommands, commands: anytype) !std.json.Parsed([]schema.ApplicationCommand) {
        const T = @TypeOf(commands);
        if (T == []const u8) {
            return self.rest.registerGlobalCommands(self.application_id, commands);
        }
        const json = try std.json.Stringify.valueAlloc(self.rest.allocator, commands, .{ .emit_null_optional_fields = false });
        defer self.rest.allocator.free(json);
        return self.rest.registerGlobalCommands(self.application_id, json);
    }

    pub fn create(self: ApplicationCommands, command: anytype) !std.json.Parsed(schema.ApplicationCommand) {
        const T = @TypeOf(command);
        if (T == []const u8) {
            const res = try self.rest.request(.POST, try std.fmt.allocPrint(self.rest.allocator, "/applications/{s}/commands", .{self.application_id}), command);
            defer self.rest.allocator.free(res.body);
            return client_mod.parseBody(schema.ApplicationCommand, self.rest.allocator, res.status_code, res.body);
        }
        const json = try std.json.Stringify.valueAlloc(self.rest.allocator, command, .{ .emit_null_optional_fields = false });
        defer self.rest.allocator.free(json);
        const path = try std.fmt.allocPrint(self.rest.allocator, "/applications/{s}/commands", .{self.application_id});
        defer self.rest.allocator.free(path);
        const res = try self.rest.request(.POST, path, json);
        defer self.rest.allocator.free(res.body);
        return client_mod.parseBody(schema.ApplicationCommand, self.rest.allocator, res.status_code, res.body);
    }

    pub fn fetchAll(self: ApplicationCommands) !std.json.Parsed([]schema.ApplicationCommand) {
        return self.rest.listApplicationCommands(self.application_id);
    }

    pub fn fetch(self: ApplicationCommands, command_id: []const u8) !std.json.Parsed(schema.ApplicationCommand) {
        return self.rest.getApplicationCommand(self.application_id, command_id);
    }

    pub fn edit(self: ApplicationCommands, command_id: []const u8, body: []const u8) !std.json.Parsed(schema.ApplicationCommand) {
        return self.rest.editApplicationCommand(self.application_id, command_id, body);
    }

    pub fn delete(self: ApplicationCommands, command_id: []const u8) !void {
        return self.rest.deleteApplicationCommand(self.application_id, command_id);
    }

    pub fn fetchPermissions(self: ApplicationCommands, guild_id: []const u8) !std.json.Parsed([]schema.CommandPermissions) {
        return self.rest.fetchCommandPermissions(self.application_id, guild_id);
    }

    pub fn fetchCommandPermissions(self: ApplicationCommands, guild_id: []const u8, command_id: []const u8) !std.json.Parsed(schema.CommandPermissions) {
        return self.rest.fetchSingleCommandPermissions(self.application_id, guild_id, command_id);
    }

    pub fn setCommandPermissions(self: ApplicationCommands, guild_id: []const u8, command_id: []const u8, permissions: []const schema.CommandPermissionEntry) !std.json.Parsed(schema.CommandPermissions) {
        return self.rest.setCommandPermissions(self.application_id, guild_id, command_id, permissions);
    }
};

pub const Interaction = struct {
    rest: *client_mod.Rest,
    id: []const u8,
    token: []const u8,
    application_id: []const u8,

    pub fn init(rest: *client_mod.Rest, data: schema.Interaction) Interaction {
        return .{
            .rest = rest,
            .id = data.id,
            .token = data.token,
            .application_id = data.application_id,
        };
    }

    fn alloc(self: Interaction) std.mem.Allocator {
        return self.rest.allocator;
    }

    pub fn reply(self: Interaction, options: anytype) !void {
        // options.* é só lido durante a construção síncrona do corpo:
        // sem dupes temporários.
        const embeds = optionsEmbeds(options);
        const components = optionsComponents(options);
        const attachments = optionsAttachments(options);
        const body = try replyRichBody(self.alloc(), optionsContent(options), optionsFlags(options), embeds, components, optionsPoll(options), attachments);
        defer self.alloc().free(body);
        if (attachments.len == 0) {
            try self.rest.respondInteraction(self.id, self.token, body);
            return;
        }
        var parts = try fileParts(self.alloc(), attachments);
        defer parts.deinit();
        try self.rest.respondInteractionMultipart(self.id, self.token, body, parts.items());
    }

    pub fn deferReply(self: Interaction, options: anytype) !void {
        const body = try deferReplyBody(self.alloc(), optionsFlags(options));
        defer self.alloc().free(body);
        try self.rest.respondInteraction(self.id, self.token, body);
    }

    pub fn deferUpdate(self: Interaction) !void {
        const body = try std.json.Stringify.valueAlloc(self.alloc(), .{ .type = 6 }, .{});
        defer self.alloc().free(body);
        try self.rest.respondInteraction(self.id, self.token, body);
    }

    pub fn update(self: Interaction, options: anytype) !void {
        const embeds = optionsEmbeds(options);
        const components = optionsComponents(options);
        const attachments = optionsAttachments(options);
        const body = try callbackBody(self.alloc(), 7, optionsContent(options), optionsFlags(options), embeds, components, optionsPoll(options), attachments);
        defer self.alloc().free(body);
        if (attachments.len == 0) {
            try self.rest.respondInteraction(self.id, self.token, body);
            return;
        }
        var parts = try fileParts(self.alloc(), attachments);
        defer parts.deinit();
        try self.rest.respondInteractionMultipart(self.id, self.token, body, parts.items());
    }

    pub fn editReply(self: Interaction, options: anytype) !void {
        const embeds = optionsEmbeds(options);
        const components = optionsComponents(options);
        const attachments = optionsAttachments(options);
        const body = try editBody(self.alloc(), optionsContent(options), optionsFlags(options), embeds, components, optionsPoll(options), attachments);
        defer self.alloc().free(body);
        if (attachments.len == 0) {
            var resp = try self.rest.editOriginalInteractionResponse(self.application_id, self.token, body);
            defer resp.deinit();
            return;
        }
        var parts = try fileParts(self.alloc(), attachments);
        defer parts.deinit();
        var resp = try self.rest.editOriginalInteractionMultipart(self.application_id, self.token, body, parts.items());
        defer resp.deinit();
    }

    pub fn followUp(self: Interaction, options: anytype) !std.json.Parsed(schema.Message) {
        const embeds = optionsEmbeds(options);
        const components = optionsComponents(options);
        const attachments = optionsAttachments(options);
        const body = try followUpBody(self.alloc(), optionsContent(options), optionsFlags(options), embeds, components, optionsPoll(options), attachments);
        defer self.alloc().free(body);
        if (attachments.len == 0) {
            return self.rest.followUp(self.application_id, self.token, body);
        }
        var parts = try fileParts(self.alloc(), attachments);
        defer parts.deinit();
        return self.rest.followUpMultipart(self.application_id, self.token, body, parts.items());
    }

    pub fn deleteReply(self: Interaction) !void {
        try self.rest.deleteInitialResponse(self.application_id, self.token);
    }

    pub fn deleteFollowUp(self: Interaction, message_id: []const u8) !void {
        try self.rest.deleteFollowUp(self.application_id, self.token, message_id);
    }

    pub fn fetchReply(self: Interaction) !std.json.Parsed(schema.Message) {
        return self.rest.getOriginalInteractionResponse(self.application_id, self.token);
    }

    pub fn autocomplete(self: Interaction, choices: []const schema.CommandChoice) !void {
        const body = try autocompleteBody(self.alloc(), choices);
        defer self.alloc().free(body);
        try self.rest.respondInteraction(self.id, self.token, body);
    }

    pub fn pong(self: Interaction) !void {
        const body = try pongResponse(self.alloc());
        defer self.alloc().free(body);
        try self.rest.respondInteraction(self.id, self.token, body);
    }

    pub fn showModal(self: Interaction, modal: schema.Modal) !void {
        const body = try modalBody(self.alloc(), modal);
        defer self.alloc().free(body);
        try self.rest.respondInteraction(self.id, self.token, body);
    }

    pub fn isCommand(data: schema.Interaction) bool {
        return data.type == 2;
    }

    pub fn isChatInputCommand(data: schema.Interaction) bool {
        if (data.type != 2) return false;
        if (data.data) |d| {
            return d.type == null or d.type.? == 1;
        }
        return true;
    }

    pub fn isContextMenuCommand(data: schema.Interaction) bool {
        if (data.type != 2) return false;
        if (data.data) |d| {
            return d.type != null and (d.type.? == 2 or d.type.? == 3);
        }
        return false;
    }

    pub fn isButton(data: schema.Interaction) bool {
        if (data.type != 3) return false;
        if (data.data) |d| {
            if (d.component_type) |ct| return ct == 2;
        }
        return false;
    }

    pub fn isStringSelectMenu(data: schema.Interaction) bool {
        if (data.type != 3) return false;
        if (data.data) |d| {
            if (d.component_type) |ct| return ct == 3;
        }
        return false;
    }

    pub fn isAnySelectMenu(data: schema.Interaction) bool {
        if (data.type != 3) return false;
        if (data.data) |d| {
            if (d.component_type) |ct| return ct >= 3 and ct <= 8;
        }
        return false;
    }

    pub fn isModalSubmit(data: schema.Interaction) bool {
        return data.type == 5;
    }

    pub fn isAutocomplete(data: schema.Interaction) bool {
        return data.type == 4;
    }

    pub fn customId(data: schema.Interaction) ?[]const u8 {
        if (data.data) |d| return d.custom_id;
        return null;
    }

    pub fn values(data: schema.Interaction) []const []const u8 {
        if (data.data) |d| return d.values;
        return &.{};
    }
};
