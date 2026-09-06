const std = @import("std");

pub const discord_epoch: u64 = 1420070400000;

pub const Snowflake = struct {
    value: u64,

    pub fn parse(text: []const u8) !Snowflake {
        return .{ .value = try std.fmt.parseInt(u64, text, 10) };
    }

    pub fn fromValue(value: u64) Snowflake {
        return .{ .value = value };
    }

    pub fn fromTimestampMs(timestamp_ms: u64) Snowflake {
        return .{ .value = (timestamp_ms - discord_epoch) << 22 };
    }

    pub fn timestampMs(self: Snowflake) u64 {
        return (self.value >> 22) + discord_epoch;
    }

    pub fn workerId(self: Snowflake) u5 {
        return @truncate((self.value & 0x3E0000) >> 17);
    }

    pub fn processId(self: Snowflake) u5 {
        return @truncate((self.value & 0x1F000) >> 12);
    }

    pub fn increment(self: Snowflake) u12 {
        return @truncate(self.value & 0xFFF);
    }

    pub fn eql(a: Snowflake, b: Snowflake) bool {
        return a.value == b.value;
    }

    pub fn format(self: Snowflake, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.printInt(self.value, 10, .lower, .{});
    }
};
