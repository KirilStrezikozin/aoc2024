const std = @import("std");

const Allocator = std.mem.Allocator;

const Stone = usize;
const Lookup = std.AutoHashMap(struct { num: Stone, decade: usize }, usize);

const StopAtDecade: usize = 75;

fn read_line(ally: *const Allocator, buff: []u8) ![]Stone {
    var array = std.ArrayList(Stone).init(ally.*);
    defer array.deinit();

    var it = std.mem.tokenizeAny(u8, buff, " \n");
    while (it.next()) |token| {
        const num = try std.fmt.parseUnsigned(Stone, token, 10);
        try array.append(num);
    }

    return array.toOwnedSlice();
}

inline fn Ndigits(stone: Stone) usize {
    var n: usize = 1;
    var d: usize = 10;
    while (d < stone) {
        n += 1;
        d *= 10;
    }

    return n;
}

fn Ncount(num: Stone, decade: usize, lookup: *Lookup) !usize {
    if (lookup.get(.{ .num = num, .decade = decade })) |count| return count;

    if (decade == 0) {
        try lookup.put(.{ .num = num, .decade = 0 }, 1);
        return 1;
    }

    if (num == 0) {
        const count = try Ncount(1, decade - 1, lookup);
        try lookup.put(.{ .num = num, .decade = decade }, count);
        return count;
    }

    const ndigits = Ndigits(num);
    if (ndigits % 2 == 1) {
        const count = try Ncount(num * 2024, decade - 1, lookup);
        try lookup.put(.{ .num = num, .decade = decade }, count);
        return count;
    }

    const div: usize = std.math.pow(usize, 10, ndigits / 2);
    const numl: Stone = num / div;
    const numr: Stone = num % div;

    const count = try Ncount(numl, decade - 1, lookup) + try Ncount(numr, decade - 1, lookup);
    try lookup.put(.{ .num = num, .decade = decade }, count);
    return count;
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    const stones = try read_line(ally, buff);

    var lookup = Lookup.init(ally.*);
    defer lookup.deinit();

    var sum: usize = 0;
    for (stones) |stone| {
        const count = try Ncount(stone, StopAtDecade, &lookup);
        sum += count;
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
    const sum = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{sum});

    // std.debug.print("{d}\n", .{Ndigits(1)});
    // std.debug.print("{d}\n", .{Ndigits(10)});
    // std.debug.print("{d}\n", .{Ndigits(999)});
    // std.debug.print("{d}\n", .{Ndigits(20245)});
    // std.debug.print("{d}\n", .{Ndigits(6666)});
    // std.debug.print("{d}\n", .{Ndigits(23)});
}
