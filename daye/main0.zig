const std = @import("std");

const MapWidth = @as(i64, 101);
const MapHeight = @as(i64, 103);

// const MapWidth = @as(i64, 11);
// const MapHeight = @as(i64, 7);

const MapWidthH = @divTrunc(MapWidth, 2);
const MapHeightH = @divTrunc(MapHeight, 2);

const Time = @as(i64, 100);

fn patrol(r: []const i64) usize {
    var nx = @mod(r[0] + r[2] * Time, MapWidth);
    if (nx < 0) {
        nx = MapWidth - nx;
    }

    var ny = @mod(r[1] + r[3] * Time, MapHeight);
    if (ny < 0) {
        ny = MapHeight - ny;
    }

    if ((nx == MapWidthH) or (ny == MapHeightH)) return 4;

    var qx: usize = 0;
    if (nx > MapWidthH) {
        qx = 1;
    }

    var qy: usize = 0;
    if (ny > MapHeightH) {
        qy = 2;
    }

    return qx + qy;
}

fn process(buff: []const u8) !usize {
    var quadrants = [_]usize{0} ** 4;
    var token_i: usize = 0;

    var bucket = [_]i64{0} ** 4;

    var lineIt = std.mem.tokenizeScalar(u8, buff, '\n');
    while (lineIt.next()) |line| {
        token_i = 0;
        var it = std.mem.tokenizeAny(u8, line, "p=v, ");
        while (it.next()) |token| {
            const num = try std.fmt.parseInt(i64, token, 10);
            bucket[token_i] = num;
            token_i += 1;
            // std.debug.print("{d} ", .{num});
        }

        const quadrant = patrol(&bucket);
        if (quadrant >= quadrants.len) continue;
        quadrants[quadrant] += 1;
        // std.debug.print("\n", .{});
    }

    var factor: usize = 1;
    for (quadrants) |quadrant| {
        factor *= quadrant;
    }

    return factor;
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
    const factor = try process(file_buff);
    std.debug.print("{d}\n", .{factor});
}
