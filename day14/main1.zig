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
const MinSaving = @as(usize, 100);

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

const Cheats = std.AutoHashMap(usize, usize);

fn SortCtx(comptime T: anytype) type {
    return struct {
        const Self = @This();
        values: []const T,
        fn asc(self: Self, lhs: usize, rhs: usize) bool {
            return self.values[lhs] < self.values[rhs];
        }
    };
}

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

fn ccheat(map: Map(u8), ds: Map(usize), chs: *Cheats, y: usize, x: usize) !void {
    const cy_l: usize = if (y < MaxCheat) 0 else y - MaxCheat;
    const cy_r: usize = @min(y + MaxCheat, map.data.len - 1);

    for (cy_l..cy_r + 1) |cy| {
        const cells: usize = MaxCheat - (if (y > cy) y - cy else cy - y);

        const cx_l: usize = if (x < cells) 0 else x - cells;
        const cx_r: usize = @min(x + cells, map.data[y].len - 1);

        for (cx_l..cx_r + 1) |cx| {
            if (ds.data[cy][cx] == MaxUsize) continue; // Not a path.

            const mdist: usize = (if (cy > y) cy - y else y - cy) + (if (cx > x) cx - x else x - cx);
            const nds = ds.data[y][x] + mdist;

            if (ds.data[cy][cx] <= nds) continue; // No cheat advantage.

            const saving: usize = ds.data[cy][cx] - nds;
            if (saving < MinSaving) continue;

            const entry = try chs.getOrPut(saving);
            if (entry.found_existing) {
                entry.value_ptr.* += 1;
            } else {
                entry.value_ptr.* = 1;
            }
        }
    }

    return;
}

fn cheats(ally: Allocator, map: Map(u8), ds: Map(usize)) !usize {
    var chs = Cheats.init(ally);
    defer chs.deinit();

    for (1..map.data.len - 1) |y| {
        for (1..map.data[y].len - 1) |x| {
            if (ds.data[y][x] != MaxUsize) {
                try ccheat(map, ds, &chs, y, x);
            }
        }
    }

    const cap: usize = chs.count();
    var keys = try ally.alloc(usize, cap);
    defer ally.free(keys);
    var values = try ally.alloc(usize, cap);
    defer ally.free(values);
    var indices = try ally.alloc(usize, cap);
    defer ally.free(indices);

    var count: usize = 0;
    var it = chs.iterator();
    var i: usize = 0;
    while (it.next()) |entry| {
        keys[i] = entry.key_ptr.*;
        values[i] = entry.value_ptr.*;
        indices[i] = i;
        i += 1;
    }

    const ctx = SortCtx(usize){ .values = keys };
    std.mem.sort(usize, indices, ctx, SortCtx(usize).asc);

    for (indices) |idx| {
        count += values[idx];
        std.debug.print(
            "There are {d} cheats that save {d} picoseconds.\n",
            .{ values[idx], keys[idx] },
        );
    }

    return count;
}

fn explore(map: Map(u8), ds: Map(usize), y: usize, x: usize, dir_i: usize) void {
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
                explore(map, ds, ny, nx, i);
            },
            Visited, StartTile, EndTile => {
                const nds = ds.data[y][x] + WalkCost;

                // Existing path cheaper, ignore.
                if (ds.data[ny][nx] <= nds) continue;

                ds.data[ny][nx] = nds;
                explore(map, ds, ny, nx, i);
            },
            else => unreachable,
        }
    }
}

fn process(ally: Allocator, buff: []u8) !usize {
    const input = try read_map(ally, buff);
    const startTile = input.s;
    const map = input.m;
    // map.print(.Unicode);

    if (map.data.len == 0) {
        @panic("Invalid map size");
    }

    // Ds is a 2d map of costs that has dimensions similar to map.
    var ds: Map(usize) = undefined;
    try ds.alloc(ally, map.data.len, map.data[0].len);
    defer ds.free(ally);

    for (0..map.data.len) |y| {
        @memset(ds.data[y], MaxUsize);
    }
    ds.data[startTile.y][startTile.x] = 0;

    explore(map, ds, startTile.y, startTile.x, Directions.len);

    // map.print(.Unicode);
    // ds.print(.Numeric);

    return try cheats(ally, map, ds);
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
