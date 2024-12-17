const std = @import("std");

// 4623158 too high, 4600700 too high.

const Allocator = std.mem.Allocator;

const Map = [][]u8;
const max_usize = std.math.maxInt(usize);

/// Returns a 2d view onto the given file buffer, split by newline characters.
fn read_map(ally: *const Allocator, b: []u8) !Map {
    var array = std.ArrayList([]u8).init(ally.*);
    defer array.deinit();

    // x, y positions for bytes in the given buff.
    var row_i: usize = 0;
    var col_i: usize = 0;

    var row_start: usize = 0;
    const last_i: usize = b.len - 1;
    for (b, 0..) |c, i| {
        switch (c) {
            '\n' => {
                try array.append(b[row_start..i]);
                row_start = i + 1;
                row_i += 1;
                col_i = 0;
            },
            else => {
                if (i == last_i) { // No final newline.
                    try array.append(b[row_start..]);
                }
                col_i += 1;
            },
        }
    }

    return array.toOwnedSlice();
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    const map = try read_map(ally, buff);
    const tsize: usize = 'Z' - 'A' + 1;

    var as: [tsize]usize = undefined; // Area per bucket.
    var ps: [tsize]usize = undefined; // Perimeter per bucket.
    var ls: [tsize]usize = undefined; // Lonely perimeter per bucket.
    var bucket: [tsize]usize = undefined; // Row bucket.
    for (0..tsize) |i| {
        as[i] = 0;
        ps[i] = 0;
        ls[i] = 0;
        bucket[i] = max_usize;
    }

    var price: usize = 0;
    for (0..map.len) |y| {
        for (0..map[y].len) |x| {
            const c = map[y][x];
            const cu = c - 'A';

            var p: usize = 4;
            if ((y > 0) and (map[y - 1][x] == c)) {
                p -= 1;
            }
            if ((y < map.len - 1) and (map[y + 1][x] == c)) {
                p -= 1;
            }
            if ((x > 0) and (map[y][x - 1] == c)) {
                p -= 1;
            }
            if ((x < map[y].len - 1) and (map[y][x + 1] == c)) {
                p -= 1;
            }

            if (p == 4) {
                std.debug.print("{d}: +4 at {d}{d}\n", .{ price, y, x });
                // ls[cu] += p;
                price += 4;
                // bucket[cu] = max_usize;
            } else {
                as[cu] += 1;
                ps[cu] += p;
                bucket[cu] = y; // Update the current row bucket.
                std.debug.print("{d}: +{d}*{d} (prior) at {d}{d}\n", .{ price, ps[cu], as[cu], y, x });
            }
        }

        for (0..tsize) |i| {
            if ((bucket[i] == max_usize) or (bucket[i] == y)) {
                // bucket[i] = y;
            } else if (y != 0) {
                // Last row, or group ended by a gap, update the price.
                std.debug.print("Group {d} ended with price: {d}*{d}+{d} before row {d}\n", .{ i, ps[i], as[i], ls[i], y });

                price += ps[i] * as[i] + ls[i];
                bucket[i] = max_usize;

                as[i] = 0;
                ps[i] = 0;
                ls[i] = 0;
            }
        }
    }

    for (0..tsize) |i| {
        if ((as[i] != 0) or (ls[i] != 0)) {
            std.debug.print("Group {d} ended with price: {d}*{d}+{d} at row {d}\n", .{ i, ps[i], as[i], ls[i], map.len - 1 });
        }
        price += ps[i] * as[i] + ls[i];
    }

    return price;
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
    const price = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{price});
}
