const std = @import("std");

const Allocator = std.mem.Allocator;

// 163246 too high.
// 153990 too low.
// 159558
// 150302

const Code = []const u8;
const Codes = []const Code;

const Location = struct { y: usize, x: usize };

fn Numeric(key: u8) Location {
    const table = [_]Location{
        .{ .y = 0, .x = 1 }, // 0.
        .{ .y = 1, .x = 0 }, // 1.
        .{ .y = 1, .x = 1 }, // 2.
        .{ .y = 1, .x = 2 }, // 3.
        .{ .y = 2, .x = 0 }, // 4.
        .{ .y = 2, .x = 1 }, // 5.
        .{ .y = 2, .x = 2 }, // 6.
        .{ .y = 3, .x = 0 }, // 7.
        .{ .y = 3, .x = 1 }, // 8.
        .{ .y = 3, .x = 2 }, // 9.
        .{ .y = 0, .x = 2 }, // A.
    };

    return switch (key) {
        '0'...'9' => table[key - '0'],
        'A' => table[table.len - 1],
        else => unreachable,
    };
}

fn Directional(key: u8) Location {
    const table = [_]Location{
        .{ .y = 1, .x = 1 }, // ^.
        .{ .y = 0, .x = 0 }, // <.
        .{ .y = 0, .x = 1 }, // v.
        .{ .y = 0, .x = 2 }, // >.
        .{ .y = 1, .x = 2 }, // A.
    };

    return switch (key) {
        '^' => table[0],
        '<' => table[1],
        'v' => table[2],
        '>' => table[3],
        'A' => table[4],
        else => unreachable,
    };
}

const Keypad = struct {
    const Self = @This();

    numeric: bool = false,
    loc: Location = undefined,

    inline fn getKey(self: *Self, key: u8) Location {
        return if (self.numeric) Numeric(key) else Directional(key);
    }

    inline fn moveTo(self: *Self, key: u8) void {
        self.loc = if (self.numeric) Numeric(key) else Directional(key);
    }
};

/// Returns a 2d view onto the given buffer, split by newline characters.
/// Clients own the returned memory.
fn parse(ally: Allocator, buff: []u8) !Codes {
    var array = std.ArrayList(Code).init(ally);
    defer array.deinit();

    var it = std.mem.tokenizeScalar(u8, buff, '\n');
    while (it.next()) |token| {
        try array.append(token);
    }

    return try array.toOwnedSlice();
}

fn buildCode(ally: Allocator, code: []const u8, numeric: bool) ![]const u8 {
    var slave = Keypad{
        .numeric = numeric,
        .loc = if (numeric) Numeric('A') else Directional('A'),
    };

    var mcode = std.ArrayList(u8).init(ally);
    defer mcode.deinit();

    for (code) |skey| {
        const slave_nloc = slave.getKey(skey);

        const xdist: usize, const left: bool = blk: {
            if (slave_nloc.x >= slave.loc.x) {
                break :blk .{ slave_nloc.x - slave.loc.x, false };
            } else {
                break :blk .{ slave.loc.x - slave_nloc.x, true };
            }
        };

        const ydist: usize, const up: bool = blk: {
            if (slave_nloc.y >= slave.loc.y) {
                break :blk .{ slave_nloc.y - slave.loc.y, true };
            } else {
                break :blk .{ slave.loc.y - slave_nloc.y, false };
            }
        };

        if (numeric) {
            std.debug.print("{d} (left is {}) {d}\n", .{ xdist, left, ydist });
        }

        // Prioritize lest turns and < over ^ over v over >.

        if (numeric) {
            if ((slave.loc.y == 0) and (slave_nloc.x == 0)) {
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
            } else if ((slave.loc.x == 0) and (slave_nloc.y == 0)) {
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
            } else if (left) {
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
            } else {
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
            }
        } else {
            if ((slave.loc.x == 0) and (slave_nloc.y == 1)) {
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
            } else if ((slave.loc.y == 1) and (slave_nloc.x == 0)) {
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
            } else if (left) {
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
            } else {
                try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                try mcode.appendNTimes(if (left) '<' else '>', xdist);
            }
        }

        try mcode.append('A');
        slave.loc = slave_nloc;
    }

    if (numeric) {
        std.debug.print("{s}\n", .{mcode.items});
    }
    return try mcode.toOwnedSlice();
}

const MaxDepth: usize = 25;
const Cache = std.StringHashMap([MaxDepth]usize);

fn splitCode(ally: Allocator, code: []const u8) ![]const []const u8 {
    var array = std.ArrayList([]const u8).init(ally);
    defer array.deinit();

    var l: usize = 0;
    for (0..code.len) |r| {
        if (code[r] == 'A') {
            try array.append(code[l .. r + 1]);
            l = r + 1;
        }
    }

    return try array.toOwnedSlice();
}

fn robotics(ally: Allocator, code: []const u8, depth: usize, cache: *Cache) !usize {
    if (cache.get(code)) |cached| {
        if (cached[depth - 1] != 0) return cached[depth - 1];
    } else {
        try cache.put(code, .{0} ** MaxDepth);
    }

    const mcode = try buildCode(ally, code, false);
    defer ally.free(mcode);

    {
        var entry = cache.get(code).?;
        entry[0] = mcode.len;
    }

    if (depth == MaxDepth) return mcode.len;

    std.debug.print("{d} {d} {d}\n", .{ depth, cache.count(), mcode.len });

    var complexity: usize = 0;
    const mmcodes = try splitCode(ally, mcode);
    defer ally.free(mmcodes);

    for (mmcodes) |mmcode| {
        const local_complexity = try robotics(ally, mmcode, depth + 1, cache);

        if (cache.get(mmcode) == null) {
            try cache.put(mmcode, .{0} ** MaxDepth);
        }

        var mentry = cache.get(mmcode).?;
        mentry[0] = local_complexity;
        complexity += local_complexity;
    }

    {
        var entry = cache.get(code).?;
        entry[depth - 1] = complexity;
    }

    return complexity;
}

fn process(ally: Allocator, buff: []u8) !usize {
    const codes = try parse(ally, buff);

    var cache = Cache.init(ally);
    defer cache.deinit();

    var complexity: usize = 0;

    for (codes) |code| {
        const mcode = try buildCode(ally, code, true);
        const local_complexity = try robotics(ally, mcode, 1, &cache);

        const code_numeric = try std.fmt.parseInt(usize, code[0 .. code.len - 1], 10);
        complexity += code_numeric * local_complexity;
    }

    return complexity;
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
    const complexity = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{complexity});
}
