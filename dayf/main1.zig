const std = @import("std");

// 1563755 too low.

const Allocator = std.mem.Allocator;

const Map = [][]u8;

const Location = struct { y: usize, x: usize };
const Robot = Location;

const Wide = struct { c: [2]u8, orig: u8 };

const Box = Wide{ .c = [_]u8{ '[', ']' }, .orig = 'O' };
const Wall = Wide{ .c = [_]u8{ '#', '#' }, .orig = '#' };
const Empty = Wide{ .c = [_]u8{ '.', '.' }, .orig = '.' };
const RobotC = Wide{ .c = [_]u8{ '@', '.' }, .orig = '@' };

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

/// Frees the map.
inline fn free_map(ally: Allocator, map: Map) void {
    for (map) |row| {
        ally.free(row);
    }
    ally.free(map);
}

/// Returns a 2d grid of characters read from the given buffer, split by
/// newline characters, the byte offset to continue reading from, and a
/// starting location of the Robot. The grid is widened by two times.
///
/// Clients are responsible for freeing the returned Map.
fn read_map(ally: Allocator, b: []u8) !struct { m: Map, r: Robot, s: usize } {
    var array = std.ArrayList([]u8).init(ally);
    defer array.deinit();

    // Determine the line length.
    var lineLen: usize = 0;
    for (b) |c| if (c != '\n') {
        lineLen += 1;
    } else break;

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

                // Widen the line and write it to the array.
                var lineBuff = try ally.alloc(u8, lineLen * 2);
                for (b[row_start..i], 0..) |cc, ii| {
                    switch (cc) {
                        Box.orig => {
                            lineBuff[ii * 2] = Box.c[0];
                            lineBuff[ii * 2 + 1] = Box.c[1];
                        },
                        Wall.orig => {
                            lineBuff[ii * 2] = Wall.c[0];
                            lineBuff[ii * 2 + 1] = Wall.c[1];
                        },
                        Empty.orig => {
                            lineBuff[ii * 2] = Empty.c[0];
                            lineBuff[ii * 2 + 1] = Empty.c[1];
                        },
                        RobotC.orig => {
                            lineBuff[ii * 2] = RobotC.c[0];
                            lineBuff[ii * 2 + 1] = RobotC.c[1];
                            robot.y = row_i;
                            robot.x = ii * 2;
                        },
                        else => unreachable,
                    }
                }

                try array.append(lineBuff);

                row_start = i + 1;
                row_i += 1;
                col_i = 0;
            },
            else => {
                if (i == last_i) { // No final newline.
                    try array.append(b[row_start..]);
                }
                col_i += 1;
            },
        }
    }

    return .{ .m = try array.toOwnedSlice(), .r = robot, .s = b.len };
}

/// Moves only the contents that align with the robot and updates the map.
fn move_h(map: Map, robot: *Robot, dir: Direction) void {
    if (dir.dy != 0) {
        @panic("Horizontal directions allowed only");
    }

    std.debug.print("Dir: {any}, R: {any}\n", .{ dir, robot.* });

    var loc: Location = robot.*;
    while (true) {
        loc.x = @intCast(@as(i64, @intCast(loc.x)) + dir.dx);

        switch (map[loc.y][loc.x]) {
            Wall.c[0] => return, // Wall encountered, cannot move.
            Empty.c[0] => break,
            else => continue,
        }
    }

    // Starting from the found empty spot at loc, move blocks to towards it.
    while (true) {
        const loc_nx: usize = @intCast(@as(i64, @intCast(loc.x)) - dir.dx);

        map[loc.y][loc.x] = map[loc.y][loc_nx];

        if (map[loc.y][loc.x] == RobotC.c[0]) {
            robot.y = loc.y;
            robot.x = loc.x;

            map[loc.y][loc_nx] = Empty.c[0];
            break;
        }

        loc.x = loc_nx;
    }
}

/// Moves the contents of the map that are touched by the Robot and updates
/// the map. If a Box on the map is aligned such that it touches two different
/// boxes above/below it, it will push those two boxes.
fn move_v(ally: Allocator, map: Map, robot: *Robot, dir: Direction) !void {
    if (dir.dx != 0) {
        @panic("Vertical directions allowed only");
    }

    std.debug.print("Dir: {any}, R: {any}\n", .{ dir, robot.* });

    var loc: Location = robot.*;

    // The contents that have to be moved are located from l to r.
    var l: usize = loc.x;
    var r: usize = loc.x;
    var min_l: usize = loc.x;
    var max_r: usize = loc.x;

    var box_lrs = std.ArrayList(struct { l: usize, r: usize }).init(ally);
    defer box_lrs.deinit();
    var box_lri: usize = 0;

    find: while (true) {
        loc.y = @intCast(@as(i64, @intCast(loc.y)) + dir.dy);

        if (map[loc.y][l] == Box.c[1]) {
            l -= 1;
        }
        if (map[loc.y][r] == Box.c[0]) {
            r += 1;
        }

        if (l < min_l) {
            min_l = l;
        }
        if (r > max_r) {
            max_r = r;
        }

        // Shrink the gap from l to r such that it only
        // covers the space to be moved.
        for (l..r + 1) |x| {
            switch (map[loc.y][x]) {
                Wall.c[0] => return,
                Box.c[0] => {
                    l = x;
                    break;
                },
                else => continue,
            }
        }
        for (l..r, 0..) |_, i| {
            switch (map[loc.y][r - i]) {
                Wall.c[0] => return,
                Box.c[1] => {
                    r -= i;
                    break;
                },
                else => continue,
            }
        }

        // Store the number of boxes to be moved on this line.
        try box_lrs.append(.{ .l = l, .r = r });
        box_lri += 1;

        for (l..r + 1) |x| switch (map[loc.y][x]) {
            Wall.c[0] => return, // Wall encountered, cannot move.
            Box.c[0], Box.c[1] => continue :find,
            else => {},
        };
        break;
    }

    std.debug.print("{any}\n", .{box_lrs.items});

    // Starting from the found free space from l to r, move blocks towards it.
    box_lri -= 1;
    while (true) {
        std.debug.print("y={d} l={d} r={d}\n", .{ loc.y, l, r });
        const loc_ny: usize = @intCast(@as(i64, @intCast(loc.y)) - dir.dy);

        var rl: bool = false;
        if (box_lri == 0) {
            l = robot.x;
            r = robot.x;
            robot.y = loc.y;
            rl = true;
        } else {
            box_lri -= 1;

            const box = box_lrs.items[box_lri];
            l = box.l;
            r = box.r;
        }

        // var nl = l;
        // var nr = r;
        //
        // // Resize the gap from l to r to cover the pushed area entirely.
        // if (loc_ny != robot.y) {
        //     while ((nl > min_l)) switch (map[loc_ny][nl]) {
        //         Box.c[0], Box.c[1] => nl -= 1,
        //         else => break,
        //     };
        //     while ((nr < max_r)) switch (map[loc_ny][nr]) {
        //         Box.c[0], Box.c[1] => nr += 1,
        //         else => break,
        //     };
        // }
        //
        // // Shrink the gap from l to r such that it only
        // // covers the space to be moved.
        // var rl: bool = false;
        // for (nl..nr + 1) |x| {
        //     switch (map[loc_ny][x]) {
        //         Box.c[0] => {
        //             l = x;
        //             break;
        //         },
        //         RobotC.c[0] => {
        //             robot.y = loc.y;
        //             robot.x = x;
        //             rl = true;
        //             l = x;
        //             break;
        //         },
        //         else => continue,
        //     }
        // }
        // for (nl..nr, 0..) |_, i| {
        //     switch (map[loc_ny][nr - i]) {
        //         Box.c[1] => {
        //             r = nr - i;
        //             break;
        //         },
        //         else => {
        //             if (!rl) continue;
        //             if (l == r) {
        //                 l -= 1;
        //             }
        //             break;
        //         },
        //     }
        // }

        std.debug.print("copy from y={d} l={d} r={d}, R: {any}\n", .{ loc_ny, l, r, robot.* });
        for (l..r + 1) |x| {
            if (!rl) {
                map[loc.y][x] = map[loc_ny][x];
                map[loc_ny][x] = Empty.c[0];
            } else if (x == robot.x) {
                map[loc.y][x] = map[loc_ny][x];
                map[loc_ny][x] = Empty.c[0];
            }
        }

        loc.y = loc_ny;
        if (rl) {
            map[loc.y][robot.x] = RobotC.c[1];
            // map[loc.y][robot.x + 1] = RobotC.c[1];
            break;
        }
    }
}

inline fn gps(map: Map) usize {
    var sum_gps: usize = 0;

    for (0..map.len) |y| {
        for (0..map[y].len) |x| {
            if (map[y][x] == Box.c[0]) {
                sum_gps += 100 * y + x;
            }
        }
    }

    return sum_gps;
}

inline fn validate_map(map: Map) bool {
    for (0..map.len) |y| {
        for (0..map[y].len) |x| {
            const c = map[y][x];
            if ((c == Box.c[0]) and (map[y][x + 1] != Box.c[1])) {
                return false;
            }
        }
    }
    return true;
}

inline fn validate_print_map(map: Map) void {
    const ansi_red = "\x1b[31m";
    const ansi_rst = "\x1b[0m";

    for (0..map.len) |y| {
        for (0..map[y].len) |x| {
            const c = map[y][x];

            if ((c == Box.c[0]) and (map[y][x + 1] != Box.c[1])) {
                std.debug.print("{s}{s}{s}", .{ ansi_red, [_]u8{ c, 0 }, ansi_rst });
            } else {
                std.debug.print("{s}", .{[_]u8{ c, 0 }});
            }
        }
        std.debug.print("\n", .{});
    }
}

fn process(ally: Allocator, buff: []u8) !usize {
    const input = try read_map(ally, buff);

    const map = input.m;
    defer free_map(ally, map);

    const seek = input.s;
    var robot = input.r;

    for (seek..buff.len) |i| {
        // for (seek..9500) |i| {
        if (!validate_map(map)) {
            validate_print_map(map);
            break;
        }
        // if ((i > 10450) and (i < 10503)) {
        // validate_print_map(map);
        // }
        // if (i >= 10503) break;
        std.debug.print("Instruction i: {d}\n", .{i});
        switch (buff[i]) {
            '\n' => continue,

            Up => try move_v(ally, map, &robot, get_direction(Up)),
            Down => try move_v(ally, map, &robot, get_direction(Down)),

            Right => move_h(map, &robot, get_direction(Right)),
            Left => move_h(map, &robot, get_direction(Left)),

            else => return 0,
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
