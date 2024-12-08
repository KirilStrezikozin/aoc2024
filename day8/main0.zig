const std = @import("std");

const Allocator = std.mem.Allocator;

const Empty = '.';
const Antinode = '#';

const max_usize = std.math.maxInt(usize);

/// Returns the number of lines between a and b indices based off line length.
inline fn NLines(comptime T: type, a: T, b: T, lineLen: T) T {
    return @divTrunc(a, lineLen) - @divTrunc(b, lineLen);
}

fn process(ally: *const Allocator, map: []const u8) !usize {
    // Last antennas store indices of last antennas.
    var last_antennas: ['z' - '0' + 1]usize = undefined;
    if (last_antennas.len <= 'Z' - '0') @compileError("Invalid ASCII table");
    for (0..last_antennas.len) |i| {
        last_antennas[i] = max_usize;
    }

    // Linked antennas store indices of previous similar antennas.
    var linked_antennas = try ally.alloc(usize, map.len);
    defer ally.free(linked_antennas);
    for (0..linked_antennas.len) |i| {
        linked_antennas[i] = max_usize;
    }

    // Anti-nodes store an updated map with anti-node markings.
    var antinodes_n: usize = 0;
    var antinodes = try ally.alloc(u8, map.len);
    defer ally.free(antinodes);
    std.mem.copyForwards(u8, antinodes, map);

    // Calculate line length.
    var lineLen: usize = 0;
    for (map, 0..) |c, i| if (c == '\n') {
        lineLen = i + 1;
        break;
    };

    for (map, 0..) |c, i| {
        if ((c == Empty) or (c == '\n')) continue;
        const asi = c - '0';

        if (last_antennas[asi] == max_usize) {
            // First antenna of this kind, continue.
            last_antennas[asi] = i;
            continue;
        }

        // Update this antenna's link to the previous antenna.
        linked_antennas[i] = last_antennas[asi];
        last_antennas[asi] = i;

        // Form anti-nodes with all previous similar antennas.
        const curr_i = i;
        var prev_i = linked_antennas[curr_i];
        // std.debug.print("\nAntenna:\n", .{});
        while (prev_i != max_usize) {
            // std.debug.print("Curr: {d}, Prev: {d}\n", .{ curr_i, prev_i });

            // Calculate line breaks between the two antennas.
            // Used to verify if anti-nodes are within the map area.
            const nlines = NLines(usize, curr_i, prev_i, lineLen);
            const dist = curr_i - prev_i;

            // Anti-node 1.
            var ai, const overflow = @subWithOverflow(prev_i, dist);
            if ((overflow != 1) and
                (nlines == NLines(usize, prev_i, ai, lineLen)) and
                (antinodes[ai] != Antinode))
            {
                antinodes[ai] = Antinode;
                antinodes_n += 1;
            }

            // Anti-node 2.
            ai = curr_i + dist;
            if ((ai < map.len) and
                (nlines == NLines(usize, ai, curr_i, lineLen)) and
                (antinodes[ai] != Antinode))
            {
                antinodes[ai] = Antinode;
                antinodes_n += 1;
            }

            prev_i = linked_antennas[prev_i];

            // std.debug.print("Previous antenna at {d}=?\n", .{prev_i});
        }
    }

    // std.debug.print("Antinodes:\n{s}", .{antinodes});
    return antinodes_n;
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
    const buff = try file.readToEndAlloc(pg_ally, stat.size);

    // Process the file.
    const count = try process(&pg_ally, buff);
    std.debug.print("{d}\n", .{count});
}
