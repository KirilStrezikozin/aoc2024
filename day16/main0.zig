const std = @import("std");

const Allocator = std.mem.Allocator;
const Generations = @as(usize, 2000);

const Secret = usize;
const Keep = @as(Secret, 0xffffff);

fn process(_: Allocator, buff: []const u8) !usize {
    var sum: usize = 0;

    var it = std.mem.tokenizeScalar(u8, buff, '\n');
    while (it.next()) |token| {
        var secret = try std.fmt.parseInt(Secret, token, 10);
        // std.debug.print("{d}\n", .{secret});

        for (0..Generations) |_| {
            secret = (secret ^ (secret << 6)) & Keep;
            secret = (secret ^ (secret >> 5)) & Keep;
            secret = (secret ^ (secret << 11)) & Keep;
        }

        // std.debug.print("{d}\n", .{secret});
        sum += secret;
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

    // Process the file.
    const sum = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{sum});
}
