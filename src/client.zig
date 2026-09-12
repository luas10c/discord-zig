const std = @import("std");
const schema = @import("./schema.zig");
const util = @import("./util.zig");
const fetch_mod = @import("./fetch.zig");
const session = @import("./session.zig");
const gateway = @import("./gateway.zig");
const events = @import("./events.zig");
const websockets = @import("./websockets.zig");
const cache_mod = @import("./cache.zig");
const guild_mod = @import("./guild.zig");
const channel_mod = @import("./channel.zig");
const user_mod = @import("./user.zig");
const attachment_mod = @import("./attachment.zig");
const poll_mod = @import("./poll.zig");
const message_mod = @import("./message.zig");
const intents_mod = @import("./intents.zig");
const permission_mod = @import("./permission.zig");
const slash_mod = @import("./slash.zig");
const voice_mod = @import("./voice.zig");
const collector_mod = @import("./collector.zig");
const cdn_mod = @import("./cdn.zig");
const formatters_mod = @import("./formatters.zig");

pub const GatewayIntentBits = intents_mod.GatewayIntentBits;

pub const base_url: []const u8 = "https://discord.com/api/v10";
pub const user_agent: []const u8 = "DiscordBot (https://github.com/discord-zig, 0.0.0)";

pub const RateLimit = struct {
    limit: ?u64 = null,
    remaining: ?u64 = null,
    reset_after: ?f64 = null,
    bucket: ?[]const u8 = null,
    scope: ?[]const u8 = null,
    global: bool = false,
};

pub const Response = struct {
    status: std.http.Status,
    status_code: u16,
    rate_limit: RateLimit,
    retry_after: ?f64,
    body: []u8,
};

pub const ApiError = error{
    Unauthorized,
    Forbidden,
    NotFound,
    RateLimited,
    ServerError,
    UnexpectedStatus,
    InvalidResponseBody,
} || std.mem.Allocator.Error || std.http.Client.RequestError || std.http.Client.Request.ReceiveHeadError || std.Io.Writer.Error || std.Uri.ParseError;

pub const Rest = struct {
    pub const cdn = cdn_mod.CDN;
    pub const formatters = formatters_mod;

    pub const RouteBucket = struct {
        remaining: u64 = 1,
        reset_at_ms: i64 = 0,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    http: std.http.Client,
    token: []const u8,
    base_url: []const u8 = base_url,
    timeout_ns: ?u64 = default_timeout_ns,
    buckets: std.StringHashMapUnmanaged(RouteBucket) = .empty,
    last_request_ms: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, token: []const u8) Rest {
        return .{
            .allocator = allocator,
            .io = io,
            .http = .{ .allocator = allocator, .io = io },
            .token = token,
            .base_url = base_url,
            .timeout_ns = default_timeout_ns,
            .buckets = .empty,
            .last_request_ms = 0,
        };
    }

    pub fn deinit(self: *Rest) void {
        var it = self.buckets.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.buckets.deinit(self.allocator);
        self.http.deinit();
    }

    pub fn urlFor(self: Rest, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ self.base_url, path });
    }

    pub fn authHeader(self: Rest, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "Bot {s}", .{self.token});
    }

    pub const max_rate_limit_retries: u32 = 3;
    pub const max_retry_wait_ms: u64 = 30000;
    pub const default_timeout_ns: u64 = 15 * std.time.ns_per_s;
    pub const timeout_poll_ms: i64 = 1;
    pub const max_idle_pool_ms: i64 = 25000;

    pub fn request(
        self: *Rest,
        method: std.http.Method,
        path: []const u8,
        json_body: ?[]const u8,
    ) !Response {
        return self.requestFull(method, path, json_body, "application/json", null);
    }

    /// Cabeçalhos de rate-limit lidos numa única passada sobre `head_bytes`
    /// (evita 7 scans lineares por request). Os slices `bucket`/`scope`
    /// emprestam `head_bytes`, como antes.
    const ScannedRateLimit = struct {
        limit: ?u64 = null,
        remaining: ?u64 = null,
        reset_after: ?f64 = null,
        bucket: ?[]const u8 = null,
        scope: ?[]const u8 = null,
        global: bool = false,
        retry_after: ?f64 = null,
    };

    fn scanRateLimit(head_bytes: []const u8) ScannedRateLimit {
        var out: ScannedRateLimit = .{};
        var lines = std.mem.splitSequence(u8, head_bytes, "\r\n");
        _ = lines.first();
        while (lines.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(key, "x-ratelimit-limit")) {
                out.limit = std.fmt.parseInt(u64, value, 10) catch null;
            } else if (std.ascii.eqlIgnoreCase(key, "x-ratelimit-remaining")) {
                out.remaining = std.fmt.parseInt(u64, value, 10) catch null;
            } else if (std.ascii.eqlIgnoreCase(key, "x-ratelimit-reset-after")) {
                out.reset_after = std.fmt.parseFloat(f64, value) catch null;
            } else if (std.ascii.eqlIgnoreCase(key, "x-ratelimit-bucket")) {
                out.bucket = value;
            } else if (std.ascii.eqlIgnoreCase(key, "x-ratelimit-scope")) {
                out.scope = value;
            } else if (std.ascii.eqlIgnoreCase(key, "x-ratelimit-global")) {
                out.global = true;
            } else if (std.ascii.eqlIgnoreCase(key, "retry-after")) {
                out.retry_after = std.fmt.parseFloat(f64, value) catch null;
            }
        }
        return out;
    }

    /// Normaliza a chave de bucket colapsando segmentos numéricos inteiros
    /// (`/channels/123/messages` -> `/channels/:id/messages`). Sem isso, cada
    /// ID distinto (canal, guild, mensagem) cria uma entrada e o mapa cresce
    /// sem limite em bots grandes. Segmentos como `v10` são preservados.
    /// A saída normalizada nunca é maior que a entrada.
    fn normalizeRouteBucket(route: []const u8, buf: []u8) []const u8 {
        var o: usize = 0;
        var i: usize = 0;
        while (i < route.len) {
            const c = route[i];
            if (c >= '0' and c <= '9' and i > 0 and route[i - 1] == '/') {
                var j = i + 1;
                while (j < route.len and route[j] >= '0' and route[j] <= '9') : (j += 1) {}
                if (j == route.len or route[j] == '/') {
                    buf[o] = ':';
                    buf[o + 1] = 'i';
                    buf[o + 2] = 'd';
                    o += 3;
                    i = j;
                    continue;
                }
            }
            buf[o] = c;
            o += 1;
            i += 1;
        }
        return buf[0..o];
    }

    pub fn requestFull(
        self: *Rest,
        method: std.http.Method,
        path: []const u8,
        body: ?[]const u8,
        content_type: []const u8,
        audit_reason: ?[]const u8,
    ) !Response {
        // Caso comum cabe na pilha: evita 2 allocs (url + auth) por request.
        var url_stack: [1024]u8 = undefined;
        var url_heap: ?[]u8 = null;
        defer if (url_heap) |h| self.allocator.free(h);
        const url_text: []const u8 = std.fmt.bufPrint(&url_stack, "{s}{s}", .{ self.base_url, path }) catch blk: {
            const h = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
            url_heap = h;
            break :blk h;
        };
        var auth_stack: [256]u8 = undefined;
        var auth_heap: ?[]u8 = null;
        defer if (auth_heap) |h| self.allocator.free(h);
        const auth: []const u8 = std.fmt.bufPrint(&auth_stack, "Bot {s}", .{self.token}) catch blk: {
            const h = try std.fmt.allocPrint(self.allocator, "Bot {s}", .{self.token});
            auth_heap = h;
            break :blk h;
        };

        var headers = [_]std.http.Header{
            .{ .name = "Authorization", .value = auth },
            .{ .name = "User-Agent", .value = user_agent },
            .{ .name = "Accept", .value = "application/json" },
            .{ .name = "Content-Type", .value = content_type },
            .{ .name = "X-Audit-Log-Reason", .value = audit_reason orelse "" },
        };
        const header_count = if (audit_reason != null) headers.len else headers.len - 1;

        const query_start = std.mem.indexOfScalar(u8, path, '?') orelse path.len;
        const route = path[0..query_start];
        // Chave normalizada na pilha: lookup sem alocar; dupe só ao inserir.
        var norm_stack: [512]u8 = undefined;
        var norm_heap: ?[]u8 = null;
        defer if (norm_heap) |h| self.allocator.free(h);
        const bucket_route: []const u8 = if (route.len <= norm_stack.len)
            normalizeRouteBucket(route, &norm_stack)
        else blk: {
            const h = try self.allocator.alloc(u8, route.len);
            norm_heap = h;
            break :blk normalizeRouteBucket(route, h);
        };

        const pre_now = util.nowMs(self.io);
        if (self.buckets.get(bucket_route)) |b| {
            if (b.remaining == 0 and pre_now < b.reset_at_ms) {
                const sleep_ms = @as(u64, @intCast(b.reset_at_ms - pre_now));
                try self.io.sleep(.{ .nanoseconds = @as(i96, sleep_ms) * std.time.ns_per_ms }, .awake);
            }
        }

        var attempt: u32 = 0;
        while (true) {
            const now = util.nowMs(self.io);
            if (self.last_request_ms > 0 and now - self.last_request_ms > max_idle_pool_ms) {
                fetch_mod.pruneAllConnections(&self.http.connection_pool, self.io);
            }

            const raw_res = if (self.timeout_ns) |ns|
                self.fetchTimed(method, url_text, headers[0..header_count], body, ns)
            else
                fetch_mod.fetch(&self.http, self.allocator, method, url_text, headers[0..header_count], body);

            var raw = raw_res catch |err| {
                if (attempt == 0 and err != error.Timeout) {
                    // Stale pooled connection race condition: purge pool and retry once fresh
                    fetch_mod.pruneAllConnections(&self.http.connection_pool, self.io);
                    attempt += 1;
                    continue;
                }
                return err;
            };
            errdefer {
                self.allocator.free(raw.head_bytes);
                self.allocator.free(raw.body);
            }

            self.last_request_ms = util.nowMs(self.io);

            const scanned = scanRateLimit(raw.head_bytes);
            const rate_limit = RateLimit{
                .limit = scanned.limit,
                .remaining = scanned.remaining,
                .reset_after = scanned.reset_after,
                .bucket = scanned.bucket,
                .scope = scanned.scope,
                .global = scanned.global,
            };

            if (rate_limit.remaining) |rem| {
                const current_now = util.nowMs(self.io);
                const reset_ms: i64 = if (rate_limit.reset_after) |ra|
                    current_now + @as(i64, @intFromFloat(ra * 1000.0))
                else
                    current_now + 1000;

                if (self.buckets.getPtr(bucket_route)) |ptr| {
                    ptr.remaining = rem;
                    ptr.reset_at_ms = reset_ms;
                } else {
                    const route_dup = self.allocator.dupe(u8, bucket_route) catch null;
                    if (route_dup) |rd| {
                        self.buckets.put(self.allocator, rd, .{
                            .remaining = rem,
                            .reset_at_ms = reset_ms,
                        }) catch {
                            self.allocator.free(rd);
                        };
                    }
                }
            }

            var retry_after: ?f64 = scanned.retry_after;
            if (retry_after == null and raw.status == .too_many_requests) {
                const parsed = std.json.parseFromSlice(struct {
                    retry_after: f64 = 0,
                    global: bool = false,
                }, self.allocator, raw.body, .{ .ignore_unknown_fields = true }) catch null;
                if (parsed) |*p| {
                    var owned = p;
                    defer owned.deinit();
                    retry_after = owned.value.retry_after;
                }
            }

            if (raw.status == .too_many_requests and attempt < max_rate_limit_retries) {
                const wait_ms: u64 = @min(@as(u64, @intFromFloat((retry_after orelse 1.0) * 1000.0)), max_retry_wait_ms);
                self.allocator.free(raw.head_bytes);
                self.allocator.free(raw.body);
                attempt += 1;
                try self.io.sleep(.{ .nanoseconds = @as(i96, wait_ms) * std.time.ns_per_ms }, .awake);
                continue;
            }

            if (raw.status_code < 200 or raw.status_code >= 300) {
                std.log.warn("discord: {s} {s} -> {d}: {s}", .{
                    @tagName(method),
                    path,
                    raw.status_code,
                    raw.body[0..@min(raw.body.len, 200)],
                });
            }

            defer self.allocator.free(raw.head_bytes);
            return .{
                .status = raw.status,
                .status_code = raw.status_code,
                .rate_limit = rate_limit,
                .retry_after = retry_after,
                .body = raw.body,
            };
        }
    }

    const FetchJob = struct {
        http: *std.http.Client,
        allocator: std.mem.Allocator,
        method: std.http.Method,
        url: []const u8,
        headers: []const std.http.Header,
        body: ?[]const u8,
        done: std.atomic.Value(bool),
        result: ?anyerror!fetch_mod.Response,
    };

    const CertLoad = struct {
        cache: *websockets.CertCache,
        io: std.Io,
        result: ?anyerror!void = null,
    };

    fn certLoadTask(job: *CertLoad) void {
        job.result = job.cache.ensure(job.io);
    }

    fn fetchTask(job: *FetchJob) void {
        job.result = fetch_mod.fetch(job.http, job.allocator, job.method, job.url, job.headers, job.body);
        job.done.store(true, .release);
    }

    fn fetchTimed(
        self: *Rest,
        method: std.http.Method,
        url: []const u8,
        headers: []const std.http.Header,
        body: ?[]const u8,
        timeout_ns: u64,
    ) !fetch_mod.Response {
        var job = FetchJob{
            .http = &self.http,
            .allocator = self.allocator,
            .method = method,
            .url = url,
            .headers = headers,
            .body = body,
            .done = std.atomic.Value(bool).init(false),
            .result = null,
        };
        var group: std.Io.Group = .init;
        group.async(self.io, fetchTask, .{&job});
        const start_ms = util.nowMs(self.io);
        const timeout_ms: i64 = @intCast(timeout_ns / std.time.ns_per_ms);
        while (!job.done.load(.acquire)) {
            if (util.nowMs(self.io) - start_ms >= timeout_ms) {
                group.cancel(self.io);
                group.await(self.io) catch {};
                self.http.deinit();
                self.http = .{ .allocator = self.allocator, .io = self.io };
                return error.Timeout;
            }
            self.io.sleep(.{ .nanoseconds = @as(i96, timeout_poll_ms) * std.time.ns_per_ms }, .awake) catch {};
        }
        group.await(self.io) catch {};
        return job.result.?;
    }

    pub fn ensureSuccess(res: Response) ApiError!void {
        switch (res.status) {
            .ok, .created, .accepted, .no_content => return,
            .unauthorized => return error.Unauthorized,
            .forbidden => return error.Forbidden,
            .not_found => return error.NotFound,
            .too_many_requests => return error.RateLimited,
            .internal_server_error, .bad_gateway, .service_unavailable, .gateway_timeout => return error.ServerError,
            else => return error.UnexpectedStatus,
        }
    }

    pub fn getCurrentUser(self: *Rest) !std.json.Parsed(schema.User) {
        const res = try self.request(.GET, "/users/@me", null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.User, self.allocator, res.status_code, res.body);
    }

    pub fn fetchUser(self: *Rest, user_id: []const u8) !std.json.Parsed(schema.User) {
        const path = try std.fmt.allocPrint(self.allocator, "/users/{s}", .{user_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.User, self.allocator, res.status_code, res.body);
    }

    pub fn createDM(self: *Rest, user_id: []const u8) !std.json.Parsed(schema.Channel) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .recipient_id = user_id }, .{});
        defer self.allocator.free(body);
        const res = try self.request(.POST, "/users/@me/channels", body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn closeDM(self: *Rest, channel_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/users/@me/channels/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn createMessageWithAttachments(self: *Rest, channel_id: []const u8, content: []const u8, attachments: []const attachment_mod.Attachment) !std.json.Parsed(schema.Message) {
        var names: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (names.items) |n| self.allocator.free(n);
            names.deinit(self.allocator);
        }
        var parts: std.ArrayListUnmanaged(fetch_mod.MultipartFile) = .empty;
        defer parts.deinit(self.allocator);
        for (attachments, 0..) |a, i| {
            const name = try std.fmt.allocPrint(self.allocator, "files[{d}]", .{i});
            try names.append(self.allocator, name);
            try parts.append(self.allocator, a.toMultipart(name));
        }
        var payload_map: std.json.ObjectMap = .empty;
        defer {
            if (payload_map.get("attachments")) |v| {
                var arr = v.array;
                for (arr.items) |*m| {
                    var obj = m.object;
                    obj.deinit(self.allocator);
                }
                arr.deinit();
            }
            payload_map.deinit(self.allocator);
        }
        try payload_map.put(self.allocator, "content", .{ .string = content });
        try payload_map.put(self.allocator, "attachments", .{ .array = std.json.Array.init(self.allocator) });
        const attach_val = payload_map.getPtr("attachments").?;
        for (attachments, 0..) |a, i| {
            var map: std.json.ObjectMap = .empty;
            errdefer map.deinit(self.allocator);
            try map.put(self.allocator, "id", .{ .integer = @intCast(i) });
            try map.put(self.allocator, "filename", .{ .string = a.filename });
            if (a.description) |d| try map.put(self.allocator, "description", .{ .string = d });
            try attach_val.array.append(.{ .object = map });
        }
        const payload = try std.json.Stringify.valueAlloc(self.allocator, std.json.Value{ .object = payload_map }, .{});
        defer self.allocator.free(payload);
        var mp = try fetch_mod.multipart(self.allocator, payload, parts.items);
        defer mp.deinit(self.allocator);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, mp.body, mp.content_type, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn createMessageWithFiles(self: *Rest, channel_id: []const u8, content: []const u8, files: []const fetch_mod.MultipartFile) !std.json.Parsed(schema.Message) {
        const payload = try std.json.Stringify.valueAlloc(self.allocator, .{ .content = content }, .{});
        defer self.allocator.free(payload);
        var mp = try fetch_mod.multipart(self.allocator, payload, files);
        defer mp.deinit(self.allocator);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, mp.body, mp.content_type, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub const MessageReference = struct {
        message_id: []const u8,
        channel_id: ?[]const u8 = null,
        kind: u8 = 0,
        fail_if_not_exists: ?bool = null,
    };

    pub const MessageCreate = struct {
        content: ?[]const u8 = null,
        flags: u32 = 0,
        embeds: []const schema.Embed = &.{},
        components: []const schema.Component = &.{},
        stickers: []const []const u8 = &.{},
        reference: ?MessageReference = null,
        poll: ?schema.PollCreate = null,
    };

    pub fn messageCreateBody(allocator: std.mem.Allocator, opts: MessageCreate) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .emit_null_optional_fields = false } };
        try jw.beginObject();
        if (opts.content) |c| {
            try jw.objectField("content");
            try jw.write(c);
        }
        if (opts.flags != 0) {
            try jw.objectField("flags");
            try jw.write(opts.flags);
        }
        if (opts.embeds.len > 0) {
            try jw.objectField("embeds");
            try jw.write(opts.embeds);
        }
        if (opts.components.len > 0) {
            try jw.objectField("components");
            try jw.write(opts.components);
        }
        if (opts.stickers.len > 0) {
            try jw.objectField("sticker_ids");
            try jw.write(opts.stickers);
        }
        if (opts.reference) |r| {
            try jw.objectField("message_reference");
            try jw.beginObject();
            try jw.objectField("message_id");
            try jw.write(r.message_id);
            if (r.channel_id) |c| {
                try jw.objectField("channel_id");
                try jw.write(c);
            }
            if (r.kind != 0) {
                try jw.objectField("type");
                try jw.write(r.kind);
            }
            if (r.fail_if_not_exists) |f| {
                try jw.objectField("fail_if_not_exists");
                try jw.write(f);
            }
            try jw.endObject();
        }
        if (opts.poll) |p| {
            try jw.objectField("poll");
            try jw.write(p);
        }
        try jw.endObject();
        return out.toOwnedSlice();
    }

    pub fn createRichMessage(self: *Rest, channel_id: []const u8, opts: MessageCreate) !std.json.Parsed(schema.Message) {
        const body = try messageCreateBody(self.allocator, opts);
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn replyTo(self: *Rest, channel_id: []const u8, message_id: []const u8, content: []const u8) !std.json.Parsed(schema.Message) {
        return self.createRichMessage(channel_id, .{
            .content = content,
            .reference = .{ .message_id = message_id },
        });
    }

    pub fn forwardMessage(self: *Rest, target_channel_id: []const u8, src_channel_id: []const u8, message_id: []const u8) !std.json.Parsed(schema.Message) {
        return self.createRichMessage(target_channel_id, .{
            .reference = .{ .message_id = message_id, .channel_id = src_channel_id, .kind = 1 },
        });
    }

    pub fn setSuppressEmbeds(self: *Rest, channel_id: []const u8, message_id: []const u8, suppress: bool) !std.json.Parsed(schema.Message) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .flags = if (suppress) message_mod.suppress_embeds else @as(u32, 0) }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn createMessage(self: *Rest, channel_id: []const u8, content: []const u8) !std.json.Parsed(schema.Message) {        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .content = content }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn registerGlobalCommands(self: *Rest, application_id: []const u8, body: []const u8) !std.json.Parsed([]schema.ApplicationCommand) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/commands", .{application_id});
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.ApplicationCommand, self.allocator, res.status_code, res.body);
    }

    pub fn registerGuildCommands(self: *Rest, application_id: []const u8, guild_id: []const u8, body: []const u8) !std.json.Parsed([]schema.ApplicationCommand) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/guilds/{s}/commands", .{ application_id, guild_id });
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.ApplicationCommand, self.allocator, res.status_code, res.body);
    }

    pub fn listApplicationCommands(self: *Rest, application_id: []const u8) !std.json.Parsed([]schema.ApplicationCommand) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/commands", .{application_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.ApplicationCommand, self.allocator, res.status_code, res.body);
    }

    pub fn getApplicationCommand(self: *Rest, application_id: []const u8, command_id: []const u8) !std.json.Parsed(schema.ApplicationCommand) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/commands/{s}", .{ application_id, command_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.ApplicationCommand, self.allocator, res.status_code, res.body);
    }

    pub fn editApplicationCommand(self: *Rest, application_id: []const u8, command_id: []const u8, body: []const u8) !std.json.Parsed(schema.ApplicationCommand) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/commands/{s}", .{ application_id, command_id });
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.ApplicationCommand, self.allocator, res.status_code, res.body);
    }

    pub fn deleteApplicationCommand(self: *Rest, application_id: []const u8, command_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/commands/{s}", .{ application_id, command_id });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn fetchCommandPermissions(self: *Rest, application_id: []const u8, guild_id: []const u8) !std.json.Parsed([]schema.CommandPermissions) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/guilds/{s}/commands/permissions", .{ application_id, guild_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.CommandPermissions, self.allocator, res.status_code, res.body);
    }

    pub fn fetchSingleCommandPermissions(self: *Rest, application_id: []const u8, guild_id: []const u8, command_id: []const u8) !std.json.Parsed(schema.CommandPermissions) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/guilds/{s}/commands/{s}/permissions", .{ application_id, guild_id, command_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.CommandPermissions, self.allocator, res.status_code, res.body);
    }

    pub fn setCommandPermissions(self: *Rest, application_id: []const u8, guild_id: []const u8, command_id: []const u8, permissions: []const schema.CommandPermissionEntry) !std.json.Parsed(schema.CommandPermissions) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .permissions = permissions }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/guilds/{s}/commands/{s}/permissions", .{ application_id, guild_id, command_id });
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.CommandPermissions, self.allocator, res.status_code, res.body);
    }

    pub fn respondInteraction(self: *Rest, interaction_id: []const u8, token: []const u8, body: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/interactions/{s}/{s}/callback", .{ interaction_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    fn sendMultipart(self: *Rest, method: std.http.Method, path: []const u8, payload_json: []const u8, files: []fetch_mod.MultipartFile) !Response {
        var mp = try fetch_mod.multipart(self.allocator, payload_json, files);
        defer mp.deinit(self.allocator);
        return self.requestFull(method, path, mp.body, mp.content_type, null);
    }

    pub fn respondInteractionMultipart(self: *Rest, interaction_id: []const u8, token: []const u8, payload_json: []const u8, files: []fetch_mod.MultipartFile) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/interactions/{s}/{s}/callback", .{ interaction_id, token });
        defer self.allocator.free(path);
        const res = try self.sendMultipart(.POST, path, payload_json, files);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn editOriginalInteractionMultipart(self: *Rest, application_id: []const u8, token: []const u8, payload_json: []const u8, files: []fetch_mod.MultipartFile) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/@original", .{ application_id, token });
        defer self.allocator.free(path);
        const res = try self.sendMultipart(.PATCH, path, payload_json, files);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn followUpMultipart(self: *Rest, application_id: []const u8, token: []const u8, payload_json: []const u8, files: []fetch_mod.MultipartFile) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}", .{ application_id, token });
        defer self.allocator.free(path);
        const res = try self.sendMultipart(.POST, path, payload_json, files);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn editOriginalInteractionResponse(self: *Rest, application_id: []const u8, token: []const u8, body: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/@original", .{ application_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn respondInteractionWithResponse(self: *Rest, interaction_id: []const u8, token: []const u8, body: []const u8) !std.json.Parsed(schema.InteractionCallbackResponse) {
        const path = try std.fmt.allocPrint(self.allocator, "/interactions/{s}/{s}/callback?with_response=true", .{ interaction_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.InteractionCallbackResponse, self.allocator, res.status_code, res.body);
    }

    pub fn getOriginalInteractionResponse(self: *Rest, application_id: []const u8, token: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/@original", .{ application_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn followUp(self: *Rest, application_id: []const u8, token: []const u8, body: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}", .{ application_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn deleteInitialResponse(self: *Rest, application_id: []const u8, token: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/@original", .{ application_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn deleteFollowUp(self: *Rest, application_id: []const u8, token: []const u8, message_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/{s}", .{ application_id, token, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn createWebhook(self: *Rest, channel_id: []const u8, name: []const u8) !std.json.Parsed(schema.Webhook) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/webhooks", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Webhook, self.allocator, res.status_code, res.body);
    }

    pub fn fetchWebhook(self: *Rest, webhook_id: []const u8) !std.json.Parsed(schema.Webhook) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}", .{webhook_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Webhook, self.allocator, res.status_code, res.body);
    }

    pub fn fetchWebhookWithToken(self: *Rest, webhook_id: []const u8, token: []const u8) !std.json.Parsed(schema.Webhook) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}", .{ webhook_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Webhook, self.allocator, res.status_code, res.body);
    }

    pub fn editWebhook(self: *Rest, webhook_id: []const u8, name: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.Webhook) {
        const body = if (name) |n|
            try std.json.Stringify.valueAlloc(self.allocator, .{ .name = n }, .{})
        else
            try self.allocator.dupe(u8, "{}");
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}", .{webhook_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Webhook, self.allocator, res.status_code, res.body);
    }

    pub fn deleteWebhook(self: *Rest, webhook_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}", .{webhook_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn deleteWebhookWithToken(self: *Rest, webhook_id: []const u8, token: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}", .{ webhook_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn executeWebhook(self: *Rest, webhook_id: []const u8, token: []const u8, body: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}?wait=true", .{ webhook_id, token });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn getWebhookMessage(self: *Rest, webhook_id: []const u8, token: []const u8, message_id: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/{s}", .{ webhook_id, token, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn editWebhookMessage(self: *Rest, webhook_id: []const u8, token: []const u8, message_id: []const u8, body: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/{s}", .{ webhook_id, token, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn deleteWebhookMessage(self: *Rest, webhook_id: []const u8, token: []const u8, message_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/webhooks/{s}/{s}/messages/{s}", .{ webhook_id, token, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getMessage(self: *Rest, channel_id: []const u8, message_id: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn listMessages(self: *Rest, channel_id: []const u8, limit: u32) !std.json.Parsed([]schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages?limit={d}", .{ channel_id, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn editMessage(self: *Rest, channel_id: []const u8, message_id: []const u8, content: []const u8) !std.json.Parsed(schema.Message) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .content = content }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn deleteMessage(self: *Rest, channel_id: []const u8, message_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn deleteMessagesBulk(self: *Rest, channel_id: []const u8, message_ids: []const []const u8) !void {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .messages = message_ids }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/bulk-delete", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn react(self: *Rest, channel_id: []const u8, message_id: []const u8, emoji: []const u8) !void {
        const encoded = try util.encodeEmoji(self.allocator, emoji);
        defer self.allocator.free(encoded);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}/reactions/{s}/@me", .{ channel_id, message_id, encoded });
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn unreact(self: *Rest, channel_id: []const u8, message_id: []const u8, emoji: []const u8) !void {
        const encoded = try util.encodeEmoji(self.allocator, emoji);
        defer self.allocator.free(encoded);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}/reactions/{s}/@me", .{ channel_id, message_id, encoded });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn listReactionUsers(self: *Rest, channel_id: []const u8, message_id: []const u8, emoji: []const u8, limit: u32) !std.json.Parsed([]schema.User) {
        const encoded = try util.encodeEmoji(self.allocator, emoji);
        defer self.allocator.free(encoded);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}/reactions/{s}?limit={d}", .{ channel_id, message_id, encoded, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.User, self.allocator, res.status_code, res.body);
    }

    pub fn awaitUserReaction(self: *Rest, channel_id: []const u8, message_id: []const u8, emoji: []const u8, user_id: []const u8, timeout_ms: i64, poll_ms: i64) !bool {
        const start = util.nowMs(self.io);
        while (util.nowMs(self.io) - start < timeout_ms) {
            var users = try self.listReactionUsers(channel_id, message_id, emoji, 25);
            defer users.deinit();
            for (users.value) |u| {
                if (std.mem.eql(u8, u.id, user_id)) return true;
            }
            self.io.sleep(.{ .nanoseconds = @as(i96, poll_ms) * std.time.ns_per_ms }, .awake) catch {};
        }
        return false;
    }

    pub fn awaitMessage(self: *Rest, channel_id: []const u8, author_id: []const u8, after_id: []const u8, timeout_ms: i64, poll_ms: i64) !?std.json.Parsed(schema.Message) {
        const after = std.fmt.parseInt(u64, after_id, 10) catch 0;
        const start = util.nowMs(self.io);
        while (util.nowMs(self.io) - start < timeout_ms) {
            var list = try self.listMessages(channel_id, 10);
            defer list.deinit();
            var i = list.value.len;
            while (i > 0) {
                i -= 1;
                const m = list.value[i];
                const id = std.fmt.parseInt(u64, m.id, 10) catch continue;
                if (id > after and std.mem.eql(u8, m.author.id, author_id)) {
                    const msg = try self.getMessage(channel_id, m.id);
                    return msg;
                }
            }
            self.io.sleep(.{ .nanoseconds = @as(i96, poll_ms) * std.time.ns_per_ms }, .awake) catch {};
        }
        return null;
    }

    pub fn pinMessage(self: *Rest, channel_id: []const u8, message_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/pins/{s}", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PUT, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn unpinMessage(self: *Rest, channel_id: []const u8, message_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/pins/{s}", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn typing(self: *Rest, channel_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/typing", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn crosspost(self: *Rest, channel_id: []const u8, message_id: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}/crosspost", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn createPollMessage(self: *Rest, channel_id: []const u8, create: schema.PollCreate) !std.json.Parsed(schema.Message) {
        const body = try poll_mod.createBody(self.allocator, create);
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn endPoll(self: *Rest, channel_id: []const u8, message_id: []const u8) !std.json.Parsed(schema.Message) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/polls/{s}/expire", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Message, self.allocator, res.status_code, res.body);
    }

    pub fn fetchPollAnswerVoters(self: *Rest, channel_id: []const u8, message_id: []const u8, answer_id: u64, after: ?[]const u8, limit: u32) !std.json.Parsed(schema.PollAnswerVoters) {
        const path = if (after) |a|
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/polls/{s}/answers/{d}?after={s}&limit={d}", .{ channel_id, message_id, answer_id, a, limit })
        else
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/polls/{s}/answers/{d}?limit={d}", .{ channel_id, message_id, answer_id, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.PollAnswerVoters, self.allocator, res.status_code, res.body);
    }

    pub fn getChannel(self: *Rest, channel_id: []const u8) !std.json.Parsed(schema.Channel) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn createGuildChannel(self: *Rest, guild_id: []const u8, name: []const u8, kind: schema.ChannelType) !std.json.Parsed(schema.Channel) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name, .type = @intFromEnum(kind) }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/channels", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn editChannel(self: *Rest, channel_id: []const u8, name: ?[]const u8, topic: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        const body = if (name) |n|
            if (topic) |t|
                try std.json.Stringify.valueAlloc(self.allocator, .{ .name = n, .topic = t }, .{})
            else
                try std.json.Stringify.valueAlloc(self.allocator, .{ .name = n }, .{})
        else if (topic) |t|
            try std.json.Stringify.valueAlloc(self.allocator, .{ .topic = t }, .{})
        else
            try self.allocator.dupe(u8, "{}");
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn deleteChannel(self: *Rest, channel_id: []const u8, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    fn optStr(comptime O: type, options: O, comptime name: []const u8) ?[]const u8 {
        if (@hasField(O, name)) return @field(options, name);
        return null;
    }

    fn optU32(comptime O: type, options: O, comptime name: []const u8) ?u32 {
        if (@hasField(O, name)) return @field(options, name);
        return null;
    }

    fn optBool(comptime O: type, options: O, comptime name: []const u8) ?bool {
        if (@hasField(O, name)) return @field(options, name);
        return null;
    }

    pub fn isString(comptime T: type) bool {
        const info = @typeInfo(T);
        return switch (info) {
            .pointer => |p| switch (p.size) {
                .slice => p.child == u8,
                .one => switch (@typeInfo(p.child)) {
                    .array => |a| a.child == u8,
                    else => false,
                },
                else => false,
            },
            .array => |a| a.child == u8,
            else => false,
        };
    }

    pub fn parsePermissionValue(val: anytype) u64 {
        const T = @TypeOf(val);
        if (T == u64 or T == comptime_int) {
            return @as(u64, @intCast(val));
        }
        if (comptime isString(T)) {
            const str: []const u8 = if (@typeInfo(T) == .array) &val else val;
            return std.fmt.parseInt(u64, str, 10) catch 0;
        }
        const info = @typeInfo(T);
        switch (info) {
            .optional => {
                if (val) |unwrapped| {
                    return parsePermissionValue(unwrapped);
                } else {
                    return 0;
                }
            },
            .pointer => |p| switch (p.size) {
                .slice => {
                    var bits: u64 = 0;
                    for (val) |item| {
                        bits |= parsePermissionValue(item);
                    }
                    return bits;
                },
                .one => return parsePermissionValue(val.*),
                else => return 0,
            },
            .array => {
                var bits: u64 = 0;
                for (val) |item| {
                    bits |= parsePermissionValue(item);
                }
                return bits;
            },
            .@"struct" => {
                if (info.@"struct".is_tuple) {
                    var bits: u64 = 0;
                    inline for (std.meta.fields(T)) |field| {
                        bits |= parsePermissionValue(@field(val, field.name));
                    }
                    return bits;
                }
                return 0;
            },
            .@"enum" => {
                return @intFromEnum(val);
            },
            else => return 0,
        }
    }

    pub fn writeOverwriteItem(jw: anytype, item: anytype) !void {
        const IT = @TypeOf(item);
        try jw.beginObject();

        if (@hasField(IT, "id")) {
            const id_val = item.id;
            const IdT = @TypeOf(id_val);
            try jw.objectField("id");
            if (IdT == u64 or IdT == comptime_int) {
                var buf: [32]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{d}", .{id_val});
                try jw.write(str);
            } else if (comptime isString(IdT)) {
                const str: []const u8 = if (@typeInfo(IdT) == .array) &id_val else id_val;
                try jw.write(str);
            } else {
                try jw.write(id_val);
            }
        }

        const item_type: u8 = if (@hasField(IT, "kind")) blk: {
            const K = @TypeOf(item.kind);
            break :blk if (K == schema.OverwriteType) @intFromEnum(item.kind) else @as(u8, @intCast(item.kind));
        } else if (@hasField(IT, "type")) blk: {
            const TP = @TypeOf(item.@"type");
            break :blk if (TP == schema.OverwriteType) @intFromEnum(item.@"type") else @as(u8, @intCast(item.@"type"));
        } else 0;
        try jw.objectField("type");
        try jw.write(item_type);

        var allow_buf: [32]u8 = undefined;
        const allow_str: []const u8 = if (@hasField(IT, "allow")) blk: {
            const AT = @TypeOf(item.allow);
            if (comptime isString(AT)) {
                break :blk if (@typeInfo(AT) == .array) &item.allow else item.allow;
            }
            const bits = parsePermissionValue(item.allow);
            break :blk std.fmt.bufPrint(&allow_buf, "{d}", .{bits}) catch "0";
        } else "0";
        try jw.objectField("allow");
        try jw.write(allow_str);

        var deny_buf: [32]u8 = undefined;
        const deny_str: []const u8 = if (@hasField(IT, "deny")) blk: {
            const DT = @TypeOf(item.deny);
            if (comptime isString(DT)) {
                break :blk if (@typeInfo(DT) == .array) &item.deny else item.deny;
            }
            const bits = parsePermissionValue(item.deny);
            break :blk std.fmt.bufPrint(&deny_buf, "{d}", .{bits}) catch "0";
        } else "0";
        try jw.objectField("deny");
        try jw.write(deny_str);

        try jw.endObject();
    }

    pub fn writePermissionOverwrites(jw: anytype, overwrites: anytype) !void {
        try jw.beginArray();
        const OT = @TypeOf(overwrites);
        const info = @typeInfo(OT);
        switch (info) {
            .pointer => |p| switch (p.size) {
                .slice => {
                    for (overwrites) |item| {
                        try writeOverwriteItem(jw, item);
                    }
                },
                .one => {
                    const child_info = @typeInfo(p.child);
                    if (child_info == .array) {
                        for (overwrites.*) |item| {
                            try writeOverwriteItem(jw, item);
                        }
                    } else if (child_info == .@"struct" and child_info.@"struct".is_tuple) {
                        inline for (std.meta.fields(p.child)) |field| {
                            try writeOverwriteItem(jw, @field(overwrites.*, field.name));
                        }
                    } else {
                        try writeOverwriteItem(jw, overwrites.*);
                    }
                },
                else => {},
            },
            .array => {
                for (overwrites) |item| {
                    try writeOverwriteItem(jw, item);
                }
            },
            .@"struct" => {
                if (info.@"struct".is_tuple) {
                    inline for (std.meta.fields(OT)) |field| {
                        try writeOverwriteItem(jw, @field(overwrites, field.name));
                    }
                } else {
                    try writeOverwriteItem(jw, overwrites);
                }
            },
            else => {},
        }
        try jw.endArray();
    }

    pub fn parseChannelType(val: anytype) schema.ChannelType {
        const T = @TypeOf(val);
        if (T == schema.ChannelType) {
            return val;
        }
        const info = @typeInfo(T);
        if (info == .enum_literal) {
            const tag_name = @tagName(val);
            if (@hasDecl(schema.ChannelType, tag_name)) {
                return @field(schema.ChannelType, tag_name);
            }
            if (std.meta.stringToEnum(schema.ChannelType, tag_name)) |matched| {
                return matched;
            }
            return .GuildText;
        }
        if (info == .int or info == .comptime_int) {
            return @enumFromInt(@as(u8, @intCast(val)));
        }
        if (info == .@"enum") {
            return @enumFromInt(@intFromEnum(val));
        }
        return .GuildText;
    }

    pub fn createChannel(self: *Rest, guild_id: []const u8, options: anytype) !std.json.Parsed(schema.Channel) {
        const O = @TypeOf(options);
        const name = optStr(O, options, "name") orelse return error.InvalidChannelOptions;
        if (name.len == 0) return error.InvalidChannelOptions;
        const kind: schema.ChannelType = if (@hasField(O, "type"))
            parseChannelType(options.@"type")
        else if (@hasField(O, "kind"))
            parseChannelType(options.kind)
        else
            .GuildText;
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        try jw.objectField("name");
        try jw.write(name);
        try jw.objectField("type");
        try jw.write(@intFromEnum(kind));
        if (optStr(O, options, "topic")) |v| {
            try jw.objectField("topic");
            try jw.write(v);
        }
        if (optBool(O, options, "nsfw")) |v| {
            try jw.objectField("nsfw");
            try jw.write(v);
        }
        if (optStr(O, options, "parent_id") orelse optStr(O, options, "parentId") orelse optStr(O, options, "parent")) |v| {
            try jw.objectField("parent_id");
            try jw.write(v);
        }
        if (optU32(O, options, "user_limit") orelse optU32(O, options, "userLimit")) |v| {
            try jw.objectField("user_limit");
            try jw.write(v);
        }
        if (optU32(O, options, "bitrate")) |v| {
            try jw.objectField("bitrate");
            try jw.write(v);
        }
        if (optU32(O, options, "rate_limit_per_user") orelse optU32(O, options, "rateLimitPerUser")) |v| {
            try jw.objectField("rate_limit_per_user");
            try jw.write(v);
        }
        if (@hasField(O, "permission_overwrites")) {
            try jw.objectField("permission_overwrites");
            try writePermissionOverwrites(&jw, options.permission_overwrites);
        } else if (@hasField(O, "permissionOverwrites")) {
            try jw.objectField("permission_overwrites");
            try writePermissionOverwrites(&jw, options.permissionOverwrites);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/channels", .{guild_id});
        defer self.allocator.free(path);
        const audit_reason = optStr(O, options, "reason");
        const res = try self.requestFull(.POST, path, body, "application/json", audit_reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn editChannelFull(self: *Rest, channel_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        const O = @TypeOf(options);
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (optStr(O, options, "name")) |v| {
            try jw.objectField("name");
            try jw.write(v);
        }
        if (optStr(O, options, "topic")) |v| {
            try jw.objectField("topic");
            try jw.write(v);
        }
        if (optBool(O, options, "nsfw")) |v| {
            try jw.objectField("nsfw");
            try jw.write(v);
        }
        if (optStr(O, options, "parent_id") orelse optStr(O, options, "parentId") orelse optStr(O, options, "parent")) |v| {
            try jw.objectField("parent_id");
            try jw.write(v);
        }
        if (optU32(O, options, "user_limit") orelse optU32(O, options, "userLimit")) |v| {
            try jw.objectField("user_limit");
            try jw.write(v);
        }
        if (optU32(O, options, "bitrate")) |v| {
            try jw.objectField("bitrate");
            try jw.write(v);
        }
        if (optU32(O, options, "rate_limit_per_user") orelse optU32(O, options, "rateLimitPerUser")) |v| {
            try jw.objectField("rate_limit_per_user");
            try jw.write(v);
        }
        if (@hasField(O, "permission_overwrites")) {
            try jw.objectField("permission_overwrites");
            try writePermissionOverwrites(&jw, options.permission_overwrites);
        } else if (@hasField(O, "permissionOverwrites")) {
            try jw.objectField("permission_overwrites");
            try writePermissionOverwrites(&jw, options.permissionOverwrites);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}", .{channel_id});
        defer self.allocator.free(path);
        const audit_reason = reason orelse optStr(O, options, "reason");
        const res = try self.requestFull(.PATCH, path, body, "application/json", audit_reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn setChannelPermissions(self: *Rest, channel_id: []const u8, overwrites: anytype, reason: ?[]const u8) !std.json.Parsed(schema.Channel) {
        return self.editChannelFull(channel_id, .{ .permission_overwrites = overwrites }, reason);
    }

    pub fn listGuildChannels(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.Channel) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/channels", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn createInvite(self: *Rest, channel_id: []const u8, max_age: u32, max_uses: u32) !std.json.Parsed(schema.Invite) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .max_age = max_age, .max_uses = max_uses }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/invites", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Invite, self.allocator, res.status_code, res.body);
    }

    pub fn fetchInvites(self: *Rest, channel_id: []const u8) !std.json.Parsed([]schema.Invite) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/invites", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Invite, self.allocator, res.status_code, res.body);
    }

    pub fn fetchGuildInvites(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.Invite) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/invites", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Invite, self.allocator, res.status_code, res.body);
    }

    pub fn deleteInvite(self: *Rest, code: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/invites/{s}", .{code});
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn startThreadFromMessage(self: *Rest, channel_id: []const u8, message_id: []const u8, name: []const u8, auto_archive_minutes: u32) !std.json.Parsed(schema.Channel) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name, .auto_archive_duration = auto_archive_minutes }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/messages/{s}/threads", .{ channel_id, message_id });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn startThread(self: *Rest, channel_id: []const u8, name: []const u8, kind: schema.ChannelType, auto_archive_minutes: u32) !std.json.Parsed(schema.Channel) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name, .type = @intFromEnum(kind), .auto_archive_duration = auto_archive_minutes }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/threads", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn joinThread(self: *Rest, channel_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members/@me", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn leaveThread(self: *Rest, channel_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members/@me", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn addThreadMember(self: *Rest, channel_id: []const u8, user_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members/{s}", .{ channel_id, user_id });
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn removeThreadMember(self: *Rest, channel_id: []const u8, user_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members/{s}", .{ channel_id, user_id });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getThreadMember(self: *Rest, channel_id: []const u8, user_id: []const u8, with_member: bool) !std.json.Parsed(schema.ThreadMember) {
        const path = if (with_member)
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members/{s}?with_member=true", .{ channel_id, user_id })
        else
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members/{s}", .{ channel_id, user_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.ThreadMember, self.allocator, res.status_code, res.body);
    }

    pub fn listThreadMembers(self: *Rest, channel_id: []const u8, limit: u32, with_member: bool) !std.json.Parsed([]schema.ThreadMember) {
        const path = if (limit > 0)
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members?limit={d}&with_member={}", .{ channel_id, limit, with_member })
        else
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/thread-members", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.ThreadMember, self.allocator, res.status_code, res.body);
    }

    pub fn setThreadArchived(self: *Rest, channel_id: []const u8, archived: bool) !std.json.Parsed(schema.Channel) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .archived = archived }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Channel, self.allocator, res.status_code, res.body);
    }

    pub fn fetchActiveThreads(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.ThreadListActive) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/threads/active", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.ThreadListActive, self.allocator, res.status_code, res.body);
    }

    pub fn getGuild(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.Guild) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Guild, self.allocator, res.status_code, res.body);
    }

    pub fn listGuilds(self: *Rest, limit: u32) !std.json.Parsed([]schema.Guild) {
        const path = try std.fmt.allocPrint(self.allocator, "/users/@me/guilds?limit={d}", .{limit});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Guild, self.allocator, res.status_code, res.body);
    }

    pub fn leaveGuild(self: *Rest, guild_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/users/@me/guilds/{s}", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn fetchAuditLog(self: *Rest, guild_id: []const u8, limit: u32, action_type: ?u64, user_id: ?[]const u8) !std.json.Parsed(schema.AuditLog) {
        var path_buf: [256]u8 = undefined;
        var w: std.Io.Writer = .fixed(&path_buf);
        try w.print("/guilds/{s}/audit-logs?limit={d}", .{ guild_id, limit });
        if (action_type) |a| try w.print("&action_type={d}", .{a});
        if (user_id) |u| try w.print("&user_id={s}", .{u});
        const path = w.buffered();
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.AuditLog, self.allocator, res.status_code, res.body);
    }

    pub fn getOnboarding(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.Onboarding) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/onboarding", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Onboarding, self.allocator, res.status_code, res.body);
    }

    pub fn editOnboarding(self: *Rest, guild_id: []const u8, enabled: ?bool, default_channel_ids: ?[]const []const u8) !std.json.Parsed(schema.Onboarding) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (enabled) |e| {
            try jw.objectField("enabled");
            try jw.write(e);
        }
        if (default_channel_ids) |ids| {
            try jw.objectField("default_channel_ids");
            try jw.write(ids);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/onboarding", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.PUT, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Onboarding, self.allocator, res.status_code, res.body);
    }

    pub fn fetchTemplates(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.Template) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/templates", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Template, self.allocator, res.status_code, res.body);
    }

    pub fn createTemplate(self: *Rest, guild_id: []const u8, name: []const u8, description: ?[]const u8) !std.json.Parsed(schema.Template) {
        const body = if (description) |d|
            try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name, .description = d }, .{})
        else
            try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/templates", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Template, self.allocator, res.status_code, res.body);
    }

    pub fn editGuild(self: *Rest, guild_id: []const u8, options: anytype) !std.json.Parsed(schema.Guild) {
        const O = @TypeOf(options);
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (optStr(O, options, "name")) |v| {
            try jw.objectField("name");
            try jw.write(v);
        }
        if (optStr(O, options, "description")) |v| {
            try jw.objectField("description");
            try jw.write(v);
        }
        if (optStr(O, options, "icon")) |v| {
            try jw.objectField("icon");
            try jw.write(v);
        }
        if (optStr(O, options, "banner")) |v| {
            try jw.objectField("banner");
            try jw.write(v);
        }
        if (optStr(O, options, "splash")) |v| {
            try jw.objectField("splash");
            try jw.write(v);
        }
        if (optU32(O, options, "verification_level")) |v| {
            try jw.objectField("verification_level");
            try jw.write(v);
        }
        if (optStr(O, options, "afk_channel_id")) |v| {
            try jw.objectField("afk_channel_id");
            try jw.write(v);
        }
        if (optU32(O, options, "afk_timeout")) |v| {
            try jw.objectField("afk_timeout");
            try jw.write(v);
        }
        if (optStr(O, options, "owner_id")) |v| {
            try jw.objectField("owner_id");
            try jw.write(v);
        }
        if (optStr(O, options, "preferred_locale")) |v| {
            try jw.objectField("preferred_locale");
            try jw.write(v);
        }
        if (optStr(O, options, "system_channel_id")) |v| {
            try jw.objectField("system_channel_id");
            try jw.write(v);
        }
        if (optStr(O, options, "rules_channel_id")) |v| {
            try jw.objectField("rules_channel_id");
            try jw.write(v);
        }
        if (optStr(O, options, "public_updates_channel_id")) |v| {
            try jw.objectField("public_updates_channel_id");
            try jw.write(v);
        }
        if (optU32(O, options, "explicit_content_filter")) |v| {
            try jw.objectField("explicit_content_filter");
            try jw.write(v);
        }
        if (optU32(O, options, "default_message_notifications")) |v| {
            try jw.objectField("default_message_notifications");
            try jw.write(v);
        }
        if (optBool(O, options, "premium_progress_bar_enabled")) |v| {
            try jw.objectField("premium_progress_bar_enabled");
            try jw.write(v);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const reason: ?[]const u8 = if (@hasField(O, "reason")) options.reason else null;
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Guild, self.allocator, res.status_code, res.body);
    }

    pub fn getMember(self: *Rest, guild_id: []const u8, user_id: []const u8) !std.json.Parsed(schema.GuildMember) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn listMembers(self: *Rest, guild_id: []const u8, limit: u32, after: ?[]const u8) !std.json.Parsed([]schema.GuildMember) {
        const path = if (after) |a|
            try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members?limit={d}&after={s}", .{ guild_id, limit, a })
        else
            try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members?limit={d}", .{ guild_id, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn editMemberNick(self: *Rest, guild_id: []const u8, user_id: []const u8, nick: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = if (nick) |n|
            try std.json.Stringify.valueAlloc(self.allocator, .{ .nick = n }, .{})
        else
            try std.json.Stringify.valueAlloc(self.allocator, .{ .nick = @as(?[]const u8, null) }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn editMemberRoles(self: *Rest, guild_id: []const u8, user_id: []const u8, roles: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .roles = roles }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn timeoutMember(self: *Rest, guild_id: []const u8, user_id: []const u8, disabled_until: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .communication_disabled_until = disabled_until }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn timeoutMemberDuration(self: *Rest, guild_id: []const u8, user_id: []const u8, duration_seconds: u32, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        var buf: [32]u8 = undefined;
        const real_now = util.realNowSec(self.io);
        const iso = formatters.formatIso8601(real_now + duration_seconds, &buf);
        return self.timeoutMember(guild_id, user_id, iso, reason);
    }


    pub fn setMemberMute(self: *Rest, guild_id: []const u8, user_id: []const u8, mute: bool, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .mute = mute }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn setMemberDeaf(self: *Rest, guild_id: []const u8, user_id: []const u8, deaf: bool, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .deaf = deaf }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn moveMember(self: *Rest, guild_id: []const u8, user_id: []const u8, channel_id: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .channel_id = channel_id }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn disconnectMember(self: *Rest, guild_id: []const u8, user_id: []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        return self.moveMember(guild_id, user_id, null, reason);
    }

    pub fn addRole(self: *Rest, guild_id: []const u8, user_id: []const u8, role_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}/roles/{s}", .{ guild_id, user_id, role_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PUT, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn removeRole(self: *Rest, guild_id: []const u8, user_id: []const u8, role_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}/roles/{s}", .{ guild_id, user_id, role_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn kick(self: *Rest, guild_id: []const u8, user_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn ban(self: *Rest, guild_id: []const u8, user_id: []const u8, delete_message_seconds: u32, reason: ?[]const u8) !void {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .delete_message_seconds = delete_message_seconds }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/bans/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PUT, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn unban(self: *Rest, guild_id: []const u8, user_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/bans/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getBan(self: *Rest, guild_id: []const u8, user_id: []const u8) !std.json.Parsed(schema.BanEntry) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/bans/{s}", .{ guild_id, user_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.BanEntry, self.allocator, res.status_code, res.body);
    }

    pub fn listRoles(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.Role) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/roles", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Role, self.allocator, res.status_code, res.body);
    }

    pub fn createRole(self: *Rest, guild_id: []const u8, name: []const u8, reason: ?[]const u8) !std.json.Parsed(schema.Role) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .name = name }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/roles", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Role, self.allocator, res.status_code, res.body);
    }

    pub fn editRole(self: *Rest, guild_id: []const u8, role_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.Role) {
        const O = @TypeOf(options);
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (optStr(O, options, "name")) |v| {
            try jw.objectField("name");
            try jw.write(v);
        }
        if (optU32(O, options, "color")) |v| {
            try jw.objectField("color");
            try jw.write(v);
        }
        if (@hasField(O, "permissions")) {
            const text = try std.fmt.allocPrint(self.allocator, "{d}", .{options.permissions});
            defer self.allocator.free(text);
            try jw.objectField("permissions");
            try jw.write(text);
        }
        if (optBool(O, options, "hoist")) |v| {
            try jw.objectField("hoist");
            try jw.write(v);
        }
        if (optBool(O, options, "mentionable")) |v| {
            try jw.objectField("mentionable");
            try jw.write(v);
        }
        if (optStr(O, options, "icon")) |v| {
            try jw.objectField("icon");
            try jw.write(v);
        }
        if (optStr(O, options, "unicode_emoji")) |v| {
            try jw.objectField("unicode_emoji");
            try jw.write(v);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/roles/{s}", .{ guild_id, role_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Role, self.allocator, res.status_code, res.body);
    }

    pub const RolePosition = struct {
        id: []const u8,
        position: i32,
    };

    pub fn setRolePositions(self: *Rest, guild_id: []const u8, positions: []const RolePosition) !std.json.Parsed([]schema.Role) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginArray();
        for (positions) |p| {
            try jw.beginObject();
            try jw.objectField("id");
            try jw.write(p.id);
            try jw.objectField("position");
            try jw.write(p.position);
            try jw.endObject();
        }
        try jw.endArray();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/roles", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Role, self.allocator, res.status_code, res.body);
    }

    pub fn deleteRole(self: *Rest, guild_id: []const u8, role_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/roles/{s}", .{ guild_id, role_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn listGuildSounds(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.SoundboardList) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/soundboard-sounds", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.SoundboardList, self.allocator, res.status_code, res.body);
    }

    pub fn createSoundboardSound(self: *Rest, guild_id: []const u8, name: []const u8, file: fetch_mod.MultipartFile, volume: ?f64, reason: ?[]const u8) !std.json.Parsed(schema.SoundboardSound) {
        var payload_map: std.json.ObjectMap = .empty;
        defer payload_map.deinit(self.allocator);
        try payload_map.put(self.allocator, "name", .{ .string = name });
        if (volume) |v| try payload_map.put(self.allocator, "volume", .{ .float = v });
        const payload = try std.json.Stringify.valueAlloc(self.allocator, std.json.Value{ .object = payload_map }, .{});
        defer self.allocator.free(payload);
        var mp = try fetch_mod.multipart(self.allocator, payload, &.{file});
        defer mp.deinit(self.allocator);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/soundboard-sounds", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, mp.body, mp.content_type, reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.SoundboardSound, self.allocator, res.status_code, res.body);
    }

    pub fn deleteSoundboardSound(self: *Rest, guild_id: []const u8, sound_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/soundboard-sounds/{s}", .{ guild_id, sound_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn sendSoundboardSound(self: *Rest, channel_id: []const u8, sound_id: []const u8, source_guild_id: ?[]const u8) !void {
        const body = if (source_guild_id) |g|
            try std.json.Stringify.valueAlloc(self.allocator, .{ .sound_id = sound_id, .source_guild_id = g }, .{})
        else
            try std.json.Stringify.valueAlloc(self.allocator, .{ .sound_id = sound_id }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/send-soundboard-sound", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn editChannelPermissions(self: *Rest, channel_id: []const u8, overwrite_id: []const u8, kind: schema.OverwriteType, allow: u64, deny: u64, reason: ?[]const u8) !void {
        const allow_str = try std.fmt.allocPrint(self.allocator, "{d}", .{allow});
        defer self.allocator.free(allow_str);
        const deny_str = try std.fmt.allocPrint(self.allocator, "{d}", .{deny});
        defer self.allocator.free(deny_str);
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .allow = allow_str, .deny = deny_str, .type = @intFromEnum(kind) }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/permissions/{s}", .{ channel_id, overwrite_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PUT, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn deleteChannelPermissions(self: *Rest, channel_id: []const u8, overwrite_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/permissions/{s}", .{ channel_id, overwrite_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getCurrentApplication(self: *Rest) !std.json.Parsed(schema.Application) {
        const res = try self.request(.GET, "/oauth2/applications/@me", null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Application, self.allocator, res.status_code, res.body);
    }

    pub fn listEntitlements(self: *Rest, application_id: []const u8, limit: u32) !std.json.Parsed([]schema.Entitlement) {
        const path = if (limit > 0)
            try std.fmt.allocPrint(self.allocator, "/applications/{s}/entitlements?limit={d}", .{ application_id, limit })
        else
            try std.fmt.allocPrint(self.allocator, "/applications/{s}/entitlements", .{application_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Entitlement, self.allocator, res.status_code, res.body);
    }

    pub fn consumeEntitlement(self: *Rest, application_id: []const u8, entitlement_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/entitlements/{s}/consume", .{ application_id, entitlement_id });
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn createTestEntitlement(self: *Rest, application_id: []const u8, sku_id: []const u8, owner_id: []const u8, owner_type: u8) !std.json.Parsed(schema.Entitlement) {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/entitlements", .{application_id});
        defer self.allocator.free(path);
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{
            .sku_id = sku_id,
            .owner_id = owner_id,
            .owner_type = owner_type,
        }, .{});
        defer self.allocator.free(body);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Entitlement, self.allocator, res.status_code, res.body);
    }

    pub fn deleteTestEntitlement(self: *Rest, application_id: []const u8, entitlement_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/applications/{s}/entitlements/{s}", .{ application_id, entitlement_id });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getGuildEmoji(self: *Rest, guild_id: []const u8, emoji_id: []const u8) !std.json.Parsed(schema.GuildEmoji) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/emojis/{s}", .{ guild_id, emoji_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildEmoji, self.allocator, res.status_code, res.body);
    }

    pub fn listGuildEmojis(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.GuildEmoji) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/emojis", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.GuildEmoji, self.allocator, res.status_code, res.body);
    }

    pub fn createGuildEmoji(self: *Rest, guild_id: []const u8, name: []const u8, image: []const u8, roles: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildEmoji) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{
            .name = name,
            .image = image,
            .roles = roles,
        }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/emojis", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildEmoji, self.allocator, res.status_code, res.body);
    }

    pub fn editGuildEmoji(self: *Rest, guild_id: []const u8, emoji_id: []const u8, name: ?[]const u8, roles: ?[]const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildEmoji) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (name) |n| {
            try jw.objectField("name");
            try jw.write(n);
        }
        if (roles) |r| {
            try jw.objectField("roles");
            try jw.write(r);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/emojis/{s}", .{ guild_id, emoji_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildEmoji, self.allocator, res.status_code, res.body);
    }

    pub fn deleteGuildEmoji(self: *Rest, guild_id: []const u8, emoji_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/emojis/{s}", .{ guild_id, emoji_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getGuildSticker(self: *Rest, guild_id: []const u8, sticker_id: []const u8) !std.json.Parsed(schema.GuildSticker) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/stickers/{s}", .{ guild_id, sticker_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildSticker, self.allocator, res.status_code, res.body);
    }

    pub fn listGuildStickers(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.GuildSticker) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/stickers", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.GuildSticker, self.allocator, res.status_code, res.body);
    }

    pub fn deleteGuildSticker(self: *Rest, guild_id: []const u8, sticker_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/stickers/{s}", .{ guild_id, sticker_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn createGuildSticker(self: *Rest, guild_id: []const u8, name: []const u8, tags: []const u8, description: []const u8, file: fetch_mod.MultipartFile, reason: ?[]const u8) !std.json.Parsed(schema.GuildSticker) {
        var payload_map: std.json.ObjectMap = .empty;
        defer payload_map.deinit(self.allocator);
        try payload_map.put(self.allocator, "name", .{ .string = name });
        try payload_map.put(self.allocator, "tags", .{ .string = tags });
        try payload_map.put(self.allocator, "description", .{ .string = description });
        const payload = try std.json.Stringify.valueAlloc(self.allocator, std.json.Value{ .object = payload_map }, .{});
        defer self.allocator.free(payload);
        var mp = try fetch_mod.multipart(self.allocator, payload, &.{file});
        defer mp.deinit(self.allocator);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/stickers", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, mp.body, mp.content_type, reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildSticker, self.allocator, res.status_code, res.body);
    }

    pub fn editGuildSticker(self: *Rest, guild_id: []const u8, sticker_id: []const u8, name: ?[]const u8, tags: ?[]const u8, description: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildSticker) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (name) |n| {
            try jw.objectField("name");
            try jw.write(n);
        }
        if (tags) |t| {
            try jw.objectField("tags");
            try jw.write(t);
        }
        if (description) |d| {
            try jw.objectField("description");
            try jw.write(d);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/stickers/{s}", .{ guild_id, sticker_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildSticker, self.allocator, res.status_code, res.body);
    }

    pub fn getScheduledEvent(self: *Rest, guild_id: []const u8, event_id: []const u8) !std.json.Parsed(schema.GuildScheduledEvent) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events/{s}", .{ guild_id, event_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildScheduledEvent, self.allocator, res.status_code, res.body);
    }

    pub fn listScheduledEvents(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.GuildScheduledEvent) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.GuildScheduledEvent, self.allocator, res.status_code, res.body);
    }

    pub fn createScheduledEvent(self: *Rest, guild_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.GuildScheduledEvent) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, options, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildScheduledEvent, self.allocator, res.status_code, res.body);
    }

    pub fn editScheduledEvent(self: *Rest, guild_id: []const u8, event_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.GuildScheduledEvent) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, options, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events/{s}", .{ guild_id, event_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildScheduledEvent, self.allocator, res.status_code, res.body);
    }

    pub fn deleteScheduledEvent(self: *Rest, guild_id: []const u8, event_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events/{s}", .{ guild_id, event_id });
        defer self.allocator.free(path);
        const res = try self.request(.DELETE, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getScheduledEventUsers(
        self: *Rest,
        guild_id: []const u8,
        event_id: []const u8,
        limit: u32,
        with_member: bool,
    ) !std.json.Parsed([]schema.GuildScheduledEventUser) {
        const path = if (limit > 0)
            try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events/{s}/users?limit={d}&with_member={}", .{ guild_id, event_id, limit, with_member })
        else
            try std.fmt.allocPrint(self.allocator, "/guilds/{s}/scheduled-events/{s}/users", .{ guild_id, event_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.GuildScheduledEventUser, self.allocator, res.status_code, res.body);
    }

    pub fn getAutoModerationRule(self: *Rest, guild_id: []const u8, rule_id: []const u8) !std.json.Parsed(schema.AutoModerationRule) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/auto-moderation/rules/{s}", .{ guild_id, rule_id });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.AutoModerationRule, self.allocator, res.status_code, res.body);
    }

    pub fn listAutoModerationRules(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.AutoModerationRule) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/auto-moderation/rules", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.AutoModerationRule, self.allocator, res.status_code, res.body);
    }

    pub fn createAutoModerationRule(self: *Rest, guild_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.AutoModerationRule) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, options, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/auto-moderation/rules", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.AutoModerationRule, self.allocator, res.status_code, res.body);
    }

    pub fn editAutoModerationRule(self: *Rest, guild_id: []const u8, rule_id: []const u8, options: anytype, reason: ?[]const u8) !std.json.Parsed(schema.AutoModerationRule) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, options, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/auto-moderation/rules/{s}", .{ guild_id, rule_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.AutoModerationRule, self.allocator, res.status_code, res.body);
    }

    pub fn deleteAutoModerationRule(self: *Rest, guild_id: []const u8, rule_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/auto-moderation/rules/{s}", .{ guild_id, rule_id });
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn fetchArchivedPublicThreads(self: *Rest, channel_id: []const u8, before: ?[]const u8, limit: u32) !std.json.Parsed(schema.ThreadListActive) {
        const path = if (before) |b|
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/threads/archived/public?before={s}&limit={d}", .{ channel_id, b, limit })
        else
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/threads/archived/public?limit={d}", .{ channel_id, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.ThreadListActive, self.allocator, res.status_code, res.body);
    }

    pub fn fetchArchivedPrivateThreads(self: *Rest, channel_id: []const u8, before: ?[]const u8, limit: u32) !std.json.Parsed(schema.ThreadListActive) {
        const path = if (before) |b|
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/threads/archived/private?before={s}&limit={d}", .{ channel_id, b, limit })
        else
            try std.fmt.allocPrint(self.allocator, "/channels/{s}/threads/archived/private?limit={d}", .{ channel_id, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.ThreadListActive, self.allocator, res.status_code, res.body);
    }

    pub fn fetchWelcomeScreen(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.WelcomeScreen) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/welcome-screen", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.WelcomeScreen, self.allocator, res.status_code, res.body);
    }

    pub fn editWelcomeScreen(self: *Rest, guild_id: []const u8, enabled: ?bool, description: ?[]const u8) !std.json.Parsed(schema.WelcomeScreen) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (enabled) |e| {
            try jw.objectField("enabled");
            try jw.write(e);
        }
        if (description) |d| {
            try jw.objectField("description");
            try jw.write(d);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/welcome-screen", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.WelcomeScreen, self.allocator, res.status_code, res.body);
    }

    pub fn fetchWidget(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.Widget) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/widget.json", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.Widget, self.allocator, res.status_code, res.body);
    }

    pub fn fetchWidgetSettings(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.WidgetSettings) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/widget", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.WidgetSettings, self.allocator, res.status_code, res.body);
    }

    pub fn editWidgetSettings(self: *Rest, guild_id: []const u8, enabled: ?bool, channel_id: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.WidgetSettings) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (enabled) |e| {
            try jw.objectField("enabled");
            try jw.write(e);
        }
        if (channel_id) |c| {
            try jw.objectField("channel_id");
            try jw.write(c);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/widget", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.WidgetSettings, self.allocator, res.status_code, res.body);
    }

    pub fn fetchVanityUrl(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.VanityUrl) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/vanity-url", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.VanityUrl, self.allocator, res.status_code, res.body);
    }

    pub fn getPruneCount(self: *Rest, guild_id: []const u8, days: u32, roles: []const []const u8) !std.json.Parsed(schema.PruneResult) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        try out.writer.print("/guilds/{s}/prune?days={d}", .{ guild_id, days });
        for (roles) |r| try out.writer.print("&include_roles={s}", .{r});
        const path = try out.toOwnedSlice();
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.PruneResult, self.allocator, res.status_code, res.body);
    }

    pub fn beginPrune(self: *Rest, guild_id: []const u8, days: u32, roles: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.PruneResult) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        try jw.objectField("days");
        try jw.write(days);
        if (roles.len > 0) {
            try jw.objectField("include_roles");
            try jw.write(roles);
        }
        if (reason) |r| {
            try jw.objectField("reason");
            try jw.write(r);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/prune", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.POST, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.PruneResult, self.allocator, res.status_code, res.body);
    }

    pub fn searchMembers(self: *Rest, guild_id: []const u8, query: []const u8, limit: u32) !std.json.Parsed([]schema.GuildMember) {
        const encoded = try util.encodeEmoji(self.allocator, query);
        defer self.allocator.free(encoded);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/members/search?query={s}&limit={d}", .{ guild_id, encoded, limit });
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn bulkBan(self: *Rest, guild_id: []const u8, user_ids: []const []const u8, delete_message_seconds: u32, reason: ?[]const u8) !std.json.Parsed(schema.BulkBanResult) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .user_ids = user_ids, .delete_message_seconds = delete_message_seconds }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/bulk-ban", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.POST, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.BulkBanResult, self.allocator, res.status_code, res.body);
    }

    pub fn fetchMe(self: *Rest, guild_id: []const u8) !std.json.Parsed(schema.GuildMember) {
        const path = try std.fmt.allocPrint(self.allocator, "/users/@me/guilds/{s}/member", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn editMe(self: *Rest, guild_id: []const u8, nick: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .nick = nick }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/users/@me/guilds/{s}/member", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.PATCH, path, body);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.GuildMember, self.allocator, res.status_code, res.body);
    }

    pub fn generateInvite(allocator: std.mem.Allocator, client_id: []const u8, permissions: u64, scopes: []const []const u8) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try out.writer.print("https://discord.com/oauth2/authorize?client_id={s}&permissions={d}&scope=", .{ client_id, permissions });
        for (scopes, 0..) |s, i| {
            if (i > 0) try out.writer.writeAll("%20");
            try out.writer.writeAll(s);
        }
        return out.toOwnedSlice();
    }

    pub fn getStageInstance(self: *Rest, channel_id: []const u8) !std.json.Parsed(schema.StageInstance) {
        const path = try std.fmt.allocPrint(self.allocator, "/stage-instances/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.StageInstance, self.allocator, res.status_code, res.body);
    }

    pub fn createStageInstance(self: *Rest, channel_id: []const u8, topic: []const u8, privacy_level: u32, reason: ?[]const u8) !std.json.Parsed(schema.StageInstance) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{
            .channel_id = channel_id,
            .topic = topic,
            .privacy_level = privacy_level,
        }, .{});
        defer self.allocator.free(body);
        const res = try self.requestFull(.POST, "/stage-instances", body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.StageInstance, self.allocator, res.status_code, res.body);
    }

    pub fn editStageInstance(self: *Rest, channel_id: []const u8, topic: ?[]const u8, privacy_level: ?u32, reason: ?[]const u8) !std.json.Parsed(schema.StageInstance) {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        var jw: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try jw.beginObject();
        if (topic) |t| {
            try jw.objectField("topic");
            try jw.write(t);
        }
        if (privacy_level) |p| {
            try jw.objectField("privacy_level");
            try jw.write(p);
        }
        try jw.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/stage-instances/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.PATCH, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody(schema.StageInstance, self.allocator, res.status_code, res.body);
    }

    pub fn deleteStageInstance(self: *Rest, channel_id: []const u8, reason: ?[]const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/stage-instances/{s}", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.DELETE, path, null, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn setVoiceChannelStatus(self: *Rest, channel_id: []const u8, status: []const u8, reason: ?[]const u8) !void {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .status = status }, .{});
        defer self.allocator.free(body);
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/voice-status", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.requestFull(.PUT, path, body, "application/json", reason);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
    }

    pub fn getChannelWebhooks(self: *Rest, channel_id: []const u8) !std.json.Parsed([]schema.Webhook) {
        const path = try std.fmt.allocPrint(self.allocator, "/channels/{s}/webhooks", .{channel_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Webhook, self.allocator, res.status_code, res.body);
    }

    pub fn getGuildWebhooks(self: *Rest, guild_id: []const u8) !std.json.Parsed([]schema.Webhook) {
        const path = try std.fmt.allocPrint(self.allocator, "/guilds/{s}/webhooks", .{guild_id});
        defer self.allocator.free(path);
        const res = try self.request(.GET, path, null);
        defer self.allocator.free(res.body);
        try ensureSuccess(res);
        return parseBody([]schema.Webhook, self.allocator, res.status_code, res.body);
    }
};

pub fn parseBody(comptime T: type, allocator: std.mem.Allocator, status_code: u16, body: []const u8) !std.json.Parsed(T) {
    return schema.parse(T, allocator, body) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            std.log.warn("discord: non-JSON response body (status {d}, {d} bytes): {s}", .{ status_code, body.len, bodyPreview(body) });
            return error.InvalidResponseBody;
        },
    };
}

fn bodyPreview(body: []const u8) []const u8 {
    return body[0..@min(body.len, 200)];
}

pub const Config = struct {
    intents: u32 = 0,
    cache: cache_mod.Limits = .{},
};

fn Slot(comptime T: type) type {
    return struct {
        on: ?*const fn (*Client, T) void = null,
        once: ?*const fn (*Client, T) void = null,
    };
}

pub const Handlers = struct {
    ready: Slot(schema.Ready) = .{},
    resumed: Slot(void) = .{},
    guild_create: Slot(std.json.Value) = .{},
    guild_update: Slot(std.json.Value) = .{},
    guild_delete: Slot(std.json.Value) = .{},
    channel_create: Slot(schema.Channel) = .{},
    channel_update: Slot(schema.Channel) = .{},
    channel_delete: Slot(schema.Channel) = .{},
    channel_pins_update: Slot(std.json.Value) = .{},
    message_create: Slot(schema.Message) = .{},
    message_update: Slot(schema.Message) = .{},
    message_delete: Slot(events.MessageDelete) = .{},
    message_delete_bulk: Slot(std.json.Value) = .{},
    message_poll_vote_add: Slot(schema.MessagePollVote) = .{},
    message_poll_vote_remove: Slot(schema.MessagePollVote) = .{},
    guild_member_add: Slot(schema.GuildMember) = .{},
    guild_member_update: Slot(schema.GuildMember) = .{},
    guild_member_remove: Slot(events.GuildMemberRemove) = .{},
    guild_members_chunk: Slot(schema.GuildMembersChunk) = .{},
    message_reaction_add: Slot(schema.MessageReaction) = .{},
    message_reaction_remove: Slot(schema.MessageReaction) = .{},
    message_reaction_remove_all: Slot(schema.ReactionRemoveAll) = .{},
    message_reaction_remove_emoji: Slot(schema.ReactionRemoveEmoji) = .{},
    interaction_create: Slot(schema.Interaction) = .{},
    user_update: Slot(std.json.Value) = .{},
    presence_update: Slot(schema.Presence) = .{},
    typing_start: Slot(schema.TypingStart) = .{},
    voice_state_update: Slot(schema.VoiceState) = .{},
    voice_server_update: Slot(schema.VoiceServerUpdate) = .{},
    voice_channel_effect_send: Slot(std.json.Value) = .{},
    webhooks_update: Slot(schema.WebhooksUpdate) = .{},
    invite_create: Slot(std.json.Value) = .{},
    invite_delete: Slot(std.json.Value) = .{},
    guild_ban_add: Slot(schema.GuildBan) = .{},
    guild_ban_remove: Slot(schema.GuildBan) = .{},
    guild_role_create: Slot(schema.Role) = .{},
    guild_role_update: Slot(schema.Role) = .{},
    guild_role_delete: Slot(events.RoleDelete) = .{},
    guild_emojis_update: Slot(std.json.Value) = .{},
    guild_stickers_update: Slot(std.json.Value) = .{},
    guild_integrations_update: Slot(std.json.Value) = .{},
    guild_audit_log_entry_create: Slot(std.json.Value) = .{},
    auto_moderation_rule_create: Slot(std.json.Value) = .{},
    auto_moderation_rule_update: Slot(std.json.Value) = .{},
    auto_moderation_rule_delete: Slot(std.json.Value) = .{},
    auto_moderation_action_execution: Slot(std.json.Value) = .{},
    application_command_permissions_update: Slot(std.json.Value) = .{},
    entitlement_create: Slot(schema.Entitlement) = .{},
    entitlement_update: Slot(schema.Entitlement) = .{},
    entitlement_delete: Slot(schema.Entitlement) = .{},
    subscription_create: Slot(std.json.Value) = .{},
    subscription_update: Slot(std.json.Value) = .{},
    subscription_delete: Slot(std.json.Value) = .{},
    guild_scheduled_event_create: Slot(std.json.Value) = .{},
    guild_scheduled_event_update: Slot(std.json.Value) = .{},
    guild_scheduled_event_delete: Slot(std.json.Value) = .{},
    guild_scheduled_event_user_add: Slot(std.json.Value) = .{},
    guild_scheduled_event_user_remove: Slot(std.json.Value) = .{},
    guild_soundboard_sound_create: Slot(std.json.Value) = .{},
    guild_soundboard_sound_update: Slot(std.json.Value) = .{},
    guild_soundboard_sound_delete: Slot(std.json.Value) = .{},
    guild_soundboard_sounds_update: Slot(std.json.Value) = .{},
    stage_instance_create: Slot(std.json.Value) = .{},
    stage_instance_update: Slot(std.json.Value) = .{},
    stage_instance_delete: Slot(std.json.Value) = .{},
    thread_create: Slot(std.json.Value) = .{},
    thread_update: Slot(std.json.Value) = .{},
    thread_delete: Slot(std.json.Value) = .{},
    thread_list_sync: Slot(std.json.Value) = .{},
    thread_members_update: Slot(std.json.Value) = .{},
    thread_member_update: Slot(std.json.Value) = .{},
    unknown: Slot(std.json.Value) = .{},
};

pub const MemberRequest = struct {
    guild_id: []u8,
    query: []u8,
    limit: u32,
};

pub const ClientApplication = struct {
    _slot: usize = 0,

    fn client(self: *ClientApplication) *Client {
        return @alignCast(@fieldParentPtr("application", self));
    }

    pub fn fetch(self: *ClientApplication) !std.json.Parsed(schema.Application) {
        return self.client().rest.getCurrentApplication();
    }

    pub fn commands(self: *ClientApplication, application_id: []const u8) slash_mod.ApplicationCommands {
        return slash_mod.ApplicationCommands.init(&self.client().rest, application_id);
    }

    pub fn entitlements(self: *ClientApplication, application_id: []const u8) ApplicationEntitlements {
        return ApplicationEntitlements.init(&self.client().rest, application_id);
    }
};

pub const ApplicationEntitlements = struct {
    rest: *Rest,
    application_id: []const u8,

    pub fn init(rest: *Rest, application_id: []const u8) ApplicationEntitlements {
        return .{ .rest = rest, .application_id = application_id };
    }

    pub fn fetch(self: ApplicationEntitlements, limit: u32) !std.json.Parsed([]schema.Entitlement) {
        return self.rest.listEntitlements(self.application_id, limit);
    }

    pub fn consume(self: ApplicationEntitlements, entitlement_id: []const u8) !void {
        return self.rest.consumeEntitlement(self.application_id, entitlement_id);
    }

    pub fn createTest(self: ApplicationEntitlements, sku_id: []const u8, owner_id: []const u8, owner_type: u8) !std.json.Parsed(schema.Entitlement) {
        return self.rest.createTestEntitlement(self.application_id, sku_id, owner_id, owner_type);
    }

    pub fn deleteTest(self: ApplicationEntitlements, entitlement_id: []const u8) !void {
        return self.rest.deleteTestEntitlement(self.application_id, entitlement_id);
    }
};

pub const Client = struct {
    pub const GatewayIntentBits = intents_mod.GatewayIntentBits;
    pub const cacheWithLimits = cache_mod.cacheWithLimits;
    pub const Options = cache_mod.Options;

    allocator: std.mem.Allocator,
    io: std.Io,
    rest: Rest,
    session: session.Session,
    cache: cache_mod.Cache,
    ca: websockets.CertCache,
    token: ?[]const u8 = null,
    handlers: Handlers = .{},
    member_request: ?MemberRequest = null,
    guilds: guild_mod.Guilds = .{},
    channels: channel_mod.Channels = .{},
    users: user_mod.Users = .{},
    user: user_mod.ClientUser = .{},
    application: ClientApplication = .{},
    presence_request: ?gateway.PresenceData = null,
    collectors: std.ArrayListUnmanaged(*collector_mod.InteractionCollector) = .empty,
    user_loaded: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: anytype) Client {
        const C = @TypeOf(config);
        const resolved_intents: u32 = if (@hasField(C, "intents"))
            intents_mod.of(config.intents)
        else
            0;
        const limits: cache_mod.Limits = if (@hasField(C, "cache"))
            cache_mod.parseLimits(config.cache)
        else
            .{};
        const shard = if (@hasField(C, "shard")) config.shard else null;
        const presence = if (@hasField(C, "presence")) config.presence else null;

        return .{
            .allocator = allocator,
            .io = io,
            .rest = Rest.init(allocator, io, ""),
            .session = session.Session.init(allocator, io, .{
                .token = "",
                .intents = resolved_intents,
                .shard = shard,
                .presence = presence,
            }),
            .cache = cache_mod.Cache.init(allocator, limits),
            .ca = websockets.CertCache.init(allocator),
            .presence_request = presence,
        };
    }

    pub fn deinit(self: *Client) void {
        for (self.collectors.items) |c| self.allocator.destroy(c);
        self.collectors.deinit(self.allocator);
        if (self.user_loaded) {
            self.allocator.free(self.user.id);
            self.allocator.free(self.user.username);
            self.allocator.free(self.user.discriminator);
            if (self.user.avatar) |a| self.allocator.free(a);
            self.user_loaded = false;
        }
        if (self.member_request) |*r| {
            self.allocator.free(r.guild_id);
            self.allocator.free(r.query);
        }
        self.ca.deinit();
        self.cache.deinit();
        self.session.deinit();
        self.rest.deinit();
        if (self.token) |t| self.allocator.free(t);
    }

    pub fn login(self: *Client, token: []const u8) !void {
        var owned: ?[]u8 = null;
        errdefer {
            if (owned) |o| self.allocator.free(o);
            self.rest.token = "";
            self.session.config.token = "";
        }
        self.rest.token = token;
        self.session.config.token = token;
        // O rescan do bundle TLS (I/O de disco) roda em paralelo com o
        // `getCurrentUser` (I/O de rede): boot não paga a soma dos dois.
        var cert_job = Rest.CertLoad{ .cache = &self.ca, .io = self.io };
        var cert_group: std.Io.Group = .init;
        cert_group.async(self.io, Rest.certLoadTask, .{&cert_job});
        errdefer {
            cert_group.cancel(self.io);
            cert_group.await(self.io) catch {};
        }
        var me = try self.rest.getCurrentUser();
        defer me.deinit();
        // Falha aqui não é fatal: `serveOnce` tenta `ensure` de novo com a
        // política de backoff existente.
        cert_group.await(self.io) catch {};
        if (cert_job.result) |r| r catch {};

        owned = try self.allocator.dupe(u8, token);
        if (self.token) |old| self.allocator.free(old);
        self.token = owned;
        self.rest.token = owned.?;
        self.session.config.token = owned.?;
        owned = null;
        self.session.clearResume();

        try self.serveForever();
    }

    pub fn serveForever(self: *Client) !void {
        var attempt: u32 = 0;
        while (true) {
            self.serveOnce() catch |err| switch (err) {
                error.GatewayReconnect,
                error.GatewayReidentify,
                error.ConnectionClosed,
                error.Timeout,
                error.HeartbeatTimeout,
                error.NoHello,
                => {
                    const delay = util.backoffMs(attempt);
                    attempt = @min(attempt + 1, 16);
                    try self.io.sleep(.{ .nanoseconds = @as(i96, delay) * std.time.ns_per_ms }, .awake);
                    continue;
                },
                // Quedas de transporte no meio da sessão (FIN silencioso,
                // NAT/LB fechando idle, flap de rede, peer resetando):
                // reconecta com backoff em vez de crashar o processo.
                // `readRaw` já normaliza EOF/falha TLS para
                // `ConnectionClosed`, mas `sendText`/handshake/DNS ainda
                // podem vazar estes erros diretamente.
                error.EndOfStream,
                error.ReadFailed,
                error.WriteFailed,
                error.ConnectionResetByPeer,
                => {
                    std.log.warn("discord: gateway transport drop ({any}), reconnecting", .{err});
                    const delay = util.backoffMs(attempt);
                    attempt = @min(attempt + 1, 16);
                    try self.io.sleep(.{ .nanoseconds = @as(i96, delay) * std.time.ns_per_ms }, .awake);
                    continue;
                },
                else => return err,
            };
        }
    }

    fn serveOnce(self: *Client) !void {
        var host: []const u8 = websockets.host;
        var port: u16 = websockets.port;
        var path: []const u8 = websockets.path;
        var tls = true;
        if (self.session.resume_url) |u| {
            if (gateway.parseGatewayUrl(u)) |t| {
                host = t.host;
                port = t.port;
                path = t.path;
                tls = t.tls;
            }
        }
        var socket = try websockets.connectOptions(self.io, self.allocator, .{
            .host = host,
            .port = port,
            .path = path,
            .tls = tls,
            .ca = &self.ca,
        });
        defer socket.deinit();
        try self.serve(&socket);
    }

    pub fn serve(self: *Client, socket: *websockets.Socket) !void {
        const s = &self.session;

        socket.setReadTimeout(60000);
        const hello_msg = (try socket.read()) orelse return error.NoHello;
        defer socket.done(hello_msg);
        const hello_text = websockets.messageData(hello_msg) orelse return error.NoHello;
        s.hb.reset(try gateway.parseHello(self.allocator, hello_text), util.nowMs(self.io));

        if (s.session_id != null) {
            const resume_msg = try s.resumePayload(self.allocator);
            defer self.allocator.free(resume_msg);
            try socket.sendText(resume_msg);
        } else {
            const identify = try s.identifyPayload(self.allocator);
            defer self.allocator.free(identify);
            try socket.sendText(identify);
        }

        socket.setReadTimeout(1000);

        while (true) {
            const maybe = try socket.read();
            if (maybe) |m| {
                defer socket.done(m);
                if (m.type == .close) {
                    if (websockets.closeCode(m)) |code| {
                        std.log.warn("discord: gateway closed connection (code {d}: {s})", .{ code, gateway.closeCodeName(code) });
                        if (gateway.canResume(code)) return error.GatewayReconnect;
                        return error.GatewayClosed;
                    }
                    return error.GatewayReconnect;
                }
                if (websockets.messageData(m)) |data| {
                    try self.handleEnvelope(data);
                }
            }
            switch (try s.hb.poll(util.nowMs(self.io))) {
                .send => {
                    // Heartbeat cabe sempre em 32 bytes: sem heap por ciclo.
                    var hb_buf: [32]u8 = undefined;
                    try socket.sendText(gateway.encodeHeartbeatBuf(s.seq, &hb_buf));
                },
                .wait => {},
            }
            if (self.presence_request) |p| {
                const payload = try gateway.encodePresenceUpdate(self.allocator, p);
                defer self.allocator.free(payload);
                try socket.sendText(payload);
                self.presence_request = null;
            }
            if (self.member_request) |r| {
                const payload = try gateway.encodeRequestGuildMembers(self.allocator, r.guild_id, r.query, r.limit);
                defer self.allocator.free(payload);
                try socket.sendText(payload);
                self.allocator.free(r.guild_id);
                self.allocator.free(r.query);
                self.member_request = null;
            }
        }
    }

    pub fn on(self: *Client, comptime ev: anytype, handler: anytype) void {
        const t = comptime events.normalize(ev);
        const H = *const fn (*Client, events.Payload(t)) void;
        const h: H = handler;
        @field(self.handlers, @tagName(t)).on = h;
    }

    pub fn once(self: *Client, comptime ev: anytype, handler: anytype) void {
        const t = comptime events.normalize(ev);
        const H = *const fn (*Client, events.Payload(t)) void;
        const h: H = handler;
        @field(self.handlers, @tagName(t)).once = h;
    }

    pub fn off(self: *Client, comptime ev: anytype) void {
        const t = comptime events.normalize(ev);
        const slot = &@field(self.handlers, @tagName(t));
        slot.on = null;
        slot.once = null;
    }

    pub fn emit(self: *Client, comptime t: events.Type, payload: events.Payload(t)) void {
        self.dispatch(t, payload);
    }

    pub fn requestGuildMembers(self: *Client, guild_id: []const u8) !void {
        return self.requestGuildMembersQuery(guild_id, "", 0);
    }

    pub fn requestGuildMembersQuery(self: *Client, guild_id: []const u8, query: []const u8, limit: u32) !void {
        if (self.member_request) |*r| {
            self.allocator.free(r.guild_id);
            self.allocator.free(r.query);
        }
        self.member_request = .{
            .guild_id = try self.allocator.dupe(u8, guild_id),
            .query = try self.allocator.dupe(u8, query),
            .limit = limit,
        };
    }

    fn dispatch(self: *Client, comptime t: events.Type, payload: events.Payload(t)) void {
        const slot = &@field(self.handlers, @tagName(t));
        if (slot.on) |f| f(self, payload);
        if (slot.once) |o| {
            slot.once = null;
            o(self, payload);
        }
    }

    fn dispatchValue(self: *Client, t: events.Type, d: ?std.json.Value) !void {
        const value = d orelse return;
        try self.cache.update(t, value);
        if (t == .ready) {
            var parsed = try std.json.parseFromValue(schema.Ready, self.allocator, value, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();
            try self.session.storeReady(parsed.value.session_id, parsed.value.resume_gateway_url);
            // Os slices de `parsed` emprestam `value` (liberado no fim do
            // envelope): dupe para `user` não pendurar.
            if (self.user_loaded) {
                self.allocator.free(self.user.id);
                self.allocator.free(self.user.username);
                self.allocator.free(self.user.discriminator);
                if (self.user.avatar) |a| self.allocator.free(a);
                self.user_loaded = false;
            }
            self.user.id = try self.allocator.dupe(u8, parsed.value.user.id);
            errdefer self.allocator.free(self.user.id);
            self.user.username = try self.allocator.dupe(u8, parsed.value.user.username);
            errdefer self.allocator.free(self.user.username);
            self.user.discriminator = try self.allocator.dupe(u8, parsed.value.user.discriminator);
            errdefer self.allocator.free(self.user.discriminator);
            self.user.avatar = if (parsed.value.user.avatar) |a| try self.allocator.dupe(u8, a) else null;
            self.user.bot = parsed.value.user.bot;
            self.user_loaded = true;
        }
        if (t == .interaction_create) {
            const slot = &@field(self.handlers, @tagName(.interaction_create));
            const want_collectors = self.collectors.items.len > 0;
            if (want_collectors or slot.on != null or slot.once != null) {
                // Parse único: alimenta collectors e o handler com o mesmo valor.
                var parsed_inter = std.json.parseFromValue(schema.Interaction, self.allocator, value, .{ .ignore_unknown_fields = true }) catch |err| {
                    const raw_json = std.json.Stringify.valueAlloc(self.allocator, value, .{}) catch "<?>";
                    defer if (!std.mem.eql(u8, raw_json, "<?>")) self.allocator.free(raw_json);
                    std.log.warn("discord: failed to parse payload for event interaction_create: {any}\nPayload: {s}", .{ err, raw_json });
                    return;
                };
                defer parsed_inter.deinit();
                if (want_collectors) {
                    const now = util.nowMs(self.io);
                    var ci: usize = 0;
                    while (ci < self.collectors.items.len) {
                        const c = self.collectors.items[ci];
                        if (c.ended or c.checkExpired(now)) {
                            self.allocator.destroy(c);
                            _ = self.collectors.swapRemove(ci);
                            continue;
                        }
                        _ = c.handleInteraction(parsed_inter.value, now);
                        if (c.ended) {
                            self.allocator.destroy(c);
                            _ = self.collectors.swapRemove(ci);
                        } else {
                            ci += 1;
                        }
                    }
                }
                self.dispatch(.interaction_create, parsed_inter.value);
                return;
            }
            return;
        }
        switch (t) {
            inline else => |tag| {
                const slot = &@field(self.handlers, @tagName(tag));
                if (slot.on == null and slot.once == null) return;

                const P = events.Payload(tag);
                if (P == void) {
                    self.dispatch(tag, {});
                    return;
                }
                var parsed = std.json.parseFromValue(P, self.allocator, value, .{ .ignore_unknown_fields = true }) catch |err| {
                    std.log.warn("discord: failed to parse payload for event {s}: {any}", .{ @tagName(tag), err });
                    return;
                };
                defer parsed.deinit();
                self.dispatch(tag, parsed.value);
            },
        }

    }

    fn handleEnvelope(self: *Client, text: []const u8) !void {
        var env = try gateway.decode(self.allocator, text);
        defer env.deinit();
        const s = &self.session;
        switch (gateway.Op.fromInt(env.value.op)) {
            .dispatch => {
                s.trackDispatch(env.value.s);
                try self.dispatchValue(events.classify(env.value.t), env.value.d);
            },
            .heartbeat => {
                s.hb.request();
            },
            .reconnect => {
                return error.GatewayReconnect;
            },
            .invalid_session => {
                if (env.value.d) |d| {
                    switch (d) {
                        .bool => |resumable| {
                            if (resumable) return error.GatewayReconnect;
                        },
                        else => {},
                    }
                }
                self.session.clearResume();
                return error.GatewayReidentify;
            },
            .hello => {
                s.hb.setInterval(45000);
            },
            .heartbeat_ack => {
                s.hb.onAck();
            },
            else => {},
        }
    }

    pub fn joinVoiceChannel(self: *Client, options: anytype) !voice_mod.VoiceConnection {
        _ = self;
        const O = @TypeOf(options);
        const guild_id = if (@hasField(O, "guild_id")) options.guild_id else if (@hasField(O, "guildId")) options.guildId else return error.MissingGuildId;
        const channel_id = if (@hasField(O, "channel_id")) options.channel_id else if (@hasField(O, "channelId")) options.channelId else return error.MissingChannelId;
        const self_mute = if (@hasField(O, "self_mute")) options.self_mute else if (@hasField(O, "selfMute")) options.selfMute else false;
        const self_deaf = if (@hasField(O, "self_deaf")) options.self_deaf else if (@hasField(O, "selfDeaf")) options.selfDeaf else false;

        var conn = voice_mod.VoiceConnection.init(guild_id, channel_id);
        conn.self_mute = self_mute;
        conn.self_deaf = self_deaf;
        return conn;
    }

    pub fn setPresence(self: *Client, presence: gateway.PresenceData) !void {
        self.session.config.presence = presence;
        self.presence_request = presence;
    }

    pub fn createMessageComponentCollector(self: *Client, options: collector_mod.InteractionCollectorOptions) !*collector_mod.InteractionCollector {
        const col = try self.allocator.create(collector_mod.InteractionCollector);
        col.* = collector_mod.InteractionCollector.init(self.allocator, options, util.nowMs(self.io));
        try self.collectors.append(self.allocator, col);
        return col;
    }

    pub fn leaveVoiceChannel(self: *Client, guild_id: []const u8) !void {
        _ = self;
        _ = guild_id;
    }
};

pub const WebhookClient = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    rest: Rest,
    id: []const u8,
    token: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, id: []const u8, token: []const u8) WebhookClient {
        return .{
            .allocator = allocator,
            .io = io,
            .rest = Rest.init(allocator, io, ""),
            .id = id,
            .token = token,
        };
    }

    pub fn deinit(self: *WebhookClient) void {
        self.rest.deinit();
    }

    pub fn send(self: *WebhookClient, content: []const u8) !std.json.Parsed(schema.Message) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .content = content }, .{});
        defer self.allocator.free(body);
        return self.rest.executeWebhook(self.id, self.token, body);
    }

    pub fn sendRich(self: *WebhookClient, opts: Rest.MessageCreate) !std.json.Parsed(schema.Message) {
        const body = try Rest.messageCreateBody(self.allocator, opts);
        defer self.allocator.free(body);
        return self.rest.executeWebhook(self.id, self.token, body);
    }

    pub fn editMessage(self: *WebhookClient, message_id: []const u8, content: []const u8) !std.json.Parsed(schema.Message) {
        const body = try std.json.Stringify.valueAlloc(self.allocator, .{ .content = content }, .{});
        defer self.allocator.free(body);
        return self.rest.editWebhookMessage(self.id, self.token, message_id, body);
    }

    pub fn deleteMessage(self: *WebhookClient, message_id: []const u8) !void {
        return self.rest.deleteWebhookMessage(self.id, self.token, message_id);
    }
};
