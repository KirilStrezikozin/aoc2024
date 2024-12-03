const std = @import("std");

// Default allocator used by this program.
const pg_ally = std.heap.page_allocator;

// Delimiters to split a line of text into tokens.
const tkn_del = " \t\n";

// Parses a line and returns an array of integers.
// Clients are responsible to free the returned array.
fn parse_line(line: []const u8) ![]i64 {
    // Count the number of tokens in line.
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, tkn_del);
    while (true) {
        const token = it.next() orelse break;
        if (token.len == 0) break; // Potential line break.
        count += 1;
    }

    // Allocate an array to hold numbers, fill it by parsing each token.
    var array = try pg_ally.alloc(i64, count);
    it = std.mem.tokenizeAny(u8, line, tkn_del);
    var i: usize = 0;
    while (true) {
        const token = it.next() orelse break;
        if (token.len == 0) break; // Potential line break.
        array[i] = try std.fmt.parseInt(i64, token, 10);
        i += 1;
    }

    return array;
}

// Check if the array of numbers is safe according to the task description.
fn is_safe(array: []const i64) bool {
    for ([_]usize{ 0, 1 }) |diff_order| {
        var success: bool = true;
        for (1..array.len) |i| {
            const diff: i64 = array[i - diff_order] - array[i - 1 + diff_order];
            if ((diff < 1) or (diff > 3)) {
                success = false;
                break;
            }
        }
        if (success) {
            return true;
        }
    }
    return false;
}

pub fn main() !void {
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

    var reader = file.reader();
    var line_buff: [1024]u8 = undefined;

    // Read input line by line.
    var safety: usize = 0;
    while (try reader.readUntilDelimiterOrEof(&line_buff, '\n')) |line| {
        // Parse numbers in the read line.
        const numbers = try parse_line(line);
        var local_safety: bool = false;

        // Check all possible combinations.
        for (0..numbers.len) |i| {
            const arrays = [2][]const i64{ numbers[0..i], numbers[i + 1 ..] };
            const array = try std.mem.concat(pg_ally, i64, &arrays);
            local_safety = local_safety or is_safe(array);
            pg_ally.free(array);
        }

        pg_ally.free(numbers);
        if (local_safety) {
            safety += 1;
        }
    }

    // Print final result.
    std.debug.print("{d}\n", .{safety});
}
