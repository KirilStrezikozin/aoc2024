const std = @import("std");

const Allocator = std.mem.Allocator;

const Costs = [][]usize;

const Location = struct { x: usize, y: usize };

const Direction = struct { dx: i64, dy: i64 };
const Directions = [_]Direction{
    .{ .dy = -1, .dx = 0 }, // Up.
    .{ .dy = 0, .dx = 1 }, // Right.
    .{ .dy = 0, .dx = -1 }, // Left.
    .{ .dy = 1, .dx = 0 }, // Down.
};

const StartTile = 'S';
const EndTile = 'E';
const Wall = '#';
const Empty = '.';
const Visited = 'O';

const MaxUsize = std.math.maxInt(usize);
const WalkCost = @as(usize, 1);
const MaxCheat = @as(usize, 20);

const PrintType = enum {
    Unicode,
    Numeric,
};

/// Creates a new map type.
/// Call free with the result to free the memory unless the
/// underlying map's data is managed externally.
fn Map(comptime T: type) type {
    return struct {
        const Self = @This();

        data: [][]T,

        /// Allocates map data with the given height and width.
        fn alloc(self: *Self, ally: Allocator, height: usize, width: usize) !void {
            self.data = try ally.alloc([]T, height);
            for (0..self.data.len) |i| {
                self.data[i] = try ally.alloc(T, width);
            }
        }

        /// Frees map data.
        fn free(self: *Self, ally: Allocator) void {
            for (0..self.data.len) |i| {
                ally.free(self.data[i]);
            }
            ally.free(self.data);
        }

        /// Print the contents of the map to standard output for debugging.
        fn print(self: *Self, comptime pt: PrintType) void {
            for (self.data) |row| {
                for (row) |val| switch (pt) {
                    .Unicode => {
                        if (@TypeOf(val) != u8) {
                            @compileError("Expected type 'u8', found 'usize'");
                        }
                        std.debug.print("{s}", .{[_]u8{ val, 0 }});
                    },
                    .Numeric => {
                        if (val != MaxUsize) {
                            std.debug.print("{:05} ", .{val});
                            continue;
                        }

                        std.debug.print("##### ", .{});
                    },
                };
                std.debug.print("\n", .{});
            }
        }
    };
}

const Cheat = std.ArrayList(usize);
const Cheats = Map(Cheat);

/// Returns a 2d view onto the given file buffer, split by newline characters.
/// And a byte offset to continue reading from.
fn read_map(ally: Allocator, b: []u8) !struct { m: Map(u8), s: Location, e: Location } {
    var array = std.ArrayList([]u8).init(ally);
    defer array.deinit();

    var s: Location = undefined;
    var e: Location = undefined;

    // x, y positions for bytes in the given buff.
    var row_i: usize = 0;
    var col_i: usize = 0;

    var row_start: usize = 0;
    for (b, 0..) |c, i| {
        switch (c) {
            '\n' => {
                try array.append(b[row_start..i]);
                row_start = i + 1;
                row_i += 1;
                col_i = 0;
                continue;
            },
            StartTile => {
                s.y = row_i;
                s.x = col_i;
            },
            EndTile => {
                e.y = row_i;
                e.x = col_i;
                col_i += 1;
            },
            else => {},
        }

        col_i += 1;
    }

    if (row_start < b.len) { // No final newline.
        try array.append(b[row_start..]);
    }

    const map = Map(u8){ .data = try array.toOwnedSlice() };
    return .{ .m = map, .s = s, .e = e };
}

fn explore_cheat(map: Map(u8), d: usize, cs: Cheats, y: usize, x: usize, dir_i: usize, n: usize) !void {
    if (n > MaxCheat) return;

    for (0..Directions.len) |i| {
        // Cannot follow the direction it came from.
        if ((dir_i < Directions.len) and (i == Directions.len - dir_i - 1)) continue;

        const ny: usize = @intCast(@as(i64, @intCast(y)) + Directions[i].dy);
        const nx: usize = @intCast(@as(i64, @intCast(x)) + Directions[i].dx);

        if ((nx == 0) or (nx == map.data[ny].len - 1) or
            (ny == 0) or (ny == map.data.len - 1))
        {
            continue;
        }

        const ncs = d + WalkCost * n;
        try cs.data[ny][nx].append(ncs);

        try explore_cheat(map, d, cs, ny, nx, i, n + 1);
    }
}

fn explore(map: Map(u8), ds: Map(usize), cs: Cheats, y: usize, x: usize, dir_i: usize) !void {
    try explore_cheat(map, map.data[y][x], cs, y, x, Directions.len, 0);

    for (0..Directions.len) |i| {
        // Cannot follow the direction it came from.
        if ((dir_i < Directions.len) and (i == Directions.len - dir_i - 1)) continue;

        const ny_int: i64 = @as(i64, @intCast(y)) + Directions[i].dy;
        const nx_int: i64 = @as(i64, @intCast(x)) + Directions[i].dx;

        const ny: usize = @intCast(ny_int);
        const nx: usize = @intCast(nx_int);

        switch (map.data[ny][nx]) {
            Wall => continue,
            Empty => {
                map.data[ny][nx] = Visited;
                ds.data[ny][nx] = ds.data[y][x] + WalkCost;
                try explore(map, ds, cs, ny, nx, i);
            },
            Visited, StartTile, EndTile => {
                const nds = ds.data[y][x] + WalkCost;

                // Existing path cheaper, ignore.
                if (ds.data[ny][nx] <= nds) continue;

                ds.data[ny][nx] = nds;
                try explore(map, ds, cs, ny, nx, i);
            },
            else => unreachable,
        }
    }
}

fn process(ally: Allocator, buff: []u8) !usize {
    const input = try read_map(ally, buff);
    const startTile = input.s;
    var map = input.m;
    map.print(.Unicode);

    if (map.data.len == 0) {
        @panic("Invalid map size");
    }

    // Ds is a 2d map of costs that has dimensions similar to map.
    var ds: Map(usize) = undefined;
    try ds.alloc(ally, map.data.len, map.data[0].len);
    defer ds.free(ally);

    // Cs s a 2d map of costs enabled by cheating.
    var cs: Cheats = undefined;
    try cs.alloc(ally, map.data.len, map.data[0].len);
    defer cs.free(ally);

    for (0..map.data.len) |y| {
        @memset(ds.data[y], MaxUsize);
        for (0..map.data[y].len) |x| {
            cs.data[y][x] = try Cheat.initCapacity(ally, 10);
        }
    }
    ds.data[startTile.y][startTile.x] = 0;

    std.debug.print("start tile at {any}\n", .{startTile});
    try explore(map, ds, cs, startTile.y, startTile.x, Directions.len);

    map.print(.Unicode);
    ds.print(.Numeric);
    // std.debug.print("\nCheat map:\n", .{});
    // cs.print(.Numeric);

    var savings = std.ArrayList(usize).init(ally);
    defer savings.deinit();

    // Calculate savings from the pre-calculated map of cheats.

    var count: usize = 0;
    for (0..map.data.len) |y| {
        for (0..map.data[y].len) |x| {
            for (cs.data[y][x].items) |cheat| {
                const d = ds.data[y][x];
                if (d <= cheat) continue;

                const saving = d - cheat;
                if (saving >= 50) {
                    count += 1;
                    try savings.append(saving);
                }
            }
        }
    }

    std.mem.sort(usize, savings.items, {}, comptime std.sort.desc(usize));
    std.debug.print("\nCheats:\n", .{});
    var last_saving: usize = 0;
    var this_savings: usize = 1;
    for (savings.items) |saving| {
        if (saving == last_saving) {
            this_savings += 1;
            continue;
        }

        if (last_saving != 0) {
            std.debug.print("There are {d} cheats that save {d} picoseconds.\n", .{ this_savings, last_saving });
        }
        last_saving = saving;
        this_savings = 1;
    }
    std.debug.print("There are {d} cheats that save {d} picoseconds.\n", .{ this_savings, last_saving });

    return count;
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
    const cost = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{cost});
}
