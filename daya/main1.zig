const std = @import("std");

const Allocator = std.mem.Allocator;

const Map = [][]u8;
const TrailStart = '0';
const TrailEnd = '9';
const Unreachable = '.';

const dirs = [_][2]usize{
    // y  x.
    .{ 0, 1 }, // Right (add).
    .{ 1, 0 }, // Down (add).
    .{ 0, 1 }, // Left (sub).
    .{ 1, 0 }, // Up (sub).
};

const block_dirs = [_]usize{ 2, 3, 0, 1 };

fn add(a: usize, b: usize) struct { usize, u1 } {
    return @addWithOverflow(a, b);
}
fn sub(a: usize, b: usize) struct { usize, u1 } {
    return @subWithOverflow(a, b);
}

const Operation = *const fn (a: usize, b: usize) struct { usize, u1 };
const dirs_op = [_]Operation{ add, add, sub, sub };

fn trail_score(map: Map, row_i: usize, col_i: usize, block_dir: ?usize) usize {
    var score: usize = 0;

    const head = map[row_i][col_i];
    if (head == TrailEnd) return 1;

    var nrow_i: usize = undefined;
    var ncol_i: usize = undefined;
    var overflow: u1 = undefined;

    for (dirs, dirs_op, 0..) |dir, op, i| {
        if (block_dir == i) continue;

        nrow_i, overflow = op(row_i, dir[0]);
        if (overflow == @as(u1, 1)) continue;
        ncol_i, overflow = op(col_i, dir[1]);
        if (overflow == @as(u1, 1)) continue;

        if ((nrow_i >= map.len) or (ncol_i >= map[row_i].len)) continue;
        if (map[nrow_i][ncol_i] == head + 1) {
            score += trail_score(map, nrow_i, ncol_i, block_dirs[i]);
        }
    }

    return score;
}

/// Returns a 2d view onto the given file buffer, split by newline characters.
fn read_map(ally: *const Allocator, buff: []u8) !Map {
    var array = std.ArrayList([]u8).init(ally.*);
    defer array.deinit();

    // x, y positions for bytes in the given buff.
    var row_i: usize = 0;
    var col_i: usize = 0;

    var row_start: usize = 0;
    const last_i: usize = buff.len - 1;
    for (buff, 0..) |c, i| {
        switch (c) {
            '\n' => {
                try array.append(buff[row_start..i]);
                row_start = i + 1;
                row_i += 1;
                col_i = 0;
            },
            else => {
                if (i == last_i) { // No final newline.
                    try array.append(buff[row_start..]);
                }
                col_i += 1;
            },
        }
    }

    return array.toOwnedSlice();
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    const map: Map = try read_map(ally, buff);
    var score: usize = 0;

    for (0..map.len) |row_i| {
        for (0..map[row_i].len) |col_i| {
            if (map[row_i][col_i] != TrailStart) continue;
            score += trail_score(map, row_i, col_i, null);
        }
    }

    return score;
}

pub fn main() !void {
    const pg_ally = std.heap.page_allocator;

    // Process command-line arguments passed to main.
    const args = try std.process.argsAlloc(pg_ally);
    defer std.process.argsFree(pg_ally, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <input filename>\n", .{args[0]});
        return;
    }

    // Get passed input filename.
    const filename = args[1];
    std.debug.print("Reading file for input: {s}\n", .{filename});

    // Open the given filename as input file for reading.
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_buff = try file.readToEndAlloc(pg_ally, stat.size);
    defer pg_ally.free(file_buff);

    // Process the file.
    const score = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{score});
}
