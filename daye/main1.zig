const std = @import("std");

const Allocator = std.mem.Allocator;

const MapWidth = @as(i64, 101);
const MapHeight = @as(i64, 103);

// const MapWidth = @as(i64, 11);
// const MapHeight = @as(i64, 7);

const Map = [MapHeight][MapWidth]u8;

const MapWidthH = @divTrunc(MapWidth, 2);
const MapHeightH = @divTrunc(MapHeight, 2);

const Robot = struct { x: i64, y: i64, dx: i64, dy: i64 };

const Time = @as(i64, 10000);

const HeuristicLimit = @as(usize, 8);

fn move(r: *Robot, time: i64) void {
    var nx = @mod(r.x + r.dx * time, MapWidth);
    if (nx < 0) {
        nx = MapWidth - nx;
    }

    var ny = @mod(r.y + r.dy * time, MapHeight);
    if (ny < 0) {
        ny = MapHeight - ny;
    }

    r.x = nx;
    r.y = ny;
}

fn heuristic(
    map: Map,
    y: usize,
    x: usize,
    n: usize,
    limit: usize,
    block_dir: usize,
    v: []bool,
) usize {
    if ((n > limit) or v[map[y].len * y + x]) return n;

    var nn = n;
    v[map[y].len * y + x] = true;

    if ((block_dir != 0) and (y > 0) and (map[y - 1][x] > '0')) {
        nn = heuristic(map, y - 1, x, nn + 1, limit, 1, v);
    }
    if ((block_dir != 1) and (y < map.len - 1) and (map[y + 1][x] > '0')) {
        nn = heuristic(map, y + 1, x, nn + 1, limit, 0, v);
    }
    if ((block_dir != 2) and (x > 0) and (map[y][x - 1] > '0')) {
        nn = heuristic(map, y, x - 1, nn + 1, limit, 3, v);
    }
    if ((block_dir != 3) and (x < map[y].len - 1) and (map[y][x + 1] > '0')) {
        nn = heuristic(map, y, x + 1, nn + 1, limit, 2, v);
    }

    return nn;
}

fn print_map(map: Map) void {
    const ansi_black = "\x1b[30m";
    const ansi_green = "\x1b[32m";
    const ansi_rst = "\x1b[0m";
    std.debug.print("\x1b[2J\x1b[H", .{});
    for (0..map.len) |i| {
        for (0..map[i].len) |j| {
            if (map[i][j] > '0') {
                std.debug.print("{s}{s}{s}", .{ ansi_green, [_]u8{ map[i][j], 0 }, ansi_rst });
            } else {
                std.debug.print("{s}{s}{s}", .{ ansi_black, [_]u8{ map[i][j], 0 }, ansi_rst });
            }
        }
        std.debug.print("\n", .{});
    }
}

fn parse(ally: Allocator, buff: []const u8) ![]Robot {
    var array = std.ArrayList(Robot).init(ally);
    defer array.deinit();

    var bucket = [_]i64{0} ** 4;
    var token_i: usize = 0;

    var lineIt = std.mem.tokenizeScalar(u8, buff, '\n');
    while (lineIt.next()) |line| {
        token_i = 0;
        var it = std.mem.tokenizeAny(u8, line, "p=v, ");
        while (it.next()) |token| {
            const num = try std.fmt.parseInt(i64, token, 10);
            bucket[token_i] = num;
            token_i += 1;
        }

        try array.append(.{
            .x = bucket[0],
            .y = bucket[1],
            .dx = bucket[2],
            .dy = bucket[3],
        });
    }

    return array.toOwnedSlice();
}

fn process(ally: Allocator, buff: []const u8) !usize {
    var map: Map = undefined;
    const v = try ally.alloc(bool, MapWidth * MapHeight);
    defer ally.free(v);
    for (0..map.len) |i| {
        @memset(&map[i], '0');
    }

    var rs = try parse(ally, buff);
    for (1..Time + 1) |t| {
        for (0..rs.len) |i| {
            const r = &rs[i];

            var x_u: usize = @intCast(r.x);
            var y_u: usize = @intCast(r.y);

            map[y_u][x_u] -= 1;
            if (map[y_u][x_u] < '0') {
                map[y_u][x_u] = '0';
            }

            move(r, 1);

            x_u = @intCast(r.x);
            y_u = @intCast(r.y);
            map[y_u][x_u] += 1;
        }

        @memset(v, false);
        for (rs) |r| {
            const x_u: usize = @intCast(r.x);
            const y_u: usize = @intCast(r.y);
            if (heuristic(map, y_u, x_u, 0, HeuristicLimit, 4, v) <= HeuristicLimit) break;
            print_map(map);
            return t;
        }
    }

    unreachable;
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
    const time = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{time});
}
