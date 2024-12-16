const std = @import("std");

const Allocator = std.mem.Allocator;

const Map = [][]u8;
const Costs = [][]usize;

const Location = struct { x: usize, y: usize };

const Direction = struct { dx: i64, dy: i64 };
const DirectionTag = enum(usize) {
    Up,
    Right,
    Left,
    Down,
};

const Directions = [_]Direction{
    .{ .dy = -1, .dx = 0 }, // Up.
    .{ .dy = 0, .dx = 1 }, // Right.
    .{ .dy = 0, .dx = -1 }, // Left.
    .{ .dy = 1, .dx = 0 }, // Down.
};

const Reindeer = struct {
    loc: Location,
    dir: DirectionTag,
};

const StartTile = 'S';
const EndTile = 'E';
const Wall = '#';
const Empty = '.';
const Visited = 'O';

const MaxUsize = std.math.maxInt(usize);

const TurnCost = @as(usize, 1000);

/// Prints the map contents to the standard output.
inline fn print_map(map: Map) void {
    for (map) |row| {
        for (row) |c| {
            std.debug.print("{s}", .{[_]u8{ c, 0 }});
        }
        std.debug.print("\n", .{});
    }
}

/// Returns a 2d view onto the given file buffer, split by newline characters.
/// And a byte offset to continue reading from.
fn read_map(ally: Allocator, b: []u8) !struct { m: Map, s: Location, e: Location } {
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
            },
            StartTile => {
                s.y = row_i;
                s.x = col_i;
                col_i += 1;
            },
            EndTile => {
                e.y = row_i;
                e.x = col_i;
                col_i += 1;
            },
            else => col_i += 1,
        }
    }

    if (row_start < b.len) { // No final newline.
        try array.append(b[row_start..]);
    }

    return .{ .m = try array.toOwnedSlice(), .s = s, .e = e };
}

/// Allocate a 2d slice with element type T and dimensions similar to trait Map.
fn alloc_map(comptime T: anytype, ally: Allocator, trait: Map) ![][]T {
    var ds = try ally.alloc([]T, trait.len);
    for (0..ds.len) |i| {
        ds[i] = try ally.alloc(T, trait[i].len);
    }
    return ds;
}

/// Free a 2d slice allocated by alloc_map.
fn free_map(comptime T: anytype, ally: Allocator, map: [][]T) void {
    for (0..map.len) |i| {
        ally.free(map[i]);
    }
    ally.free(map);
}

fn turn_cost(dir_i_a: usize, dir_i_b: usize) usize {
    if (dir_i_a == dir_i_b) return 0;
    const ddx: usize = @abs(Directions[dir_i_a].dx - Directions[dir_i_b].dx);
    const ddy: usize = @abs(Directions[dir_i_a].dy - Directions[dir_i_b].dy);
    return @max(ddx, ddy) * TurnCost;
}

fn explore(map: Map, ds: Costs, y: usize, x: usize, dir_i: usize) void {
    for (0..Directions.len) |i| {
        // Cannot follow the direction it came from.
        if (i == Directions.len - dir_i - 1) continue;

        const ny: usize = @intCast(@as(i64, @intCast(y)) + Directions[i].dy);
        const nx: usize = @intCast(@as(i64, @intCast(x)) + Directions[i].dx);

        switch (map[ny][nx]) {
            Wall => continue,
            Empty => {
                map[ny][nx] = Visited;
                ds[ny][nx] = ds[y][x] + 1 + turn_cost(dir_i, i);
                explore(map, ds, ny, nx, i);
            },
            Visited, StartTile, EndTile => {
                const nds = ds[y][x] + 1 + turn_cost(dir_i, i);

                // Existing path cheaper, ignore.
                if (ds[ny][nx] <= nds) continue;

                ds[ny][nx] = nds;
                explore(map, ds, ny, nx, i);
            },
            else => unreachable,
        }
    }
}

fn trace(map: Map, ds: Costs, y: usize, x: usize, carry: usize, sum: usize) usize {
    var nsum = sum;
    for (0..Directions.len) |i| {
        const ny: usize = @intCast(@as(i64, @intCast(y)) + Directions[i].dy);
        const nx: usize = @intCast(@as(i64, @intCast(x)) + Directions[i].dx);

        const curr = ds[y][x];
        const new = ds[ny][nx];
        var ncarry = carry;

        if ((map[ny][nx] == Wall) or (curr == 0) or (new == 0)) continue;

        if ((new + 1 == curr) or (new + 1 == carry)) {
            ncarry = new;
        } else if (new + 1 + TurnCost == curr) {
            ncarry = curr - 1;
        } else continue;

        nsum = trace(map, ds, ny, nx, ncarry, nsum);
    }

    if (map[y][x] == Visited) return nsum;
    map[y][x] = Visited;
    return nsum; // + 1;
}

fn process(ally: Allocator, buff: []u8) !usize {
    const input = try read_map(ally, buff);
    const startTile = input.s;
    const endTile = input.e;

    const map = input.m;
    const r: Reindeer = .{ .loc = startTile, .dir = .Right };

    // ds is a 2d map of costs that has dimensions similar to map.
    var ds: Costs = try alloc_map(usize, ally, map);
    defer free_map(usize, ally, ds);

    // Allocate a trail map to visualize best paths.
    const trails = try alloc_map(u8, ally, map);
    defer free_map(u8, ally, trails);

    // Initialize ds and copy map over to trails.
    for (0..map.len) |i| {
        @memset(ds[i], MaxUsize);
        @memcpy(trails[i], map[i]);
    }
    ds[r.loc.y][r.loc.x] = 0;

    // Launch path exploration to calculate costs.
    explore(map, ds, r.loc.y, r.loc.x, @intFromEnum(r.dir));

    // Trace back the best trails.
    _ = trace(trails, ds, endTile.y, endTile.x, map[endTile.y][endTile.x], 0);

    print_map(trails);
    for (ds) |row| {
        for (row) |d| {
            if (d == MaxUsize) {
                std.debug.print("##### ", .{});
                continue;
            }
            std.debug.print("{:05} ", .{d});
        }
        std.debug.print("\n", .{});
    }

    var rcount: usize = 1;
    for (trails) |row| {
        for (row) |t| if (t == Visited) {
            rcount += 1;
        };
    }

    return rcount;
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
    const count = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{count});
}
