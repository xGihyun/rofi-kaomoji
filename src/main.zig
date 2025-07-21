const std = @import("std");

const Emoji = struct {
    value: []const u8,
    tags: [][]const u8,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const HOME = std.posix.getenv("HOME").?;
    const config_path = try std.fmt.allocPrint(allocator, "{s}/dotfiles-hyprland/emoji.json", .{HOME});
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const file_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(file_buffer);

    _ = try file.readAll(file_buffer);

    const emojis = try std.json.parseFromSlice([]Emoji, allocator, file_buffer, .{});
    defer emojis.deinit();

    const selected_emoji = try selectEmoji(allocator, emojis.value);

    if (selected_emoji) |emoji| {
        try copyEmoji(allocator, emoji);
    }
}

fn selectEmoji(allocator: std.mem.Allocator, emojis: []Emoji) !?Emoji {
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    for (emojis) |emoji| {
        try str.appendSlice(emoji.value);
        try str.append(' ');

        const tags = try std.mem.join(allocator, ", ", emoji.tags);
        defer allocator.free(tags);

        try str.appendSlice(tags);
        try str.append('\n');
    }

    const rofi_cmd = [_][]const u8{ "rofi", "-format", "i", "-dmenu", "-i", "-p", "Kaomoji" };
    var child = std.process.Child.init(&rofi_cmd, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(str.items);
        stdin.close();
        child.stdin = null;
    }

    var stdout: std.ArrayListUnmanaged(u8) = .empty;
    defer stdout.deinit(allocator);

    var stderr: std.ArrayListUnmanaged(u8) = .empty;
    defer stderr.deinit(allocator);

    try child.collectOutput(allocator, &stdout, &stderr, 1024);

    _ = try child.wait();

    if (stdout.items.len == 0) {
        return null;
    }

    const trimmed = std.mem.trim(u8, stdout.items, &std.ascii.whitespace);
    const emoji_idx = try std.fmt.parseInt(usize, trimmed, 10);
    if (emoji_idx >= emojis.len) {
        std.debug.print("Emoji index is out of bounds.", .{});
        return null;
    }

    const selected_emoji = emojis[emoji_idx];
    return selected_emoji;
}

fn copyEmoji(allocator: std.mem.Allocator, emoji: Emoji) !void {
    const cmd = [_][]const u8{ "wl-copy", emoji.value };
    var child = std.process.Child.init(&cmd, allocator);
    _ = try child.spawnAndWait();
}

test "stuff" {
    const allocator = std.testing.allocator;
    const data =
        \\[
        \\{ "value": "(>_<)", "tags": ["painful"] },
        \\{ "value": "( ´-ω･)︻┻┳══━一", "tags": ["sniper"] },
        \\{ "value": "(/ω･＼)", "tags": ["peering", "shy"] }
        \\]
    ;

    const emojis = try std.json.parseFromSlice([]Emoji, allocator, data, .{});
    defer emojis.deinit();

    _ = try selectEmoji(allocator, emojis.value);
}
