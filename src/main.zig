const std = @import("std");

const Kaomoji = struct {
    value: []const u8,
    tags: [][]const u8,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const HOME = std.posix.getenv("HOME").?;
    const config_path = try std.fmt.allocPrint(allocator, "{s}/.config/kaomoji.json", .{HOME});
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const file_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(file_buffer);

    _ = try file.readAll(file_buffer);

    const emojis = try std.json.parseFromSlice([]Kaomoji, allocator, file_buffer, .{});
    defer emojis.deinit();

    const selected_emoji = try selectKaomoji(allocator, emojis.value);

    if (selected_emoji) |emoji| {
        try copyKaomoji(allocator, emoji);
    }
}

fn selectKaomoji(allocator: std.mem.Allocator, kaomojis: []Kaomoji) !?Kaomoji {
    const str_buf = try allocator.alloc(u8, 1024);
    var str = std.ArrayList(u8).initBuffer(str_buf);
    defer str.deinit(allocator);

    for (kaomojis) |kaomoji| {
        try str.appendSlice(allocator, kaomoji.value);
        try str.append(allocator, ' ');

        const tags = try std.mem.join(allocator, ", ", kaomoji.tags);
        defer allocator.free(tags);

        try str.appendSlice(allocator, tags);
        try str.append(allocator, '\n');
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
    const kaomoji_idx = try std.fmt.parseInt(usize, trimmed, 10);
    if (kaomoji_idx >= kaomojis.len) {
        std.log.err("Kaomoji index is out of bounds.", .{});
        return null;
    }

    const selected_emoji = kaomojis[kaomoji_idx];
    return selected_emoji;
}

fn copyKaomoji(allocator: std.mem.Allocator, kaomoji: Kaomoji) !void {
    // Only support Wayland for now
    const cmd = [_][]const u8{ "wl-copy", kaomoji.value };
    var child = std.process.Child.init(&cmd, allocator);
    _ = try child.spawnAndWait();
}

test "select kaomoji" {
    const allocator = std.testing.allocator;
    const data =
        \\[
        \\{ "value": "(>_<)", "tags": ["painful"] },
        \\{ "value": "( ´-ω･)︻┻┳══━一", "tags": ["sniper"] },
        \\{ "value": "(/ω･＼)", "tags": ["peering", "shy"] }
        \\]
    ;

    const emojis = try std.json.parseFromSlice([]Kaomoji, allocator, data, .{});
    defer emojis.deinit();

    const selected = try selectKaomoji(allocator, emojis.value);
    if (selected) |kaomoji| {
        std.debug.print("{s}", .{kaomoji.value});
    }
}
