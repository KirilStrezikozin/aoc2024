const std = @import("std");

const Allocator = std.mem.Allocator;

const Map = [][]u8;

const Location = struct { y: usize, x: usize };
const Robot = Location;

const Box = 'O';
const Wall = '#';
const Empty = '.';
const RobotC = '@';

const Direction = struct { dy: i64, dx: i64 };

const Up = '^';
const Right = '>';
const Down = 'v';
const Left = '<';

/// Returns a Map movement direction depending on the cursor shape.
inline fn get_direction(comptime c: u8) Direction {
    return comptime switch (c) {
        '^' => .{ .dy = -1, .dx = 0 },
        '>' => .{ .dy = 0, .dx = 1 },
        'v' => .{ .dy = 1, .dx = 0 },
        '<' => .{ .dy = 0, .dx = -1 },
        else => @compileError("Invalid direction: " ++ [_]u8{ c, 0 }),
    };
}

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
fn read_map(ally: Allocator, b: []u8) !struct { m: Map, r: Robot, s: usize } {
    var array = std.ArrayList([]u8).init(ally);
    defer array.deinit();

    var robot: Robot = undefined;

    // x, y positions for bytes in the given buff.
    var row_i: usize = 0;
    var col_i: usize = 0;

    var row_start: usize = 0;
    const last_i: usize = b.len - 1;
    for (b, 0..) |c, i| {
        switch (c) {
            '\n' => {
                if (i == row_start) {
                    // Map data finished.
                    return .{
                        .m = try array.toOwnedSlice(),
                        .r = robot,
                        .s = i + 1,
                    };
                }

                try array.append(b[row_start..i]);
                row_start = i + 1;
                row_i += 1;
                col_i = 0;
            },
            else => {
                if (c == '@') {
                    robot.y = row_i;
                    robot.x = col_i;
                }

                if (i == last_i) { // No final newline.
                    try array.append(b[row_start..]);
                }
                col_i += 1;
            },
        }
    }

    return .{ .m = try array.toOwnedSlice(), .r = robot, .s = b.len };
}

inline fn move(map: Map, robot: *Robot, dir: Direction) void {
    var loc: Location = robot.*;
    while (true) {
        loc.y = @intCast(@as(i64, @intCast(loc.y)) + dir.dy);
        loc.x = @intCast(@as(i64, @intCast(loc.x)) + dir.dx);

        switch (map[loc.y][loc.x]) {
            Wall => return, // Wall encountered, cannot move.
            Empty => break,
            else => continue,
        }
    }

    // Starting from the found empty spot at loc, move blocks to towards it.
    while (true) {
        const loc_ny: usize = @intCast(@as(i64, @intCast(loc.y)) - dir.dy);
        const loc_nx: usize = @intCast(@as(i64, @intCast(loc.x)) - dir.dx);

        map[loc.y][loc.x] = map[loc_ny][loc_nx];

        if (map[loc.y][loc.x] == RobotC) {
            robot.y = loc.y;
            robot.x = loc.x;

            map[loc_ny][loc_nx] = Empty;
            break;
        }

        loc.y = loc_ny;
        loc.x = loc_nx;
    }
}

inline fn gps(map: Map) usize {
    var sum_gps: usize = 0;

    for (0..map.len) |y| {
        for (0..map[y].len) |x| {
            if (map[y][x] == Box) {
                sum_gps += 100 * y + x;
            }
        }
    }

    return sum_gps;
}

fn process(ally: Allocator, buff: []u8) !usize {
    const input = try read_map(ally, buff);
    const seek = input.s;
    const map = input.m;
    var robot = input.r;

    for (seek..buff.len) |i| {
        switch (buff[i]) {
            '\n' => continue,
            Up => move(map, &robot, get_direction(Up)),
            Right => move(map, &robot, get_direction(Right)),
            Down => move(map, &robot, get_direction(Down)),
            Left => move(map, &robot, get_direction(Left)),
            else => unreachable,
        }
    }

    print_map(map);
    return gps(map);
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
    const sum_gps = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{sum_gps});
}
