const std = @import("std");

// Returns a parsed multiplication result or 0 on failure.
fn parse_mult(buff: []const u8) i64 {
    var nums: [2]i64 = .{ 0, 0 };
    const dls: [2]u8 = .{ ',', ')' };

    var num_bsize: usize = 0;
    var idx: usize = 0;

    // Incrementally find and parse two numbers.
    for (buff) |c| {
        if (c == dls[idx]) {
            idx += 1;
            num_bsize = 0;
            if (idx == nums.len) break;
            continue;
        } else if ((c < '0') or (c > '9')) return 0;

        num_bsize += 1;
        if (num_bsize > 3) return 0;
        nums[idx] = nums[idx] * 10 + (c - '0');
    }

    return nums[0] * nums[1];
}

fn process_buff(buff: []u8) i64 {
    var sum: i64 = 0;
    var enable: bool = true;

    const iis: [3][]const u8 = .{ "mul(", "don't()", "do()" };
    var idx: [3]usize = .{ 0, 0, 0 };

    // Incrementally search for instructions.
    for (buff, 0..) |c, buff_i| {
        for (0..iis.len) |i| {
            if (c == iis[i][idx[i]]) {
                idx[i] += 1;
            } else {
                idx[i] = 0;
            }

            if (idx[i] < iis[i].len) continue;
            // Found complete instruction.
            switch (i) {
                0 => if (enable) {
                    sum += parse_mult(buff[buff_i + 1 ..]);
                },
                1 => enable = false,
                2 => enable = true,
                else => unreachable,
            }

            // Reset partially found instructions.
            for (0..idx.len) |_i| idx[_i] = 0;
            break;
        }
    }

    return sum;
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

    // Process all instructions.
    const sum = process_buff(file_buff);
    std.debug.print("{d}\n", .{sum});
}
