const std = @import("std");

const XMAS = "XMAS";

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

fn count_xmas(buff: [][]const u8) usize {
    const ray_ds = [_][2]i64{
        // r  c
        .{ 0, 1 }, // right.
        .{ 1, 1 }, // bottom-right.
        .{ 1, 0 }, // bottom.
        .{ 1, -1 }, // bottom-left.
        .{ 0, -1 }, // left.
        .{ -1, -1 }, // top-left.
        .{ -1, 0 }, // top.
        .{ -1, 1 }, // top-right.
    };

    var matches: usize = 0;

    for (0..buff.len) |gri| {
        for (0..buff[gri].len) |gci| {
            if (buff[gri][gci] != XMAS[0]) continue;

            for (ray_ds) |d| {
                var lri = gri;
                var lci = gci;
                ray: for (XMAS) |xmas_c| {
                    // Check match.
                    if (buff[lri][lci] != xmas_c) break :ray;
                    if (xmas_c == XMAS[XMAS.len - 1]) {
                        matches += 1;
                    }

                    // Continue ray, check if valid.
                    if ((lri == 0) and (d[0] < 0)) break :ray;
                    lri = @as(usize, @intCast(@as(i64, @intCast(lri)) + d[0]));
                    if (lri >= buff.len) break :ray;

                    if ((lci == 0) and (d[1] < 0)) break :ray;
                    lci = @as(usize, @intCast(@as(i64, @intCast(lci)) + d[1]));
                    if (lci >= buff[gri].len) break :ray;
                }
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
