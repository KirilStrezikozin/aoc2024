const std = @import("std");

const Allocator = std.mem.Allocator;

const Location = struct { y: usize, x: usize };
const Directions = [_]struct { dy: i64, dx: i64 }{
    .{ .dy = -1, .dx = 0 }, // Up.
    .{ .dy = 0, .dx = 1 }, // Right.
    .{ .dy = 0, .dx = -1 }, // Left.
    .{ .dy = 1, .dx = 0 }, // Down.
};

const MapHeight = @as(usize, 71);
const MapWidth = MapHeight;

const MapCell = enum(u8) {
    Empty = '.',
    Obstacle = '#',
    Visited = 'O',
};

const PrintType = enum {
    Unicode,
    Numeric,
};

const MaxUsize = std.math.maxInt(usize);

/// Creates a new Map type to hold the current memory map.
/// Call free with the result to free the memory.
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
        fn print(self: *Self, pt: PrintType) void {
            for (self.data) |row| {
                for (row) |val| switch (pt) {
                    .Numeric => std.debug.print("{any} ", .{val}),
                    .Unicode => {
                        const s = switch (@typeInfo(T)) {
                            .Enum => @intFromEnum(val),
                            else => val,
                        };
                        std.debug.print("{s}", .{[_]u8{ s, 0 }});
                    },
                };
                std.debug.print("\n", .{});
            }
        }
    };
}

/// Returns a slice of integer pairs parsed from input buff.
fn parse(ally: Allocator, buff: []u8) ![]Location {
    var array = std.ArrayList(Location).init(ally);
    defer array.deinit();

    var lineIt = std.mem.tokenizeScalar(u8, buff, '\n');
    var lineI = @as(usize, 0);
    while (lineIt.next()) |line| : (lineI += 1) {
        var it = std.mem.splitScalar(u8, line, ',');
        const x = try std.fmt.parseInt(usize, it.next().?, 10);
        const y = try std.fmt.parseInt(usize, it.next().?, 10);

        try array.append(.{ .y = y, .x = x });
    }

    return try array.toOwnedSlice();
}

fn explore(map: *Map(MapCell), ds: *Map(usize), y: usize, x: usize, dir_i: usize) void {
    for (0..Directions.len) |i| {
        // Cannot follow the direction it came from.
        if ((dir_i < Directions.len) and (i == Directions.len - dir_i - 1)) continue;

        const nyi: i64 = @as(i64, @intCast(y)) + Directions[i].dy;
        const nxi: i64 = @as(i64, @intCast(x)) + Directions[i].dx;
        if ((nxi < 0) or (nxi >= map.data[y].len) or (nyi < 0) or (nyi >= map.data.len)) continue;
        const ny: usize = @intCast(nyi);
        const nx: usize = @intCast(nxi);

        switch (map.data[ny][nx]) {
            .Obstacle => continue,
            .Empty => {
                map.data[ny][nx] = .Visited;
                ds.data[ny][nx] = ds.data[y][x] + 1;
                explore(map, ds, ny, nx, i);
            },
            .Visited => {
                const nds = ds.data[y][x] + 1;

                // Existing path cheaper, ignore.
                if (ds.data[ny][nx] <= nds) continue;

                ds.data[ny][nx] = nds;
                explore(map, ds, ny, nx, i);
            },
        }
    }
}

fn process(ally: Allocator, buff: []u8) !Location {
    var map: Map(MapCell) = undefined;
    try map.alloc(ally, MapHeight, MapWidth);
    defer map.free(ally);

    var ds: Map(usize) = undefined;
    try ds.alloc(ally, MapHeight, MapWidth);
    defer ds.free(ally);

    const obs = try parse(ally, buff);
    var limit_upper: usize = obs.len;
    var limit_lower: usize = 0;

    // Binary search the first obstacle at which the path is fully blocked.
    while (limit_upper - limit_lower > 1) {
        const obs_limit: usize = (limit_lower + limit_upper) / 2;
        std.debug.print("Up to coordinate {any} at {d}/{d}, blocked: ", .{ obs[obs_limit], obs_limit, obs.len - 1 });

        // Reset distances and visited cells.
        for (0..ds.data.len) |i| {
            @memset(map.data[i], .Empty);
            @memset(ds.data[i], MaxUsize);
        }
        ds.data[0][0] = 0;

        for (0..obs_limit + 1) |i| {
            const ob = obs[i];
            map.data[ob.y][ob.x] = .Obstacle;
        }

        explore(&map, &ds, 0, 0, Directions.len);

        const blocked = ds.data[MapHeight - 1][MapWidth - 1] == MaxUsize;
        std.debug.print("{}\n", .{blocked});

        if (blocked) {
            limit_upper = obs_limit;
        } else {
            limit_lower = obs_limit;
        }
    }

    return obs[limit_upper];
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
    const loc = try process(pg_ally, file_buff);
    std.debug.print("{any}\n", .{loc});
}
