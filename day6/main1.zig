const std = @import("std");

const Allocator = std.mem.Allocator;

const Map = [][]u8;
const Obstacle = '#';
const Mark = 'X';

/// Historians' new obstacle.
const RetroEncabulator = 'O';
/// Stores possible position for the RetroEncabulator.
const RELocations = []Point;

/// Indicates what a Guard currently faces in front.
const Face = enum(u8) {
    end_of_map,
    obstacle,
    mark,
    empty,
};

/// Direction is a (dx, dy) difference to apply to a (x, y) point.
const Direction = struct {
    dx: i64 = 0,
    dy: i64 = 0,
};

/// Point is a (x, y) mapping on a 2d coordinate system.
const Point = struct {
    x: usize = undefined,
    y: usize = undefined,
};

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
    pub fn move(self: *Guard) void {
        const new_x: i64 = self.direction.dx + @as(i64, @intCast(self.x));
        const new_y: i64 = self.direction.dy + @as(i64, @intCast(self.y));

        self.*.x = @as(usize, @intCast(new_x));
        self.*.y = @as(usize, @intCast(new_y));
    }

    /// Move to the specified (x, y) coordinate.
    pub fn moveTo(self: *Guard, x: usize, y: usize) void {
        self.*.x = x;
        self.*.y = y;
    }

    /// Returns a Face enum indicating what the Guard currently faces in front.
    pub fn face(self: *Guard, map: Map) Face {
        const new_x: i64 = self.direction.dx + @as(i64, @intCast(self.x));
        const new_y: i64 = self.direction.dy + @as(i64, @intCast(self.y));

        if ((new_x < 0) or (new_x >= @as(i64, @intCast(map[self.y].len)))) {
            return .end_of_map;
        } else if ((new_y < 0) or (new_y >= @as(i64, @intCast(map.len)))) {
            return .end_of_map;
        }

        const new_ux = @as(usize, @intCast(new_x));
        const new_uy = @as(usize, @intCast(new_y));

        return switch (map[new_uy][new_ux]) {
            Mark => .mark,
            Obstacle, RetroEncabulator => .obstacle,
            else => .empty,
        };
    }

    /// Turns the Guard's walking direction by 90 degrees.
    pub fn turn_90(self: *Guard) void {
        const dx = self.*.direction.dx;
        const dy = self.*.direction.dy;
        if ((dx == 0) and (dy == -1)) { // Up.
            self.*.direction.dx = 1;
            self.*.direction.dy = 0;
        } else if ((dx == 1) and (dy == 0)) { // Right.
            self.*.direction.dx = 0;
            self.*.direction.dy = 1;
        } else if ((dx == 0) and (dy == 1)) { // Down.
            self.*.direction.dx = -1;
            self.*.direction.dy = 0;
        } else if ((dx == -1) and (dy == 0)) { // Left.
            self.*.direction.dx = 0;
            self.*.direction.dy = -1;
        } else unreachable;
    }
};

/// Returns a 2d view onto the given file buffer,split by newline characters.
/// Positions the given Guard struct in the starting position found on the map.
fn read_map(ally: *const Allocator, b: []u8, guard: *Guard) !Map {
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
            },
            '^' => {
                guard.moveTo(col_i, row_i);
                guard.*.direction = .{ .dx = 0, .dy = -1 };
            },
            '>' => {
                guard.moveTo(col_i, row_i);
                guard.*.direction = .{ .dx = 1, .dy = 0 };
            },
            'v' => {
                guard.moveTo(col_i, row_i);
                guard.*.direction = .{ .dx = 0, .dy = 1 };
            },
            '<' => {
                guard.moveTo(col_i, row_i);
                guard.*.direction = .{ .dx = -1, .dy = 0 };
            },
            else => {
                if (i == last_i) { // No final newline.
                    try array.append(b[row_start..]);
                }
                col_i += 1;
            },
        }
    }

    return array.toOwnedSlice();
}

/// Returns all possible (x, y) locations for the RetroEncabulator obstacle.
/// It overwrites the contents of given Map and Guard. Client's are responsible
/// for providing copies of these values if needed.
fn read_re(ally: *const Allocator, map: Map, guard_ptr: *Guard) !RELocations {
    var array = std.ArrayList(Point).init(ally.*);
    defer array.deinit();

    var guard = guard_ptr.*;

    // Mark initial position as visited, but do not add it to the list of
    // possible RetroEncabulator locations.
    map[guard.y][guard.x] = Mark;

    walk: while (true) {
        switch (guard.face(map)) {
            .end_of_map => break :walk,
            .obstacle => guard.turn_90(),
            .mark => guard.move(),
            .empty => {
                guard.move();
                map[guard.y][guard.x] = Mark;
                try array.append(.{ .y = guard.y, .x = guard.x });
            },
        }
    }

    return array.toOwnedSlice();
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    // Construct positions for the new obstacle.
    // Do not modify the given buffer to be able to reset the Map.
    const buff_cp = try ally.alloc(u8, buff.len);
    std.mem.copyForwards(u8, buff_cp, buff);
    defer ally.free(buff_cp);

    // Working map and guard.
    var guard = Guard.default;
    const map: Map = try read_map(ally, buff_cp, &guard);

    // Save initial guard states.
    const spawnPoint: Point = .{ .x = guard.x, .y = guard.y };
    const spawnDir: Direction = guard.direction;

    // Read all possible RetroEncabulator obstacle locations.
    const relocs = try read_re(ally, map, &guard);

    var stucks: usize = 0;

    for (relocs) |loc| {
        // Reset (clear) map using the fallback source buffer.
        std.mem.copyForwards(u8, buff_cp, buff);

        // Reset guard to her starting state.
        guard.y = spawnPoint.y;
        guard.x = spawnPoint.x;
        guard.direction = spawnDir;

        // Place new obstacle.
        map[loc.y][loc.x] = RetroEncabulator;

        // Check if guard is stuck in a loop.
        var new_visited: usize = 1;
        var dejavu: usize = 0;

        // Mark initial position as visited.
        map[guard.y][guard.x] = Mark;

        walk: while (true) {
            switch (guard.face(map)) {
                .end_of_map => break :walk,
                .obstacle => {
                    guard.turn_90();

                    if (new_visited > 0) {
                        // The guard had already walked this route before.
                        new_visited = 0;
                        continue :walk;
                    }

                    // Make the guard walk the same route enough times to
                    // be sure this is a closed loop.
                    dejavu += 1;
                    if (dejavu < 10) continue;
                    stucks += 1;
                    break :walk;
                },
                .mark => guard.move(),
                .empty => {
                    guard.move();
                    map[guard.y][guard.x] = Mark;
                    new_visited += 1;
                },
            }
        }
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
