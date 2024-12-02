const std = @import("std");

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

    var reader = file.reader();
    var line_buff: [1024]u8 = undefined;

    var safety: usize = 0;
    var line_i: usize = 0;

    const min_diff: i64 = 1;
    const max_diff: i64 = 3;

    while (try reader.readUntilDelimiterOrEof(&line_buff, '\n')) |line| {
        if (line.len == 0) break;

        var n_prev: i64 = -1;
        var direction: i8 = 0; // down (-1), no (0), up (1).

        std.debug.print("\n", .{});
        std.debug.print("{s}\n", .{line});

        var it = std.mem.tokenizeAny(u8, line, " \t\n");
        while (true) {
            const token = it.next() orelse break;
            if (token.len == 0) {
                // Potential line break.
                std.debug.print("line break\n", .{});
                break;
            }

            const n = try std.fmt.parseInt(i64, token, 10);
            std.debug.print("{d} {d} '{s}' ", .{ n_prev, n, token });
            if (n_prev == -1) {
                std.debug.print("- first number\n", .{});
                // First number in line.
                n_prev = n;
                continue;
            }

            var local_direction: i8 = 0;
            var local_diff: i64 = 0;
            if (n > n_prev) {
                local_direction = 1;
                local_diff = n - n_prev;
            } else if (n_prev < n) {
                local_direction = -1;
                local_diff = n_prev - n;
            } else {
                // Same numbers, unsafe.
                std.debug.print("same numbers\n", .{});
                break;
            }

            if (direction == 0) {
                direction = local_direction;
            } else if (local_direction != direction) {
                // Unstable direction, unsafe.
                std.debug.print("direction\n", .{});
                break;
            }

            if ((min_diff < local_diff) or (local_diff > max_diff)) {
                // Unstable difference, unsafe.
                std.debug.print("diff\n", .{});
                break;
            }

            safety += 1;
        }

        line_i += 1;
    }

    // Print final result.
    std.debug.print("{d}\n", .{safety});
}
