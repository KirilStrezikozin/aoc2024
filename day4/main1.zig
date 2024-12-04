const std = @import("std");

const MAS = "MAS";
const SAM = "SAM";

// Returns a 2d view onto the given file buffer, split by newline characters.
fn file_readbytes(ally: *const std.mem.Allocator, b: []const u8) ![][]const u8 {
    var array = std.ArrayList([]const u8).init(ally.*);

    var row_i: usize = 0;
    for (b, 0..) |c, i| {
        if (c == '\n') {
            try array.append(b[row_i..i]);
            row_i = i + 1;
        }
    }

    if (row_i < b.len) { // No final newline.
        try array.append(b[row_i..]);
    }

    return array.toOwnedSlice();
}

const Ray = struct {
    x: i64,
    y: i64,
};

fn is_mas(buff: [][]const u8, ri: usize, ci: usize, ray: Ray, mas: []const u8) bool {
    const mas_rc = mas[mas.len - 1];
    var lri = ri;
    var lci = ci;
    for (mas) |mas_c| {
        if (buff[lri][lci] != mas_c) break;
        if (buff[lri][lci] == mas_rc) return true;

        // Continue ray.
        lri = @as(usize, @intCast(@as(i64, @intCast(lri)) + ray.x));
        lci = @as(usize, @intCast(@as(i64, @intCast(lci)) + ray.y));
    }

    return false;
}

fn count_xmas(buff: [][]const u8) usize {
    const ray_ds = [_]Ray{
        // r  c
        .{ .x = 1, .y = 1 }, // bottom-right.
        .{ .x = 1, .y = -1 }, // bottom-left.
    };

    var matches: usize = 0;

    for (0..buff.len) |gri| {
        for (0..buff[gri].len) |gci| {
            // Check if MAS can fit.
            if ((gri + 2 >= buff.len) or (gci + 2 >= buff[gri].len)) continue;

            var is_match = is_mas(buff, gri, gci, ray_ds[0], MAS);
            is_match = is_match or is_mas(buff, gri, gci, ray_ds[0], SAM);
            if (!is_match) continue;

            if (is_mas(buff, gri, gci + 2, ray_ds[1], MAS)) {
                matches += 1;
            } else if (is_mas(buff, gri, gci + 2, ray_ds[1], SAM)) {
                matches += 1;
            }
        }
    }

    return matches;
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

    // View file as a matrix of lines.
    const bytes = try file_readbytes(&pg_ally, file_buff);
    defer pg_ally.free(bytes);

    // Count all XMASes.
    const count = count_xmas(bytes);
    std.debug.print("{d}\n", .{count});
}
