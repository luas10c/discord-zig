const std = @import("std");
const schema = @import("./schema.zig");

pub const max_question_len = 300;
pub const max_answers = 10;
pub const max_answer_len = 55;
pub const max_duration_hours = 768;

pub const BuildError = error{
    MissingQuestion,
    QuestionTooLong,
    NoAnswers,
    TooManyAnswers,
    AnswerTextEmpty,
    AnswerTextTooLong,
    BadDuration,
} || std.mem.Allocator.Error;

pub const AnswerInput = struct {
    text: []const u8,
    emoji_name: ?[]const u8 = null,
    emoji_id: ?[]const u8 = null,
};

pub const Builder = struct {
    arena: std.heap.ArenaAllocator,
    question: ?[]const u8 = null,
    answers: std.ArrayListUnmanaged(schema.PollAnswerCreate) = .empty,
    duration_hours: ?u32 = null,
    multiselect: bool = false,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *Builder) void {
        self.answers.deinit(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setQuestion(self: *Builder, question: []const u8) !void {
        self.question = try self.arena.allocator().dupe(u8, question);
    }

    pub fn addAnswer(self: *Builder, answer: AnswerInput) !void {
        const aa = self.arena.allocator();
        const emoji: ?schema.Emoji = if (answer.emoji_name != null or answer.emoji_id != null) .{
            .name = if (answer.emoji_name) |n| try aa.dupe(u8, n) else null,
            .id = if (answer.emoji_id) |id| try aa.dupe(u8, id) else null,
        } else null;
        try self.answers.append(aa, .{
            .poll_media = .{
                .text = try aa.dupe(u8, answer.text),
                .emoji = emoji,
            },
        });
    }

    pub fn setDurationHours(self: *Builder, hours: u32) void {
        self.duration_hours = hours;
    }

    pub fn setMultiselect(self: *Builder, multiselect: bool) void {
        self.multiselect = multiselect;
    }

    pub fn build(self: *Builder) BuildError!schema.PollCreate {
        const question = self.question orelse return error.MissingQuestion;
        if (question.len == 0 or question.len > max_question_len) return error.QuestionTooLong;
        if (self.answers.items.len == 0) return error.NoAnswers;
        if (self.answers.items.len > max_answers) return error.TooManyAnswers;
        for (self.answers.items) |a| {
            const text = a.poll_media.text orelse return error.AnswerTextEmpty;
            if (text.len == 0 or text.len > max_answer_len) return error.AnswerTextTooLong;
        }
        if (self.duration_hours) |h| {
            if (h == 0 or h > max_duration_hours) return error.BadDuration;
        }
        return .{
            .question = .{ .text = question },
            .answers = self.answers.items,
            .duration = self.duration_hours,
            .allow_multiselect = self.multiselect,
            .layout_type = 1,
        };
    }
};

pub fn createBody(allocator: std.mem.Allocator, create: schema.PollCreate) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .poll = create }, .{ .emit_null_optional_fields = false });
}
