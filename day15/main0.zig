const std = @import("std");

const Allocator = std.mem.Allocator;

// 163246 too high.
// 153990 too low.
// 159558

const Code = []const u8;
const Codes = []const Code;

const Location = struct { y: usize, x: usize };

fn Numeric(key: u8) Location {
    const table = [_]Location{
        .{ .y = 3, .x = 1 }, // 0.
        .{ .y = 2, .x = 0 }, // 1.
        .{ .y = 2, .x = 1 }, // 2.
        .{ .y = 2, .x = 2 }, // 3.
        .{ .y = 1, .x = 0 }, // 4.
        .{ .y = 1, .x = 1 }, // 5.
        .{ .y = 1, .x = 2 }, // 6.
        .{ .y = 0, .x = 0 }, // 7.
        .{ .y = 0, .x = 1 }, // 8.
        .{ .y = 0, .x = 2 }, // 9.
        .{ .y = 3, .x = 2 }, // A.
    };

    return switch (key) {
        '0'...'9' => table[key - '0'],
        'A' => table[table.len - 1],
        else => unreachable,
    };
}

fn Directional(key: u8) Location {
    const table = [_]Location{
        .{ .y = 0, .x = 1 }, // ^.
        .{ .y = 1, .x = 0 }, // <.
        .{ .y = 1, .x = 1 }, // v.
        .{ .y = 1, .x = 2 }, // >.
        .{ .y = 0, .x = 2 }, // A.
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

fn process(ally: Allocator, buff: []u8) !usize {
    const codes = try parse(ally, buff);

    var scode = std.ArrayList(u8).init(ally);
    defer scode.deinit();

    var complexity: usize = 0;

    for (codes) |c| {
        std.debug.print("\nCode:\n", .{});

        try scode.resize(c.len);
        @memcpy(scode.items, c);

        for (0..3) |slave_i| {
            const numeric = slave_i == 0;
            var slave = Keypad{
                .numeric = numeric,
                .loc = if (numeric) Numeric('A') else Directional('A'),
            };

            var mcode = std.ArrayList(u8).init(ally);

            std.debug.print("{s}\n", .{scode.items});
            for (scode.items) |skey| {
                const slave_nloc = slave.getKey(skey);

                const xdist: usize, const left: bool = blk: {
                    if (slave_nloc.x > slave.loc.x) {
                        break :blk .{ slave_nloc.x - slave.loc.x, false };
                    } else {
                        break :blk .{ slave.loc.x - slave_nloc.x, true };
                    }
                };

                const ydist: usize, const up: bool = blk: {
                    if (slave_nloc.y > slave.loc.y) {
                        break :blk .{ slave_nloc.y - slave.loc.y, false };
                    } else {
                        break :blk .{ slave.loc.y - slave_nloc.y, true };
                    }
                };

                // if (numeric and !up) {
                //     try mcode.appendNTimes(if (left) '<' else '>', xdist);
                //     try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                // } else if (numeric and up) {
                //     try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                //     try mcode.appendNTimes(if (left) '<' else '>', xdist);
                // } else if (!up) {
                //     try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                //     try mcode.appendNTimes(if (left) '<' else '>', xdist);
                // } else {
                //     try mcode.appendNTimes(if (left) '<' else '>', xdist);
                //     try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                // }

                if (false) {
                    try mcode.appendNTimes(if (left) '<' else '>', xdist);
                    try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                } else {
                    try mcode.appendNTimes(if (up) '^' else 'v', ydist);
                    try mcode.appendNTimes(if (left) '<' else '>', xdist);
                }

                try mcode.append('A');
                slave.loc = slave_nloc;
            }

            try scode.resize(mcode.items.len);
            std.debug.print("new code len={d}\n", .{mcode.items.len});
            @memcpy(scode.items, mcode.items);
            mcode.deinit();
        }
        std.debug.print("{s}\n", .{scode.items});

        const local_complexity = try std.fmt.parseInt(usize, c[0 .. c.len - 1], 10) * scode.items.len;
        std.debug.print(
            "Complexity: {d}*{d}={d}\n",
            .{
                try std.fmt.parseInt(usize, c[0 .. c.len - 1], 10),
                scode.items.len,
                local_complexity,
            },
        );

        complexity += local_complexity;
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
