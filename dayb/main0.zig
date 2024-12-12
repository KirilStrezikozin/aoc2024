const std = @import("std");

const Allocator = std.mem.Allocator;

const Stone = usize;
const Stones = std.ArrayList(Stone);

fn read_line(ally: *const Allocator, buff: []u8) !Stones {
    var array = try Stones.initCapacity(ally.*, 0);

    var it = std.mem.tokenizeAny(u8, buff, " \n");
    while (it.next()) |token| {
        const num = try std.fmt.parseUnsigned(Stone, token, 10);
        try array.append(num);
    }

    return array;
}

inline fn Ndigits(stone: Stone) usize {
    var n: usize = 1;
    var a = stone / 10;
    while (a > 0) {
        n += 1;
        a /= 10;
    }

    return n;
}

fn blink(stones: *Stones) !void {
    var i: usize = 0;
    while (i < stones.items.len) : (i += 1) {
        if (stones.items[i] == 0) {
            stones.items[i] = 1;
            continue;
        }

        const ndigits = Ndigits(stones.items[i]);
        if (ndigits % 2 == 1) {
            stones.items[i] *= 2024;
            continue;
        }

        const div: usize = std.math.pow(usize, 10, ndigits / 2);
        const numl: Stone = stones.items[i] / div;
        const numr: Stone = stones.items[i] % div;

        stones.items[i] = numl;
        try stones.insert(i + 1, numr);
        i += 1;
    }
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    var stones = try read_line(ally, buff);
    defer stones.deinit();

    for (0..25) |_| {
        try blink(&stones);
    }

    return stones.items.len;
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
    const count = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{count});
}
