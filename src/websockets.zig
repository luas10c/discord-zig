const std = @import("std");
const builtin = @import("builtin");
const tls = std.crypto.tls;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Bundle = std.crypto.Certificate.Bundle;

pub const host: []const u8 = "gateway.discord.gg";
pub const port: u16 = 443;
pub const path: []const u8 = "/?v=10&encoding=json";
pub const max_message_size: usize = 8 * 1024 * 1024;
pub const websocket_guid: []const u8 = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

pub const Message = struct {
    type: Type,
    data: []u8,

    pub const Type = enum {
        text,
        binary,
        ping,
        pong,
        close,
    };
};

pub const CertCache = struct {
    gpa: Allocator,
    bundle: Bundle = .empty,
    lock: Io.RwLock = .init,
    loaded: bool = false,

    pub fn init(gpa: Allocator) CertCache {
        return .{ .gpa = gpa };
    }

    pub fn ensure(self: *CertCache, io: Io) !void {
        if (self.loaded) return;
        var fresh: Bundle = .empty;
        errdefer fresh.deinit(self.gpa);
        try fresh.rescan(self.gpa, io, Io.Timestamp.now(io, .real));
        self.bundle.deinit(self.gpa);
        self.bundle = fresh;
        self.loaded = true;
    }

    pub fn deinit(self: *CertCache) void {
        if (!self.loaded) return;
        self.bundle.deinit(self.gpa);
        self.* = undefined;
    }
};

const TlsContext = struct {
    client: tls.Client,
    stream_reader: Io.net.Stream.Reader,
    stream_writer: Io.net.Stream.Writer,
    arena: std.heap.ArenaAllocator,
};

pub const Socket = struct {
    io: Io,
    allocator: Allocator,
    net_stream: Io.net.Stream,
    tls_ctx: ?*TlsContext,
    read_timeout_ms: u32,
    msg_buf: []u8,
    msg_len: usize,
    frag_opcode: ?u8,

    pub fn deinit(self: *Socket) void {
        if (self.tls_ctx) |ctx| {
            ctx.client.end() catch {};
            ctx.arena.deinit();
            self.allocator.destroy(ctx);
            self.tls_ctx = null;
        }
        self.net_stream.close(self.io);
        self.allocator.free(self.msg_buf);
        self.* = undefined;
    }

    pub fn setReadTimeout(self: *Socket, ms: u32) void {
        self.read_timeout_ms = ms;
    }

    pub fn sendText(self: *Socket, text: []const u8) !void {
        // writeFrame não muta mais o payload (mascara por blocos na pilha),
        // então dá para enviar o slice do chamador sem dupe temporário.
        try self.writeFrame(0x1, text);
    }

    pub fn read(self: *Socket) !?Message {
        if (!try self.pollReadable()) return null;
        const saved = self.read_timeout_ms;
        self.read_timeout_ms = 30000;
        defer self.read_timeout_ms = saved;
        while (true) {
            const h = try self.readHeader();
            switch (h.opcode) {
                0x0, 0x1, 0x2 => {
                    if (h.opcode != 0 and self.frag_opcode != null) return error.ProtocolError;
                    if (h.opcode == 0 and self.frag_opcode == null) return error.ProtocolError;
                    const start = if (h.opcode == 0) self.frag_opcode.? else h.opcode;
                    if (h.opcode != 0) self.msg_len = 0;
                    try self.appendPayload(h);
                    if (h.fin) {
                        self.frag_opcode = null;
                        return .{
                            .type = if (start == 0x2) .binary else .text,
                            .data = self.msg_buf[0..self.msg_len],
                        };
                    }
                    self.frag_opcode = start;
                },
                0x8 => {
                    self.msg_len = 0;
                    try self.appendPayload(h);
                    self.writeFrame(0x8, &.{}) catch {};
                    self.frag_opcode = null;
                    return .{ .type = .close, .data = self.msg_buf[0..self.msg_len] };
                },
                0x9 => {
                    var ctrl: [125]u8 = undefined;
                    if (h.len > ctrl.len) return error.ProtocolError;
                    try self.readFull(ctrl[0..h.len]);
                    if (h.masked) applyMask(h.mask, ctrl[0..h.len]);
                    self.writeFrame(0xA, ctrl[0..h.len]) catch {};
                },
                0xA => {
                    var ctrl: [125]u8 = undefined;
                    if (h.len > ctrl.len) return error.ProtocolError;
                    try self.readFull(ctrl[0..h.len]);
                },
                else => return error.ProtocolError,
            }
        }
    }

    pub fn done(self: *Socket, message: Message) void {
        // O buffer de recepção cresce sob demanda até 8MB (picos de
        // GUILD_CREATE etc). Encolhe aqui — quando ninguém mais usa `data` —
        // para não segurar megabytes ociosos entre eventos.
        const cap = self.msg_buf.len;
        if (cap > 262144 and self.msg_len * 4 < cap) {
            const want = @max(self.msg_len * 2, 8192);
            if (want < cap) {
                if (self.allocator.realloc(self.msg_buf, want)) |smaller| {
                    self.msg_buf = smaller;
                } else |_| {}
            }
        }
        _ = message;
    }

    pub fn close(self: *Socket) !void {
        self.writeFrame(0x8, &.{}) catch {};
        self.deinit();
    }

    fn writeAll(self: *Socket, data: []const u8) !void {
        if (self.tls_ctx) |ctx| {
            try ctx.client.writer.writeAll(data);
            try ctx.client.writer.flush();
            try ctx.stream_writer.interface.flush();
            return;
        }
        var w = self.net_stream.writer(self.io, &.{});
        try w.interface.writeAll(data);
        try w.interface.flush();
    }

    fn pollReadable(self: *Socket) !bool {
        if (self.tls_ctx) |ctx| {
            if (ctx.client.reader.bufferedLen() != 0) return true;
            if (hasBufferedTlsRecord(ctx.client.input)) return true;
        }
        if (comptime builtin.os.tag == .windows) return true;
        if (self.read_timeout_ms == 0) return true;
        var pfd = [_]std.posix.pollfd{.{ .fd = self.net_stream.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        const ms: i32 = @intCast(@min(self.read_timeout_ms, std.math.maxInt(i32)));
        const ready = try std.posix.poll(&pfd, ms);
        return ready != 0;
    }

    const FrameHeader = struct {
        fin: bool,
        opcode: u8,
        len: u64,
        masked: bool,
        mask: [4]u8,
    };

    fn readRaw(self: *Socket, buf: []u8) !usize {
        if (buf.len == 0) return 0;
        if (self.tls_ctx) |ctx| {
            if (ctx.client.reader.bufferedLen() == 0 and !hasBufferedTlsRecord(ctx.client.input)) {
                if (!try self.pollReadable()) return error.WouldBlock;
            }
            var w: Io.Writer = .fixed(buf);
            while (true) {
                const n = try ctx.client.reader.stream(&w, .limited(buf.len));
                if (n != 0) return n;
            }
        }
        if (!try self.pollReadable()) return error.WouldBlock;
        var data = [_][]u8{buf};
        const n = try self.io.vtable.netRead(self.io.userdata, self.net_stream.socket.handle, &data);
        if (n == 0) return error.ConnectionClosed;
        return n;
    }

    fn readFull(self: *Socket, buf: []u8) !void {
        var off: usize = 0;
        while (off < buf.len) {
            const n = try self.readRaw(buf[off..]);
            if (n == 0) return error.ConnectionClosed;
            off += n;
        }
    }

    fn readHeader(self: *Socket) !FrameHeader {
        var hb: [2]u8 = undefined;
        self.readFull(&hb) catch |err| {
            if (err == error.WouldBlock) return error.Timeout;
            return err;
        };
        const fin = hb[0] & 0x80 != 0;
        const opcode = hb[0] & 0x0F;
        const masked = hb[1] & 0x80 != 0;
        var len: u64 = hb[1] & 0x7F;
        if (len == 126) {
            var eb: [2]u8 = undefined;
            try self.readFull(&eb);
            len = std.mem.readInt(u16, &eb, .big);
        } else if (len == 127) {
            var eb: [8]u8 = undefined;
            try self.readFull(&eb);
            len = std.mem.readInt(u64, &eb, .big);
            if (len >> 63 != 0) return error.FrameTooLarge;
        }
        if (len > max_message_size) return error.FrameTooLarge;
        if (opcode >= 0x8 and (!fin or len > 125)) return error.ProtocolError;
        var mask: [4]u8 = .{ 0, 0, 0, 0 };
        if (masked) try self.readFull(&mask);
        return .{ .fin = fin, .opcode = opcode, .len = len, .masked = masked, .mask = mask };
    }

    fn appendPayload(self: *Socket, h: FrameHeader) !void {
        const n: usize = @intCast(h.len);
        try self.ensureCapacity(self.msg_len + n);
        const dest = self.msg_buf[self.msg_len .. self.msg_len + n];
        try self.readFull(dest);
        if (h.masked) applyMask(h.mask, dest);
        self.msg_len += n;
    }

    fn ensureCapacity(self: *Socket, needed: usize) !void {
        if (needed > max_message_size) return error.FrameTooLarge;
        if (needed <= self.msg_buf.len) return;
        var cap = self.msg_buf.len * 2;
        while (cap < needed) cap *= 2;
        cap = @min(cap, max_message_size);
        self.msg_buf = try self.allocator.realloc(self.msg_buf, cap);
    }

    fn writeFrame(self: *Socket, opcode: u8, payload: []const u8) !void {
        var hb: [10]u8 = undefined;
        const header = encodeHeader(opcode, payload.len, &hb);
        var mask: [4]u8 = undefined;
        self.io.random(&mask);
        var framed: [14]u8 = undefined;
        @memcpy(framed[0..header.len], header);
        framed[1] |= 0x80;
        @memcpy(framed[header.len .. header.len + 4], &mask);
        try self.writeAll(framed[0 .. header.len + 4]);
        // Mascara por blocos num buffer de pilha em vez de mutar o slice do
        // chamador: elimina o dupe temporário por frame enviado.
        var off: usize = 0;
        var chunk: [4096]u8 = undefined;
        while (off < payload.len) {
            const n = @min(chunk.len, payload.len - off);
            @memcpy(chunk[0..n], payload[off .. off + n]);
            applyMaskAt(mask, off, chunk[0..n]);
            try self.writeAll(chunk[0..n]);
            off += n;
        }
    }

    fn doHandshake(self: *Socket, req_path: []const u8, req_host: []const u8) !void {
        var key_bin: [16]u8 = undefined;
        self.io.random(&key_bin);
        var key: [24]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&key, &key_bin);
        var req: [1024]u8 = undefined;
        const text = try std.fmt.bufPrint(&req, "GET {s} HTTP/1.1\r\ncontent-length: 0\r\nupgrade: websocket\r\nsec-websocket-version: 13\r\nconnection: upgrade\r\nsec-websocket-key: {s}\r\nHost: {s}\r\n\r\n", .{ req_path, key, req_host });
        try self.writeAll(text);
        const timeout_ms: u32 = 10000;
        const start = Io.Timestamp.now(self.io, .real).nanoseconds;
        const deadline = start + @as(i96, timeout_ms) * std.time.ns_per_ms;
        var resp: [16384]u8 = undefined;
        var pos: usize = 0;
        // Byte a byte de propósito: ler além do terminador "\r\n\r\n"
        // consumiria bytes do primeiro frame (frequentemente coalescidos no
        // mesmo segmento TCP) e os descartaria, corrompendo o stream.
        while (true) {
            if (pos >= resp.len) return error.ResponseTooLarge;
            var byte: [1]u8 = undefined;
            const n = self.readRaw(&byte) catch |err| {
                if (err == error.WouldBlock) {
                    if (Io.Timestamp.now(self.io, .real).nanoseconds > deadline) return error.Timeout;
                    continue;
                }
                return err;
            };
            if (n == 0) return error.ConnectionClosed;
            resp[pos] = byte[0];
            pos += n;
            if (pos >= 4 and std.mem.eql(u8, resp[pos - 4 .. pos], "\r\n\r\n")) break;
            // Checa o deadline a cada 64 bytes em vez de por byte.
            if (pos % 64 == 0 and Io.Timestamp.now(self.io, .real).nanoseconds > deadline) return error.Timeout;
        }
        if (Io.Timestamp.now(self.io, .real).nanoseconds > deadline) return error.Timeout;
        try validateHandshakeResponse(&key, resp[0..pos]);
    }
};

pub const Options = struct {
    host: []const u8 = host,
    port: u16 = port,
    path: []const u8 = path,
    tls: bool = true,
    ca: ?*CertCache = null,
};

pub fn connect(io: Io, allocator: Allocator) !Socket {
    return connectOptions(io, allocator, .{});
}

pub fn connectOptions(io: Io, allocator: Allocator, options: Options) !Socket {
    const host_name = try Io.net.HostName.init(options.host);
    const net_stream = try host_name.connect(io, options.port, .{ .mode = .stream });
    errdefer net_stream.close(io);

    if (options.ca) |ca| try ca.ensure(io);

    var tls_ctx: ?*TlsContext = null;
    if (options.tls) {
        tls_ctx = try tlsContextInit(io, allocator, net_stream, options.host, options.ca);
    }
    errdefer if (tls_ctx) |ctx| tlsContextDeinit(allocator, ctx);

    var socket = Socket{
        .io = io,
        .allocator = allocator,
        .net_stream = net_stream,
        .tls_ctx = tls_ctx,
        .read_timeout_ms = 0,
        .msg_buf = try allocator.alloc(u8, 8192),
        .msg_len = 0,
        .frag_opcode = null,
    };
    errdefer allocator.free(socket.msg_buf);

    try socket.doHandshake(options.path, options.host);
    return socket;
}

pub fn messageData(message: Message) ?[]const u8 {
    return switch (message.type) {
        .text, .binary => message.data,
        else => null,
    };
}

pub fn closeCode(message: Message) ?u16 {
    if (message.type != .close) return null;
    if (message.data.len < 2) return null;
    return std.mem.readInt(u16, message.data[0..2], .big);
}

pub fn acceptKey(key: []const u8, out: *[28]u8) void {
    var h: [20]u8 = undefined;
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(key);
    hasher.update(websocket_guid);
    hasher.final(&h);
    _ = std.base64.standard.Encoder.encode(out, &h);
}

pub fn encodeHeader(opcode: u8, len: usize, out: *[10]u8) []u8 {
    out[0] = 0x80 | opcode;
    if (len <= 125) {
        out[1] = @intCast(len);
        return out[0..2];
    }
    if (len < 65536) {
        out[1] = 126;
        out[2] = @intCast((len >> 8) & 0xFF);
        out[3] = @intCast(len & 0xFF);
        return out[0..4];
    }
    out[1] = 127;
    out[2] = 0;
    out[3] = 0;
    out[4] = 0;
    out[5] = 0;
    out[6] = @intCast((len >> 24) & 0xFF);
    out[7] = @intCast((len >> 16) & 0xFF);
    out[8] = @intCast((len >> 8) & 0xFF);
    out[9] = @intCast(len & 0xFF);
    return out[0..10];
}

pub fn applyMask(mask: [4]u8, data: []u8) void {
    for (data, 0..) |b, i| data[i] = b ^ mask[i & 3];
}

fn applyMaskAt(mask: [4]u8, base: usize, data: []u8) void {
    for (data, 0..) |b, i| data[i] = b ^ mask[(base + i) & 3];
}

pub fn validateHandshakeResponse(key: []const u8, response: []const u8) !void {
    var expected: [28]u8 = undefined;
    acceptKey(key, &expected);
    var lines = std.mem.splitSequence(u8, response, "\r\n");
    const status = lines.first();
    if (!std.ascii.startsWithIgnoreCase(status, "HTTP/1.1 101 ")) return error.InvalidHandshakeResponse;
    var seen_upgrade = false;
    var seen_connection = false;
    var seen_accept = false;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "upgrade")) {
            if (!std.ascii.eqlIgnoreCase(value, "websocket")) return error.InvalidUpgradeHeader;
            seen_upgrade = true;
        } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
            if (!std.ascii.eqlIgnoreCase(value, "upgrade")) return error.InvalidConnectionHeader;
            seen_connection = true;
        } else if (std.ascii.eqlIgnoreCase(name, "sec-websocket-accept")) {
            if (!std.mem.eql(u8, value, &expected)) return error.InvalidAcceptHeader;
            seen_accept = true;
        }
    }
    if (!seen_upgrade or !seen_connection or !seen_accept) return error.InvalidHandshakeResponse;
}

fn tlsContextInit(io: Io, allocator: Allocator, net_stream: Io.net.Stream, sni_host: []const u8, ca: ?*CertCache) !*TlsContext {
    const ctx = try allocator.create(TlsContext);
    errdefer allocator.destroy(ctx);
    ctx.* = .{
        .client = undefined,
        .stream_reader = undefined,
        .stream_writer = undefined,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
    errdefer ctx.arena.deinit();
    const aa = ctx.arena.allocator();
    var bundle_ptr: *Bundle = undefined;
    var bundle_lock: *Io.RwLock = undefined;
    if (ca) |c| {
        bundle_ptr = &c.bundle;
        bundle_lock = &c.lock;
    } else {
        bundle_ptr = try aa.create(Bundle);
        bundle_ptr.* = .empty;
        try bundle_ptr.rescan(aa, io, Io.Timestamp.now(io, .real));
        bundle_lock = try aa.create(Io.RwLock);
        bundle_lock.* = .init;
    }
    const buf_len = tls.max_ciphertext_record_len;
    const buf = try aa.alloc(u8, buf_len * 4);
    ctx.stream_writer = net_stream.writer(io, buf[0..buf_len]);
    ctx.stream_reader = net_stream.reader(io, buf[buf_len .. 2 * buf_len]);
    var entropy: [tls.Client.Options.entropy_len]u8 = undefined;
    io.random(&entropy);
    ctx.client = try tls.Client.init(
        &ctx.stream_reader.interface,
        &ctx.stream_writer.interface,
        .{
            .ca = .{ .bundle = .{ .gpa = aa, .io = io, .lock = bundle_lock, .bundle = bundle_ptr } },
            .host = .{ .explicit = sni_host },
            .read_buffer = buf[2 * buf_len .. 3 * buf_len],
            .write_buffer = buf[3 * buf_len .. 4 * buf_len],
            .entropy = &entropy,
            .realtime_now = Io.Timestamp.now(io, .real),
        },
    );
    return ctx;
}

fn tlsContextDeinit(allocator: Allocator, ctx: *TlsContext) void {
    ctx.client.end() catch {};
    ctx.arena.deinit();
    allocator.destroy(ctx);
}

fn hasBufferedTlsRecord(input: *Io.Reader) bool {
    const buffered = input.buffered();
    if (buffered.len < tls.record_header_len) return false;
    const record_len = std.mem.readInt(u16, buffered[3..5], .big);
    return buffered.len >= tls.record_header_len + record_len;
}
