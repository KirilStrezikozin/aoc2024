const std = @import("std");

const Allocator = std.mem.Allocator;

const Empty = '.';
const Mark = 'X';
const Obstacle = '#';
const RetroEncabulator = 'O'; // Historians' new obstacle.

/// Direction is a (dx, dy) difference to apply to a (x, y) point.
const Direction = struct {
    dx: i64 = 0,
    dy: i64 = 0,

    /// Returns true if both Directions are identical.
    inline fn isEqual(self: *const Direction, other: *const Direction) bool {
        return ((self.dx == other.dx) and (self.dy == other.dy));
    }
};

/// Point is a (x, y) mapping on a 2d coordinate system.
const Point = struct { x: usize = undefined, y: usize = undefined };

const Map = [][]u8;
const Obstacles = std.AutoHashMap(
    Point,
    struct { visited: bool, direction: Direction },
);

/// Guard is an entity that walks the Map.
const Guard = struct {
    x: usize,
    y: usize,
    direction: Direction,

    /// Guard with a default position.
    const default: Guard = .{
        .x = 0,
        .y = 0,
        .direction = .{ .dx = 0, .dy = 0 },
    };

    /// Move this Guard according to its direction.
    fn move(self: *Guard) void {
        const new_x: i64 = self.direction.dx + @as(i64, @intCast(self.x));
        const new_y: i64 = self.direction.dy + @as(i64, @intCast(self.y));

        self.x = @as(usize, @intCast(new_x));
        self.y = @as(usize, @intCast(new_y));
    }

    /// Move to the specified (x, y) coordinate.
    inline fn moveTo(self: *Guard, x: usize, y: usize) void {
        self.x = x;
        self.y = y;
    }

    /// Returns the location of the value that the Guard is currently facing or
    /// null if that location is invalid.
    fn face(self: *Guard, map: Map) ?Point {
        const new_ix: i64 = self.direction.dx + @as(i64, @intCast(self.x));
        const new_iy: i64 = self.direction.dy + @as(i64, @intCast(self.y));

        if ((new_ix < 0) or (new_iy < 0)) return null;

        const new_x = @as(usize, @intCast(new_ix));
        const new_y = @as(usize, @intCast(new_iy));

        if ((new_x >= map[self.y].len) or (new_y >= map.len)) return null;

        return .{ .x = new_x, .y = new_y };
    }

    /// Turns the Guard's walking direction by 90 degrees clockwise.
    inline fn turn_90(self: *Guard) void {
        const dy = self.direction.dy;
        const dx = self.direction.dx;

        if (dy == 0) {
            self.direction.dx = dy;
            self.direction.dy = dx;
        } else {
            self.direction.dx -= dy;
            self.direction.dy -= dy;
        }
    }
};

/// Positions the given Guard struct in the starting position found on the map.
/// Fills a hash map with all obstacle locations.
/// Returns a 2d view onto the given file buffer, split by newline characters.
fn read_map(ally: *const Allocator, b: []u8, guard: *Guard, obstacles: *Obstacles) !Map {
    var array = std.ArrayList([]u8).init(ally.*);
    defer array.deinit();

    // x, y positions for bytes in the given buff.
    var row_i: usize = 0;
    var col_i: usize = 0;

    var row_start: usize = 0;
    const last_i: usize = b.len - 1;
    for (b, 0..) |c, i| {
        switch (c) {
            '\n' => {
                try array.append(b[row_start..i]);
                row_start = i + 1;
                row_i += 1;
                col_i = 0;
                continue;
            },
            '^' => {
                guard.moveTo(col_i, row_i);
                guard.direction = .{ .dx = 0, .dy = -1 };
            },
            '>' => {
                guard.moveTo(col_i, row_i);
                guard.direction = .{ .dx = 1, .dy = 0 };
            },
            'v' => {
                guard.moveTo(col_i, row_i);
                guard.direction = .{ .dx = 0, .dy = 1 };
            },
            '<' => {
                guard.moveTo(col_i, row_i);
                guard.direction = .{ .dx = -1, .dy = 0 };
            },
            Obstacle => try obstacles.put(
                .{ .x = col_i, .y = row_i },
                .{ .visited = false, .direction = undefined },
            ),
            Empty => {},
            else => unreachable,
        }

        col_i += 1;
        if (i == last_i) { // No final newline.
            try array.append(b[row_start..]);
        }
    }

    return array.toOwnedSlice();
}

/// Returns all possible (x, y) locations for the RetroEncabulator obstacle.
/// It overwrites the contents of given Map and Guard. Client's are responsible
/// for providing copies of these values if needed.
fn read_re(ally: *const Allocator, map: Map, guard: *Guard) ![]Point {
    var array = std.ArrayList(Point).init(ally.*);
    defer array.deinit();

    // Mark initial position as visited, but do not add it to the list of
    // possible RetroEncabulator locations.
    map[guard.y][guard.x] = Mark;

    while (true) {
        if (guard.face(map)) |point| switch (map[point.y][point.x]) {
            Obstacle, RetroEncabulator => guard.turn_90(),
            Mark => guard.move(),
            else => {
                guard.move();
                map[guard.y][guard.x] = Mark;
                try array.append(.{ .y = guard.y, .x = guard.x });
            },
        } else break; // Beyond the map.
    }

    return array.toOwnedSlice();
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    // Working map, guard, and obstacles.
    var guard = Guard.default;

    var obstacles = Obstacles.init(ally.*);
    defer obstacles.deinit();

    const map = try read_map(ally, buff, &guard, &obstacles);

    // Save initial guard states.
    const spawnPoint: Point = .{ .x = guard.x, .y = guard.y };
    const spawnDir: Direction = guard.direction;

    // Read all possible RetroEncabulator obstacle locations.
    const relocs = try read_re(ally, map, &guard);

    var stucks: usize = 0;

    for (relocs) |loc| {
        // De-visit all obstacles.
        var vit = obstacles.valueIterator();
        while (vit.next()) |ob| {
            ob.visited = false;
        }

        // Reset guard to her starting state.
        guard.y = spawnPoint.y;
        guard.x = spawnPoint.x;
        guard.direction = spawnDir;

        // Place new obstacle.
        map[loc.y][loc.x] = RetroEncabulator;
        try obstacles.put(loc, .{ .visited = false, .direction = undefined });

        while (true) {
            if (guard.face(map)) |point| switch (map[point.y][point.x]) {
                Obstacle, RetroEncabulator => {
                    guard.turn_90();

                    const ob = obstacles.getPtr(point).?;
                    if (ob.visited and ob.direction.isEqual(&guard.direction)) {
                        // The guard had already walked here - loop.
                        stucks += 1;
                        break;
                    }

                    ob.visited = true;
                    ob.direction = guard.direction;
                },
                else => guard.move(),
            } else break; // Beyond the map.
        }

        // Remove the new obstacle.
        _ = obstacles.remove(loc);
        map[loc.y][loc.x] = Empty;
    }

    return stucks;
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
    const stucks = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{stucks});
}
