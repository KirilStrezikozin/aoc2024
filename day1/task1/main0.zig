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

    var line_count: usize = 0;
    while (try reader.readUntilDelimiterOrEof(&line_buff, '\n')) |line| {
        if (line.len == 0) break;
        line_count += 1;
    }

    try file.seekTo(0);

    var array1 = try pg_ally.alloc(i64, line_count);
    var array2 = try pg_ally.alloc(i64, line_count);
    defer pg_ally.free(array1);
    defer pg_ally.free(array2);

    var _i: usize = 0;
    while (try reader.readUntilDelimiterOrEof(&line_buff, '\n')) |line| {
        if (line.len == 0) break;

        var pair_i: usize = 0;
        var it = std.mem.tokenizeAny(u8, &line_buff, " \t\n");
        while (true) {
            if (pair_i >= 2) {
                break;
            }

            const num = it.next() orelse break;
            const n = try std.fmt.parseInt(i64, num, 10);

            if (pair_i == 0) {
                array1[_i] = n;
            } else {
                array2[_i] = n;
            }
            pair_i += 1;
        }

        _i += 1;
    }

    // Sorting both arrays.
    std.mem.sort(i64, array1, {}, comptime std.sort.asc(i64));
    std.mem.sort(i64, array2, {}, comptime std.sort.asc(i64));

    var distance: i64 = 0;
    for (0..line_count) |__i| {
        // std.debug.print("{d} {d}\n", .{ array1[__i], array2[__i] });
        if (array1[__i] > array2[__i]) {
            distance += array1[__i] - array2[__i];
        } else {
            distance += array2[__i] - array1[__i];
        }
    }

    // Print final result.
    std.debug.print("{d}\n", .{distance});
}
