const std = @import("std");
const slash = @import("discord-zig").slash;
const schema = @import("discord-zig").schema;
const client = @import("discord-zig").client;
const message = @import("discord-zig").message;
const attachment = @import("discord-zig").attachment;

test "ping command json" {
    var cmd = try slash.Command.init(std.testing.allocator, "ping", "Responde pong");
    defer cmd.deinit();
    const built = try cmd.build();
    const body = try slash.encodeCommands(std.testing.allocator, &.{built});
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("[{\"name\":\"ping\",\"description\":\"Responde pong\",\"type\":1,\"options\":[]}]", body);
}

test "command with options and choices json" {
    var cmd = try slash.Command.init(std.testing.allocator, "eco", "Ecoa texto");
    defer cmd.deinit();
    try cmd.addStringOption("texto", "o que ecoar", true);
    try cmd.addChoice("texto", "curto", .{ .string = "s" });
    try cmd.addChoice("texto", "num", .{ .integer = 1 });
    try cmd.addIntegerOption("vezes", "repetições", false);
    const built = try cmd.build();
    const body = try slash.encodeCommands(std.testing.allocator, &.{built});
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("[{\"name\":\"eco\",\"description\":\"Ecoa texto\",\"type\":1,\"options\":[{\"name\":\"texto\",\"description\":\"o que ecoar\",\"type\":3,\"required\":true,\"choices\":[{\"name\":\"curto\",\"value\":\"s\"},{\"name\":\"num\",\"value\":1}],\"options\":[],\"channel_types\":[],\"autocomplete\":false},{\"name\":\"vezes\",\"description\":\"repetições\",\"type\":4,\"required\":false,\"choices\":[],\"options\":[],\"channel_types\":[],\"autocomplete\":false}]}]", body);
}

test "autocomplete min max and localizations json" {
    var cmd = try slash.Command.init(std.testing.allocator, "busca", "x");
    defer cmd.deinit();
    try cmd.addAutocompleteStringOption("q", "termo", true);
    try cmd.addOption(.{ .name = "n", .description = "d", .kind = .integer, .min_value = 1, .max_value = 10 });
    try cmd.setNameLocalization("pt-BR", "busca");
    try cmd.setDescriptionLocalization("pt-BR", "y");
    const built = try cmd.build();
    const body = try slash.encodeCommands(std.testing.allocator, &.{built});
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("[{\"name\":\"busca\",\"description\":\"x\",\"type\":1,\"options\":[{\"name\":\"q\",\"description\":\"termo\",\"type\":3,\"required\":true,\"choices\":[],\"options\":[],\"channel_types\":[],\"autocomplete\":true},{\"name\":\"n\",\"description\":\"d\",\"type\":4,\"required\":false,\"choices\":[],\"options\":[],\"channel_types\":[],\"autocomplete\":false,\"min_value\":1,\"max_value\":10}],\"name_localizations\":{\"pt-BR\":\"busca\"},\"description_localizations\":{\"pt-BR\":\"y\"}}]", body);

    var bad = try slash.Command.init(std.testing.allocator, "x", "y");
    defer bad.deinit();
    try bad.addBooleanOption("flag", "d", false);
    bad.options.items[0].autocomplete = true;
    try std.testing.expectError(error.AutocompleteOnWrongType, bad.build());
}

test "subcommand group nesting builds" {
    var cmd = try slash.Command.init(std.testing.allocator, "mod", "x");
    defer cmd.deinit();
    try cmd.addSubcommandGroup("user", "d", &.{
        .{ .name = "kick", .description = "d", .kind = .sub_command, .options = &.{.{ .name = "alvo", .description = "d", .kind = .user, .required = true }} },
    });
    const built = try cmd.build();
    try std.testing.expectEqual(@as(usize, 1), built.options.len);
    try std.testing.expectEqual(@as(u8, 2), built.options[0].type);
    try std.testing.expectEqual(@as(u8, 1), built.options[0].options[0].type);
}

test "command registration extras json" {
    var cmd = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer cmd.deinit();
    try cmd.setDefaultPermissions("8");
    cmd.setNsfw(true);
    try cmd.setContexts(&.{ 0, 1 });
    try cmd.setIntegrationTypes(&.{0});
    const built = try cmd.build();
    const body = try slash.encodeCommands(std.testing.allocator, &.{built});
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("[{\"name\":\"ping\",\"description\":\"x\",\"type\":1,\"options\":[],\"default_member_permissions\":\"8\",\"nsfw\":true,\"contexts\":[0,1],\"integration_types\":[0]}]", body);
}

test "subcommand nesting" {
    var cmd = try slash.Command.init(std.testing.allocator, "mod", "Moderação");
    defer cmd.deinit();
    try cmd.addSubcommand("kick", "Expulsa membro", &.{
        .{ .name = "alvo", .description = "quem", .kind = .user, .required = true },
    });
    const built = try cmd.build();
    try std.testing.expectEqual(@as(usize, 1), built.options.len);
    try std.testing.expectEqual(@as(u8, 1), built.options[0].type);
    try std.testing.expectEqual(@as(usize, 1), built.options[0].options.len);
    try std.testing.expectEqual(@as(u8, 6), built.options[0].options[0].type);
}

test "name validation" {
    var a = try slash.Command.init(std.testing.allocator, "Com Espaço", "x");
    defer a.deinit();
    try std.testing.expectError(error.NameInvalid, a.build());

    var b = try slash.Command.init(std.testing.allocator, "", "x");
    defer b.deinit();
    try std.testing.expectError(error.NameInvalid, b.build());

    var c = try slash.Command.init(std.testing.allocator, "a" ** 33, "x");
    defer c.deinit();
    try std.testing.expectError(error.NameInvalid, c.build());
}

test "description validation" {
    var a = try slash.Command.init(std.testing.allocator, "ping", "");
    defer a.deinit();
    try std.testing.expectError(error.DescriptionInvalid, a.build());

    var b = try slash.Command.init(std.testing.allocator, "perfil", "mostra perfil");
    defer b.deinit();
    b.setType(.user);
    try std.testing.expectError(error.DescriptionInvalid, b.build());

    var c = try slash.Command.init(std.testing.allocator, "perfil", "");
    defer c.deinit();
    c.setType(.user);
    _ = try c.build();
}

test "too many options" {
    var cmd = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer cmd.deinit();
    var i: usize = 0;
    while (i < 26) : (i += 1) {
        const name = try std.fmt.allocPrint(std.testing.allocator, "opt{d}", .{i});
        defer std.testing.allocator.free(name);
        try cmd.addStringOption(name, "d", false);
    }
    try std.testing.expectError(error.TooManyOptions, cmd.build());
}

test "required after optional" {
    var cmd = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer cmd.deinit();
    try cmd.addStringOption("a", "d", false);
    try cmd.addStringOption("b", "d", true);
    try std.testing.expectError(error.RequiredAfterOptional, cmd.build());
}

test "subcommand cannot be required" {
    var cmd = try slash.Command.init(std.testing.allocator, "mod", "x");
    defer cmd.deinit();
    try cmd.addOption(.{ .name = "kick", .description = "d", .kind = .sub_command, .required = true });
    try std.testing.expectError(error.SubcommandRequired, cmd.build());
}

test "bad nesting rejected" {
    var a = try slash.Command.init(std.testing.allocator, "mod", "x");
    defer a.deinit();
    try a.addOption(.{
        .name = "g",
        .description = "d",
        .kind = .sub_command_group,
        .options = &.{.{ .name = "s", .description = "d", .kind = .string }},
    });
    try std.testing.expectError(error.BadNesting, a.build());

    var b = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer b.deinit();
    try b.addOption(.{
        .name = "s",
        .description = "d",
        .kind = .string,
        .options = &.{.{ .name = "n", .description = "d", .kind = .string }},
    });
    try std.testing.expectError(error.BadNesting, b.build());
}

test "choices validated" {
    var a = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer a.deinit();
    try a.addBooleanOption("flag", "d", false);
    try a.addChoice("flag", "sim", .{ .bool = true });
    try std.testing.expectError(error.ChoiceOnWrongType, a.build());

    var b = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer b.deinit();
    try b.addStringOption("texto", "d", false);
    try b.addChoice("texto", "", .{ .string = "s" });
    try std.testing.expectError(error.ChoiceNameInvalid, b.build());

    var c = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer c.deinit();
    try std.testing.expectError(error.OptionNotFound, c.addChoice("falta", "s", .{ .string = "s" }));
}

test "channel types only on channel options" {
    var cmd = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer cmd.deinit();
    try cmd.addOption(.{ .name = "s", .description = "d", .kind = .string, .channel_types = &.{.guild_text} });
    try std.testing.expectError(error.ChannelTypesOnWrongType, cmd.build());
}

test "interaction response json" {
    const MF = message.MessageFlags;
    const msg = try slash.reply(std.testing.allocator, "Pong!", .{});
    defer std.testing.allocator.free(msg);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"Pong!\"}}", msg);

    const eph = try slash.reply(std.testing.allocator, "só você vê", .{MF.Ephemeral});
    defer std.testing.allocator.free(eph);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"só você vê\",\"flags\":64}}", eph);

    const pong = try slash.pongResponse(std.testing.allocator);
    defer std.testing.allocator.free(pong);
    try std.testing.expectEqualStrings("{\"type\":1}", pong);

    const def = try slash.deferReply(std.testing.allocator, .{MF.Ephemeral});
    defer std.testing.allocator.free(def);
    try std.testing.expectEqualStrings("{\"type\":5,\"data\":{\"flags\":64}}", def);
}

fn replyWithRuntimeFlags(allocator: std.mem.Allocator, flags: u32) ![]u8 {
    return slash.reply(allocator, "hi", flags);
}

test "reply and deferReply accept flags tuple" {
    const MF = message.MessageFlags;
    const plain = try slash.reply(std.testing.allocator, "hi", .{});
    defer std.testing.allocator.free(plain);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"hi\"}}", plain);

    const flagged = try slash.reply(std.testing.allocator, "hi", .{ MF.Ephemeral, MF.SuppressNotifications });
    defer std.testing.allocator.free(flagged);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"hi\",\"flags\":4160}}", flagged);

    const raw = try slash.reply(std.testing.allocator, "hi", @as(u32, 64));
    defer std.testing.allocator.free(raw);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"hi\",\"flags\":64}}", raw);

    const dyn_reply = try replyWithRuntimeFlags(std.testing.allocator, 64);
    defer std.testing.allocator.free(dyn_reply);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"hi\",\"flags\":64}}", dyn_reply);

    const dd = try slash.deferReply(std.testing.allocator, .{MF.Ephemeral});
    defer std.testing.allocator.free(dd);
    try std.testing.expectEqualStrings("{\"type\":5,\"data\":{\"flags\":64}}", dd);

    const dp = try slash.deferReply(std.testing.allocator, .{});
    defer std.testing.allocator.free(dp);
    try std.testing.expectEqualStrings("{\"type\":5}", dp);
}

test "encode commands array" {
    var cmd = try slash.Command.init(std.testing.allocator, "ping", "x");
    defer cmd.deinit();
    const built = try cmd.build();
    const body = try slash.encodeCommands(std.testing.allocator, &.{built});
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("[{\"name\":\"ping\",\"description\":\"x\",\"type\":1,\"options\":[]}]", body);
}

test "interaction option helpers" {
    const body =
        \\{"id":"1","application_id":"2","type":2,"token":"t","data":{"id":"3","name":"eco","type":1,"options":[{"name":"texto","type":3,"value":"oi"},{"name":"vezes","type":4,"value":2},{"name":"flag","type":5,"value":true}]}}
    ;
    var parsed = try schema.parse(schema.Interaction, std.testing.allocator, body);
    defer parsed.deinit();
    const data = parsed.value.data.?;
    try std.testing.expectEqualStrings("eco", data.name);
    const texto = data.get("texto").?;
    try std.testing.expectEqualStrings("oi", texto.asString().?);
    try std.testing.expect(texto.asInteger() == null);
    try std.testing.expectEqual(@as(i64, 2), data.get("vezes").?.asInteger().?);
    try std.testing.expectEqual(true, data.get("flag").?.asBool().?);
    try std.testing.expect(data.get("falta") == null);
}

const MockReq = struct {
    method: [8]u8 = [_]u8{0} ** 8,
    method_len: usize = 0,
    path: [256]u8 = [_]u8{0} ** 256,
    path_len: usize = 0,
    body: [1024]u8 = [_]u8{0} ** 1024,
    body_len: usize = 0,

    fn methodStr(self: *const MockReq) []const u8 {
        return self.method[0..self.method_len];
    }

    fn pathStr(self: *const MockReq) []const u8 {
        return self.path[0..self.path_len];
    }

    fn bodyStr(self: *const MockReq) []const u8 {
        return self.body[0..self.body_len];
    }
};

const InteractionMockCtx = struct {
    server: *std.Io.net.Server,
    err: ?anyerror = null,
    reqs: [8]MockReq = .{ .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{} },
    count: usize = 0,
    want: usize = 0,
    saw_connection_close: [8]bool = .{ false, false, false, false, false, false, false, false },
};

fn mockReadFull(io: std.Io, stream: *std.Io.net.Stream, buf: []u8) !void {
    var off: usize = 0;
    while (off < buf.len) {
        var pfd = [_]std.posix.pollfd{.{ .fd = stream.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = try std.posix.poll(&pfd, 10000);
        if (ready == 0) return error.Timeout;
        var data = [_][]u8{buf[off..]};
        const n = try io.vtable.netRead(io.userdata, stream.socket.handle, &data);
        if (n == 0) return error.ConnectionClosed;
        off += n;
    }
}

fn mockWriteAll(io: std.Io, stream: *std.Io.net.Stream, data: []const u8) !void {
    var wbuf: [4096]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

fn interactionMockMain(ctx: *InteractionMockCtx) void {
    interactionMockRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn interactionMockRun(ctx: *InteractionMockCtx) !void {
    const io = std.testing.io;
    while (ctx.count < ctx.want) {
        var stream = try ctx.server.accept(io);
        defer stream.close(io);
        var slot = &ctx.reqs[ctx.count];
        ctx.count += 1;

        var head_buf: [8192]u8 = undefined;
        var head_len: usize = 0;
        while (true) {
            if (head_len >= head_buf.len) return error.RequestTooLarge;
            var byte: [1]u8 = undefined;
            try mockReadFull(io, &stream, &byte);
            head_buf[head_len] = byte[0];
            head_len += 1;
            if (head_len >= 4 and std.mem.eql(u8, head_buf[head_len - 4 .. head_len], "\r\n\r\n")) break;
        }
        const head = head_buf[0..head_len];

        var lines = std.mem.splitSequence(u8, head, "\r\n");
        const request_line = lines.first();
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.first();
        const path = parts.next() orelse return error.BadRequestLine;
        @memcpy(slot.method[0..method.len], method);
        slot.method_len = method.len;
        @memcpy(slot.path[0..path.len], path);
        slot.path_len = path.len;

        var content_len: usize = 0;
        while (lines.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                content_len = try std.fmt.parseInt(usize, value, 10);
            }
            if (std.ascii.eqlIgnoreCase(name, "connection")) {
                if (std.ascii.eqlIgnoreCase(value, "close")) ctx.saw_connection_close[ctx.count - 1] = true;
            }
        }
        if (content_len > slot.body.len) return error.BodyTooLarge;
        if (content_len > 0) try mockReadFull(io, &stream, slot.body[0..content_len]);
        slot.body_len = content_len;

        if (std.mem.eql(u8, slot.methodStr(), "DELETE")) {
            try mockWriteAll(io, &stream, "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        } else if (std.mem.eql(u8, slot.methodStr(), "GET")) {
            const body = "{\"id\":\"1\",\"channel_id\":\"2\",\"author\":{\"id\":\"3\",\"username\":\"bot\"}}";
            var resp_buf: [256]u8 = undefined;
            const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body });
            try mockWriteAll(io, &stream, resp);
        } else if (std.mem.indexOf(u8, slot.pathStr(), "with_response") != null) {
            const body = "{\"resource\":{\"type\":0,\"message\":{\"id\":\"9\",\"channel_id\":\"2\",\"author\":{\"id\":\"3\",\"username\":\"bot\"}}}}";
            var resp_buf: [512]u8 = undefined;
            const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body });
            try mockWriteAll(io, &stream, resp);
        } else if (std.mem.eql(u8, slot.methodStr(), "PATCH") or std.mem.startsWith(u8, slot.pathStr(), "/webhooks")) {
            const body = "{\"id\":\"1\",\"channel_id\":\"2\",\"author\":{\"id\":\"3\",\"username\":\"bot\"}}";
            var resp_buf: [256]u8 = undefined;
            const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body });
            try mockWriteAll(io, &stream, resp);
        } else {
            try mockWriteAll(io, &stream, "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        }
    }
}

const InteractionMockSetup = struct {
    port: u16,
    server: std.Io.net.Server,
    thread: std.Thread,
    ctx: InteractionMockCtx,
    joined: bool = false,

    pub fn join(self: *InteractionMockSetup) void {
        if (!self.joined) {
            _ = std.os.linux.shutdown(self.server.socket.handle, std.os.linux.SHUT.RDWR);
            self.thread.join();
            self.joined = true;
        }
    }
};

fn withInteractionMock(want: usize) !*InteractionMockSetup {
    const io = std.testing.io;
    const setup = try std.testing.allocator.create(InteractionMockSetup);
    errdefer std.testing.allocator.destroy(setup);

    var bound = false;
    for ([_]u16{ 18561, 18562, 18563 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            setup.* = .{
                .port = p,
                .server = s,
                .thread = undefined,
                .ctx = .{ .server = undefined, .want = want, .err = null },
            };
            bound = true;
            break;
        } else |_| continue;
    }
    if (!bound) return error.CannotBindTestServer;
    errdefer setup.server.deinit(io);

    setup.ctx.server = &setup.server;
    setup.thread = try std.Thread.spawn(.{}, interactionMockMain, .{&setup.ctx});
    return setup;
}

fn destroyInteractionMock(setup: *InteractionMockSetup) void {
    setup.join();
    setup.server.deinit(std.testing.io);
    std.testing.allocator.destroy(setup);
}

test "interaction handle deferReply and editReply" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(4);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });

    try handle.deferReply(.{ .flags = .{message.Bits.ephemeral} });
    try handle.editReply(.{ .content = "Pong!" });
    try handle.reply(.{ .content = "hi" });
    try handle.deferReply(.{ .flags = .{message.MessageFlags.Ephemeral} });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);

    const defer_req = &setup.ctx.reqs[0];
    try std.testing.expectEqualStrings("POST", defer_req.methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback", defer_req.pathStr());
    try std.testing.expectEqualStrings("{\"type\":5,\"data\":{\"flags\":64}}", defer_req.bodyStr());

    const edit_req = &setup.ctx.reqs[1];
    try std.testing.expectEqualStrings("PATCH", edit_req.methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN/messages/@original", edit_req.pathStr());
    try std.testing.expectEqualStrings("{\"content\":\"Pong!\"}", edit_req.bodyStr());

    const reply_req = &setup.ctx.reqs[2];
    try std.testing.expectEqualStrings("POST", reply_req.methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback", reply_req.pathStr());
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"content\":\"hi\"}}", reply_req.bodyStr());

    const flags_req = &setup.ctx.reqs[3];
    try std.testing.expectEqualStrings("POST", flags_req.methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback", flags_req.pathStr());
    try std.testing.expectEqualStrings("{\"type\":5,\"data\":{\"flags\":64}}", flags_req.bodyStr());

    for (setup.ctx.saw_connection_close[0..setup.ctx.count]) |saw| {
        try std.testing.expect(!saw);
    }
}

test "interaction types parse with guards and helpers" {
    const button =
        \\{"id":"10","application_id":"2","type":3,"token":"t","data":{"custom_id":"btn-yes","component_type":2},"message":{"id":"7","channel_id":"8","author":{"id":"3","username":"bot"}}}
    ;
    var parsed_btn = try schema.parse(schema.Interaction, std.testing.allocator, button);
    defer parsed_btn.deinit();
    const btn = parsed_btn.value;
    try std.testing.expect(btn.isComponent());
    try std.testing.expect(!btn.isChatInput());
    try std.testing.expect(!btn.isModalSubmit());
    try std.testing.expectEqualStrings("btn-yes", btn.data.?.custom_id.?);
    try std.testing.expectEqual(@as(u8, 2), btn.data.?.component_type.?);
    try std.testing.expectEqualStrings("7", btn.message.?.id);

    const auto =
        \\{"id":"11","application_id":"2","type":4,"token":"t","data":{"id":"3","name":"eco","type":1,"options":[{"name":"texto","type":3,"value":"oi","focused":true},{"name":"vezes","type":4,"value":2}]}}
    ;
    var parsed_auto = try schema.parse(schema.Interaction, std.testing.allocator, auto);
    defer parsed_auto.deinit();
    const actx = parsed_auto.value;
    try std.testing.expect(actx.isAutocomplete());
    const focused = actx.data.?.getFocused().?;
    try std.testing.expectEqualStrings("texto", focused.name);
    try std.testing.expectEqualStrings("oi", focused.asString().?);

    const modal =
        \\{"id":"12","application_id":"2","type":5,"token":"t","data":{"custom_id":"modal-x","components":[{"type":1,"components":[{"type":4,"custom_id":"field-a","value":"hello"}]}]}}
    ;
    var parsed_modal = try schema.parse(schema.Interaction, std.testing.allocator, modal);
    defer parsed_modal.deinit();
    const mctx = parsed_modal.value;
    try std.testing.expect(mctx.isModalSubmit());
    try std.testing.expectEqualStrings("modal-x", mctx.data.?.custom_id.?);
    try std.testing.expectEqualStrings("hello", mctx.data.?.getTextInput("field-a").?);
    try std.testing.expect(mctx.data.?.getTextInput("missing") == null);

    const modal_select =
        \\{"id":"14","application_id":"2","type":5,"token":"t","data":{"custom_id":"m2","components":[{"type":18,"id":1,"component":{"type":5,"id":2,"custom_id":"who","values":["7","9"]}}]}}
    ;
    var parsed_sel = try schema.parse(schema.Interaction, std.testing.allocator, modal_select);
    defer parsed_sel.deinit();
    const vals = parsed_sel.value.data.?.getSelectedValues("who").?;
    try std.testing.expectEqual(@as(usize, 2), vals.len);
    try std.testing.expectEqualStrings("7", vals[0]);
    try std.testing.expect(parsed_sel.value.data.?.getSelectedValues("nope") == null);

    const ping = "{\"id\":\"13\",\"application_id\":\"2\",\"type\":1,\"token\":\"t\"}";
    var parsed_ping = try schema.parse(schema.Interaction, std.testing.allocator, ping);
    defer parsed_ping.deinit();
    try std.testing.expect(parsed_ping.value.isPing());
}

test "interaction data with null fields parses safely" {
    const json =
        \\{
        \\  "id": "1",
        \\  "application_id": "2",
        \\  "type": 3,
        \\  "token": "t",
        \\  "data": {
        \\    "name": null,
        \\    "type": null,
        \\    "custom_id": "settings_btn:general",
        \\    "component_type": 2,
        \\    "values": null,
        \\    "options": null,
        \\    "components": null
        \\  },
        \\  "member": {
        \\    "user": {
        \\      "id": "123",
        \\      "username": "luas10c",
        \\      "discriminator": null
        \\    },
        \\    "guild_id": null,
        \\    "joined_at": null,
        \\    "roles": null
        \\  },
        \\  "message": {
        \\    "id": "999",
        \\    "channel_id": "888",
        \\    "author": null,
        \\    "content": null,
        \\    "embeds": null,
        \\    "attachments": null
        \\  }
        \\}
    ;
    var parsed = try schema.parse(schema.Interaction, std.testing.allocator, json);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.isComponent());
    try std.testing.expectEqualStrings("settings_btn:general", parsed.value.data.?.custom_id.?);
    try std.testing.expectEqualStrings("", parsed.value.data.?.name);
    try std.testing.expectEqual(@as(u8, 0), parsed.value.data.?.type);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.data.?.values.len);
    try std.testing.expectEqualStrings("0", parsed.value.member.?.user.?.discriminator);
    try std.testing.expectEqualStrings("", parsed.value.member.?.guild_id);
}

test "message component interaction parses with real discord payload" {
    const json =
        \\{
        \\  "app_permissions": "1071698660929",
        \\  "application_id": "123456789",
        \\  "authorizing_integration_owners": { "0": "1098316516774129684" },
        \\  "channel": { "id": "111", "type": 0 },
        \\  "channel_id": "111",
        \\  "context": 0,
        \\  "data": {
        \\    "component_type": 2,
        \\    "custom_id": "settings_btn:general"
        \\  },
        \\  "entitlement_sku_ids": [],
        \\  "entitlements": [],
        \\  "guild": { "id": "1098316516774129684" },
        \\  "guild_id": "1098316516774129684",
        \\  "guild_locale": "pt-BR",
        \\  "id": "999888777",
        \\  "locale": "pt-BR",
        \\  "member": {
        \\    "avatar": null,
        \\    "communication_disabled_until": null,
        \\    "deaf": false,
        \\    "flags": 0,
        \\    "joined_at": "2023-01-01T00:00:00.000000+00:00",
        \\    "mute": false,
        \\    "nick": null,
        \\    "pending": false,
        \\    "permissions": "8",
        \\    "premium_since": null,
        \\    "roles": [],
        \\    "unusual_dm_activity_until": null,
        \\    "user": {
        \\      "avatar": "abc",
        \\      "avatar_decoration_data": null,
        \\      "bot": false,
        \\      "clan": null,
        \\      "discriminator": "0",
        \\      "global_name": "Luciano",
        \\      "id": "333",
        \\      "public_flags": 0,
        \\      "username": "luas10c"
        \\    }
        \\  },
        \\  "message": {
        \\    "attachments": [],
        \\    "author": {
        \\      "avatar": "def",
        \\      "avatar_decoration_data": null,
        \\      "bot": true,
        \\      "clan": null,
        \\      "discriminator": "0000",
        \\      "global_name": null,
        \\      "id": "123456789",
        \\      "public_flags": 0,
        \\      "username": "BamBam"
        \\    },
        \\    "channel_id": "111",
        \\    "components": [
        \\      {
        \\        "type": 1,
        \\        "components": [
        \\          {
        \\            "type": 2,
        \\            "style": 2,
        \\            "label": "⚙️ Geral",
        \\            "custom_id": "settings_btn:general"
        \\          }
        \\        ]
        \\      }
        \\    ],
        \\    "content": "",
        \\    "edited_timestamp": null,
        \\    "embeds": [
        \\      {
        \\        "color": 5793266,
        \\        "description": "Visualize o status...",
        \\        "fields": [
        \\          {
        \\            "inline": false,
        \\            "name": "⚙️ Configurações Gerais",
        \\            "value": "• **Boas-Vindas:** <#123>\n• **Saída:** <#456>"
        \\          }
        \\        ],
        \\        "title": "⚙️ Painel de Configurações do Servidor",
        \\        "type": "rich"
        \\      }
        \\    ],
        \\    "flags": 64,
        \\    "id": "888777666",
        \\    "mention_everyone": false,
        \\    "mention_roles": [],
        \\    "mentions": [],
        \\    "pinned": false,
        \\    "timestamp": "2026-09-10T21:00:00.000000+00:00",
        \\    "tts": false,
        \\    "type": 0
        \\  },
        \\  "token": "aW50ZX...",
        \\  "type": 3,
        \\  "version": 1
        \\}
    ;
    var parsed = try schema.parse(schema.Interaction, std.testing.allocator, json);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.isComponent());
}

test "interaction handle followUp fetchReply delete autocomplete" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(6);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });

    var fu_msg = try handle.followUp(.{ .content = "hi", .embeds = &.{schema.Embed{ .title = "t" }} });
    defer fu_msg.deinit();
    try std.testing.expectEqualStrings("1", fu_msg.value.id);
    var fetched = try handle.fetchReply();
    defer fetched.deinit();
    try std.testing.expectEqualStrings("1", fetched.value.id);
    try handle.deleteReply();
    try handle.deleteFollowUp("M1");
    try handle.autocomplete(&.{.{ .name = "a", .value = .{ .string = "x" } }});
    var with_resp = try rest.respondInteractionWithResponse("INT", "TKN", "{\"type\":4,\"data\":{\"content\":\"hi\"}}");
    defer with_resp.deinit();
    try std.testing.expectEqualStrings("9", with_resp.value.resource.?.message.?.id);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 6), setup.ctx.count);

    const fu = &setup.ctx.reqs[0];
    try std.testing.expectEqualStrings("POST", fu.methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN", fu.pathStr());
    try std.testing.expectEqualStrings("{\"content\":\"hi\",\"embeds\":[{\"title\":\"t\"}]}", fu.bodyStr());

    const get = &setup.ctx.reqs[1];
    try std.testing.expectEqualStrings("GET", get.methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN/messages/@original", get.pathStr());

    const del = &setup.ctx.reqs[2];
    try std.testing.expectEqualStrings("DELETE", del.methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN/messages/@original", del.pathStr());

    const del_fu = &setup.ctx.reqs[3];
    try std.testing.expectEqualStrings("DELETE", del_fu.methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN/messages/M1", del_fu.pathStr());

    const ac = &setup.ctx.reqs[4];
    try std.testing.expectEqualStrings("POST", ac.methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback", ac.pathStr());
    try std.testing.expectEqualStrings("{\"type\":8,\"data\":{\"choices\":[{\"name\":\"a\",\"value\":\"x\"}]}}", ac.bodyStr());

    const wr = &setup.ctx.reqs[5];
    try std.testing.expectEqualStrings("POST", wr.methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback?with_response=true", wr.pathStr());
}

test "editReply with flags carries v2 flag" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(1);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });
    try handle.editReply(.{ .content = "v2", .flags = .{message.MessageFlags.IsComponentsV2} });

    setup.join();
    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("PATCH", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN/messages/@original", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("{\"content\":\"v2\",\"flags\":32768}", setup.ctx.reqs[0].bodyStr());
}

test "reply without content sends v2 components only" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(1);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });
    const row = schema.Component{ .type = 1, .components = &.{} };
    try handle.reply(.{ .flags = .{message.MessageFlags.IsComponentsV2}, .components = &.{row} });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"flags\":32768,\"components\":[{\"type\":1,\"components\":[]}]}}", setup.ctx.reqs[0].bodyStr());
}

test "reply with embeds and components" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(1);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });
    const embed = schema.Embed{
        .title = "Hello",
        .description = "World",
    };
    try handle.reply(.{ .embeds = &.{embed} });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"type\":4,\"data\":{\"embeds\":[{\"title\":\"Hello\",\"description\":\"World\"}]}}", setup.ctx.reqs[0].bodyStr());
}


test "followUp with poll and reply with files" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(2);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });
    const create = schema.PollCreate{
        .question = .{ .text = "Best?" },
        .answers = &.{.{ .poll_media = .{ .text = "A" } }},
    };
    var fu = try handle.followUp(.{ .content = "vote", .poll = create });
    defer fu.deinit();
    try std.testing.expectEqualStrings("1", fu.value.id);

    var ab = attachment.Builder.init(allocator);
    defer ab.deinit();
    try ab.setFilename("a.txt");
    try ab.setData("hi");
    const built = try ab.build();
    const files = [_]attachment.Attachment{built};
    try handle.reply(.{ .content = "files", .attachments = &files });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 2), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/webhooks/APP/TKN", setup.ctx.reqs[0].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"poll\"") != null);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[1].methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback", setup.ctx.reqs[1].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[1].bodyStr(), "filename=\"a.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[1].bodyStr(), "\"attachments\"") != null);
}

test "interaction handle reply with poll" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(1);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });
    const create = schema.PollCreate{
        .question = .{ .text = "Which language?" },
        .answers = &.{
            .{ .poll_media = .{ .text = "Zig" } },
            .{ .poll_media = .{ .text = "Other" } },
        },
        .duration = 48,
    };
    try handle.reply(.{ .content = "Vote now:", .poll = create });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/interactions/INT/TKN/callback", setup.ctx.reqs[0].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"type\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"poll\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"Which language?\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"duration\":48") != null);
}

test "update and deferUpdate send types 7 and 6" {
    const allocator = std.testing.allocator;
    const setup = try withInteractionMock(2);
    defer destroyInteractionMock(setup);

    var rest = client.Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var handle = slash.Interaction.init(&rest, .{
        .id = "INT",
        .application_id = "APP",
        .token = "TKN",
    });
    try handle.deferUpdate();
    try handle.update(.{ .content = "edited" });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 2), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"type\":6}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("{\"type\":7,\"data\":{\"content\":\"edited\"}}", setup.ctx.reqs[1].bodyStr());
}

test "parse real component interaction payload from discord" {
    const raw =
        \\{"version":1,"type":3,"token":"aW50ZXJhY3Rpb246MTU0Nzc3MzIwODY3NjAxNjI3ODowWm5Xd3FGWHpZaVRKNHZGcm50SVdQQ0hSMnk2U2lnaTEzSUo5SjhtbDMxQ2w0WEVTTGdxdWVua2pRM0NoVldsc2xLUmZYODNXTUxsd2RHajlvVTlZeTNuZng0dXlUVjNMU0RuSlZzOWVwRHBqVUZsbldiRzNPSFl0WTVyZXpyNA","message":{"webhook_id":"1291499059097374721","type":20,"tts":false,"timestamp":"2026-09-11T00:34:34.763000+00:00","pinned":false,"mentions":[],"mention_roles":[],"mention_everyone":false,"interaction_metadata":{"user":{"vad_colors":null,"username":"capitanlaw","public_flags":0,"primary_guild":null,"id":"310615264288964610","global_name":"Capitão Law","display_name_styles":null,"discriminator":"0","collectibles":{"nameplate":{"sku_id":"1465519580016410746","palette":"bubble_gum","label":"Swaying cherry blossom branch with petals blowing and gentle watercolor washes.","expires_at":null,"asset":"nameplates/blossoming_branch/1465519580016410746/"}},"clan":null,"avatar_decoration_data":{"sku_id":"1466990610429772003","expires_at":null,"asset":"a_205011b1e9e1b3538f8cc7c6ccba61b3"},"avatar":"bf33b3980bb5898a0857766c348aefe2"},"type":2,"name":"bambam settings","id":"1547767268283392041","command_type":1,"authorizing_integration_owners":{"0":"1098316516774129684"}},"interaction":{"user":{"vad_colors":null,"username":"capitanlaw","public_flags":0,"primary_guild":null,"id":"310615264288964610","global_name":"Capitão Law","display_name_styles":null,"discriminator":"0","collectibles":{"nameplate":{"sku_id":"1465519580016410746","palette":"bubble_gum","label":"Swaying cherry blossom branch with petals blowing and gentle watercolor washes.","expires_at":null,"asset":"nameplates/blossoming_branch/1465519580016410746/"}},"clan":null,"avatar_decoration_data":{"sku_id":"1466990610429772003","expires_at":null,"asset":"a_205011b1e9e1b3538f8cc7c6ccba61b3"},"avatar":"bf33b3980bb5898a0857766c348aefe2"},"type":2,"name":"bambam settings","id":"1547767268283392041"},"id":"1547767276164489218","flags":64,"embeds":[{"type":"rich","title":"⚙️ Painel de Configurações do Servidor","id":"1547767276164489217","fields":[{"value":"• **Boas-Vindas:** Não configurado\n• **Saída:** Não configurado","name":"⚙️ Configurações Gerais","inline":false},{"value":"• **Canal de Cargos:** Não configurado\n• **Autoroles:** 0 cargo(s)\n• **Cargos Autoatribuíveis:** 0 cargo(s)","name":"🎭 Cargos & Painel","inline":false},{"value":"• **Categorias Monitoradas:** 0 categoria(s) configurada(s)","name":"🔊 Salas de Voz Temporárias","inline":false}],"description":"Visualize o status das configurações do servidor e clique nos botões abaixo para editar cada seção.","content_scan_version":0,"color":5793266}],"edited_timestamp":null,"content":"","components":[{"type":1,"id":1,"components":[{"type":2,"style":2,"label":"⚙️ Geral","id":2,"custom_id":"settings_btn:general"},{"type":2,"style":2,"label":"🎭 Cargos","id":3,"custom_id":"settings_btn:roles"},{"type":2,"style":2,"label":"🔊 Salas de Voz","id":4,"custom_id":"settings_btn:voice"}]}],"channel_id":"1281291889538105477","author":{"vad_colors":null,"username":"Bambam","public_flags":0,"primary_guild":null,"id":"1291499059097374721","global_name":null,"display_name_styles":null,"discriminator":"1552","collectibles":null,"clan":null,"bot":true,"avatar_decoration_data":null,"avatar":"8ad4f44789f3f5b2c4127ca2266f9fc2"},"attachments":[],"application_id":"1291499059097374721"},"member":{"user":{"vad_colors":null,"username":"capitanlaw","public_flags":0,"primary_guild":null,"id":"310615264288964610","global_name":"Capitão Law","display_name_styles":null,"discriminator":"0","collectibles":{"nameplate":{"sku_id":"1465519580016410746","palette":"bubble_gum","label":"Swaying cherry blossom branch with petals blowing and gentle watercolor washes.","expires_at":null,"asset":"nameplates/blossoming_branch/1465519580016410746/"}},"clan":null,"avatar_decoration_data":{"sku_id":"1466990610429772003","expires_at":null,"asset":"a_205011b1e9e1b3538f8cc7c6ccba61b3"},"avatar":"bf33b3980bb5898a0857766c348aefe2"},"unusual_dm_activity_until":null,"roles":["1289376155790479471","1108091773613518898","1281421033433468948","1395031398385188984","1289305940901888093"],"premium_since":null,"permissions":"18014398509481983","pending":false,"nick":null,"mute":false,"joined_at":"2024-09-16T10:13:04.810000+00:00","flags":106,"deaf":false,"communication_disabled_until":null,"banner":null,"avatar":null},"locale":"pt-BR","id":"1547773208676016278","guild_locale":"pt-BR","guild_id":"1098316516774129684","guild":{"locale":"pt-BR","id":"1098316516774129684","features":["VIDEO_QUALITY_720_60FPS","GUESTS_ENABLED","ACTIVITY_FEED_DISABLED_BY_USER","MEMBER_VERIFICATION_MANUAL_APPROVAL","COMMUNITY","GUILD_SERVER_GUIDE","GUILD_WEB_PAGE_VANITY_URL","WELCOME_SCREEN_ENABLED","SOUNDBOARD","ENABLED_DISCOVERABLE_BEFORE","CHANNEL_ICON_EMOJIS_GENERATED","NEWS","INVITE_SPLASH","MEMBER_VERIFICATION_GATE_ENABLED","GUILD_ONBOARDING_HAS_PROMPTS","GUILD_ONBOARDING","AUDIO_BITRATE_128_KBPS","GUILD_ONBOARDING_EVER_ENABLED","ANIMATED_ICON","STAGE_CHANNEL_VIEWERS_50","VIDEO_BITRATE_ENHANCED","AUTO_MODERATION","TIERLESS_BOOSTING","AGE_VERIFICATION_LARGE_GUILD","PRUNE_REQUIRES_ADMIN"]},"entitlements":[],"entitlement_sku_ids":[],"data":{"id":2,"custom_id":"settings_btn:general","component_type":2},"context":0,"channel_id":"1281291889538105477","channel":{"type":0,"topic":null,"rate_limit_per_user":0,"position":5,"permissions":"18014398509481983","parent_id":"1291226772259471422","nsfw":false,"name":"⌈🔐⌋╸security","last_message_id":"1547378469036630017","id":"1281291889538105477","guild_id":"1098316516774129684","flags":0},"authorizing_integration_owners":{"0":"1098316516774129684"},"attachment_size_limit":20971520,"application_id":"1291499059097374721","app_permissions":"8886045607586513"}
    ;
    var parsed_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
    defer parsed_json.deinit();

    var parsed_inter = try std.json.parseFromValue(schema.Interaction, std.testing.allocator, parsed_json.value, .{ .ignore_unknown_fields = true });
    defer parsed_inter.deinit();

    try std.testing.expectEqualStrings("1547773208676016278", parsed_inter.value.id);
    try std.testing.expectEqual(@as(u8, 3), parsed_inter.value.type);
    const data = parsed_inter.value.data.?;
    try std.testing.expectEqualStrings("settings_btn:general", data.custom_id.?);
    try std.testing.expectEqual(@as(u8, 2), data.component_type.?);
}

