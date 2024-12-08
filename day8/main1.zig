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

        // Form resonant anti-nodes with all previous similar antennas.
        const curr_i = i;
        var prev_i = linked_antennas[curr_i];
        while (prev_i != max_usize) {
            // Calculate line breaks between the two antennas.
            // Used to verify whether new anti-nodes are within the map area.
            const dist = curr_i - prev_i;
            const nlines = NLines(usize, curr_i, prev_i, lineLen);
            var ai: usize = undefined;

            // Resonant harmonics backward.
            ai = prev_i;
            while (true) {
                if (antinodes[ai] != Antinode) {
                    antinodes[ai] = Antinode;
                    antinodes_n += 1;
                }

                // Update and verify whether within the map's bounds.
                const new_ai, const overflow = @subWithOverflow(ai, dist);
                if ((overflow == @as(u1, 1)) or
                    (map[new_ai] == '\n') or
                    (nlines != NLines(usize, ai, new_ai, lineLen))) break;
                ai = new_ai;
            }

            // Resonant harmonics forward.
            ai = curr_i;
            while (true) {
                if (antinodes[ai] != Antinode) {
                    antinodes[ai] = Antinode;
                    antinodes_n += 1;
                }

                // Update and verify whether within the map's bounds.
                const new_ai, const overflow = @addWithOverflow(ai, dist);
                if ((overflow == @as(u1, 1)) or
                    (new_ai >= map.len) or
                    (map[new_ai] == '\n') or
                    (nlines != NLines(usize, new_ai, ai, lineLen))) break;
                ai = new_ai;
            }

            prev_i = linked_antennas[prev_i];
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
