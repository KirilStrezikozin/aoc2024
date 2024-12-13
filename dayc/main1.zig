const std = @import("std");

const Allocator = std.mem.Allocator;

const Map = [][]u8;
const max_usize = std.math.maxInt(usize);

const DirectionFlags = [4]bool;
const DefaultDirectionFlags = [_]bool{false} ** 4;

const Up = 0;
const Left = 1;
const Down = 2;
const Right = 3;

const SideText = [_][]const u8{ "Up", "Left", "Down", "Right" };

const Visited = @as(u1, 1);

const Fence = struct {
    ally: *const Allocator,
    data: []Pack = undefined,
    rows: usize = undefined,

    const Pack = struct { visited: bool, follow: [4]bool };

    fn init(ally: *const Allocator, rows: usize, cols: usize) !Fence {
        const data = try ally.alloc(Pack, rows * cols);
        @memset(data, .{ .visited = false, .follow = .{ false, false, false, false } });
        return Fence{
            .ally = ally,
            .data = data,
            .rows = rows,
        };
    }

    fn deinit(self: *Fence) void {
        _ = self.ally.free(self.data);
    }

    fn unpack(self: *Fence, y: usize, x: usize) *Pack {
        return &self.data[self.rows * y + x];
    }

    fn at(self: *Fence, y: usize, x: usize) bool {
        return self.data[self.rows * y + x].visited;
    }

    fn put(self: *Fence, y: usize, x: usize, p: Pack) void {
        self.data[self.rows * y + x] = p;
    }
};

/// Returns a 2d view onto the given file buffer, split by newline characters.
fn read_map(ally: *const Allocator, b: []u8) !Map {
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

fn price_region(
    map: Map,
    fence: *Fence,
    y: usize,
    x: usize,
) struct { area: usize, perimeter: usize } {
    const c = map[y][x];
    var area: usize = 1;
    var perimeter: usize = 0;

    var pack = fence.unpack(y, x);
    if (pack.visited) return .{ .area = 0, .perimeter = 0 };
    pack.visited = true;

    var neighbours = [_]bool{false} ** 4;
    var nfollow = [_]bool{false} ** 4;
    @memset(&pack.follow, true);

    // Determine if there exist neighbouring fences on the same side.

    // Up.
    if ((y > 0) and (map[y - 1][x] == c)) {
        const npack = fence.unpack(y - 1, x);
        neighbours[Up] = !npack.visited;
        pack.follow[Up] = false;
    } else {
        for (1..x + 1) |i| {
            if (((y > 0) and (map[y - 1][x - i] == c)) or (map[y][x - i] != c)) break;
            const fptr = &fence.unpack(y, x - i).follow[Up];
            if (fptr.*) {
                nfollow[Up] = true;
                break;
            }
            fptr.* = true;
        }
        for (x + 1..map[y].len) |i| {
            if (((y > 0) and (map[y - 1][i] == c)) or (map[y][i] != c)) break;
            const fptr = &fence.unpack(y, i).follow[Up];
            if (fptr.*) {
                nfollow[Up] = true;
                break;
            }
            fptr.* = true;
        }
    }

    // Right.
    if ((x < map[y].len - 1) and (map[y][x + 1] == c)) {
        const npack = fence.unpack(y, x + 1);
        neighbours[Right] = !npack.visited;
        pack.follow[Right] = false;
    } else {
        for (1..y + 1) |i| {
            if (((x < map[y].len - 1) and (map[y - i][x + 1] == c)) or (map[y - i][x] != c)) break;
            const fptr = &fence.unpack(y - i, x).follow[Right];
            if (fptr.*) {
                nfollow[Right] = true;
                break;
            }
            fptr.* = true;
        }
        for (y + 1..map.len) |i| {
            if (((x < map[y].len - 1) and (map[i][x + 1] == c)) or (map[i][x] != c)) break;
            const fptr = &fence.unpack(i, x).follow[Right];
            if (fptr.*) {
                nfollow[Right] = true;
                break;
            }
            fptr.* = true;
        }
    }

    // Down.
    if ((y < map.len - 1) and (map[y + 1][x] == c)) {
        const npack = fence.unpack(y + 1, x);
        neighbours[Down] = !npack.visited;
        pack.follow[Down] = false;
    } else {
        for (1..x + 1) |i| {
            if (((y < map.len - 1) and (map[y + 1][x - i] == c)) or (map[y][x - i] != c)) break;
            const fptr = &fence.unpack(y, x - i).follow[Down];
            if (fptr.*) {
                nfollow[Down] = true;
                break;
            }
            fptr.* = true;
        }
        for (x + 1..map[y].len) |i| {
            if (((y < map.len - 1) and (map[y + 1][i] == c)) or (map[y][i] != c)) break;
            const fptr = &fence.unpack(y, i).follow[Down];
            if (fptr.*) {
                nfollow[Down] = true;
                break;
            }
            fptr.* = true;
        }
    }

    // Left.
    if ((x > 0) and (map[y][x - 1] == c)) {
        const npack = fence.unpack(y, x - 1);
        neighbours[Left] = !npack.visited;
        pack.follow[Left] = false;
    } else {
        for (1..y + 1) |i| {
            if (((x > 0) and (map[y - i][x - 1] == c)) or (map[y - i][x] != c)) break;
            const fptr = &fence.unpack(y - i, x).follow[Left];
            if (fptr.*) {
                nfollow[Left] = true;
                break;
            }
            fptr.* = true;
        }
        for (y + 1..map.len) |i| {
            if (((x > 0) and (map[i][x - 1] == c)) or (map[i][x] != c)) break;
            const fptr = &fence.unpack(i, x).follow[Left];
            if (fptr.*) {
                nfollow[Left] = true;
                break;
            }
            fptr.* = true;
        }
    }

    for (0..pack.follow.len) |i| if (pack.follow[i] and !nfollow[i]) {
        // std.debug.print("Region {s} at y={d}, x={d}: new side {s}\n", .{
        //     [_]u8{ map[y][x], 0 },
        //     y,
        //     x,
        //     SideText[i],
        // });

        perimeter += 1;
    };

    // Explore the region.

    if (neighbours[Up]) {
        const region = price_region(map, fence, y - 1, x);
        perimeter += region.perimeter;
        area += region.area;
    }

    if (neighbours[Right]) {
        const region = price_region(map, fence, y, x + 1);
        perimeter += region.perimeter;
        area += region.area;
    }

    if (neighbours[Down]) {
        const region = price_region(map, fence, y + 1, x);
        perimeter += region.perimeter;
        area += region.area;
    }

    if (neighbours[Left]) {
        const region = price_region(map, fence, y, x - 1);
        perimeter += region.perimeter;
        area += region.area;
    }

    return .{ .area = area, .perimeter = perimeter };
}

fn process(ally: *const Allocator, buff: []u8) !usize {
    const map = try read_map(ally, buff);
    if (map.len == 0) return 0;

    var fence = try Fence.init(ally, map.len, map[0].len);
    defer fence.deinit();

    var price: usize = 0;
    for (0..map.len) |y| {
        for (0..map[y].len) |x| {
            const region = price_region(map, &fence, y, x);
            price += region.area * region.perimeter;

            // std.debug.print("Region {s}: price={d}*{d}\n", .{
            //     [_]u8{ map[y][x], 0 },
            //     region.area,
            //     region.perimeter,
            // });
        }
    }

    return price;
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
    const price = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{price});
}
