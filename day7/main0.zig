const std = @import("std");

const Allocator = std.mem.Allocator;

const TestValue = usize;

/// Operator declarations.
const Operator = *const fn (a: TestValue, b: TestValue) TestValue;

fn add(a: TestValue, b: TestValue) TestValue {
    return a + b;
}
fn sub(a: TestValue, b: TestValue) TestValue {
    return a - b;
}
fn mul(a: TestValue, b: TestValue) TestValue {
    return a * b;
}
fn div(a: TestValue, b: TestValue) TestValue {
    return a / b;
}

/// Operators to apply during equation calibration.
const operators = [_]Operator{ add, mul };

/// Calibrates the given slice of test values by recursively applying operators.
/// Returns a true if the test values were calibrated.
fn calibrate(reach: TestValue, curr: TestValue, nums: []const TestValue) bool {
    if (nums.len == 0) return false;
    for (operators) |operator| {
        const curr_new = operator(curr, nums[0]);
        if ((curr_new == reach) or calibrate(reach, curr_new, nums[1..])) return true;
    }
    return false;
}

/// Processes the given buffer and returns a sum of calibrated equations.
fn process(ally: *const Allocator, buff: []const u8) !usize {
    var sum: usize = 0;

    var array = std.ArrayList(TestValue).init(ally.*);
    defer array.deinit();

    var lines = std.mem.tokenizeScalar(u8, buff, '\n');
    while (lines.next()) |line| {
        var i: usize = 0;

        // Parse numbers in each line in buff.
        var it = std.mem.tokenizeAny(u8, line, " :");
        while (it.next()) |token| {
            const value = try std.fmt.parseInt(TestValue, token, 10);

            if (array.items.len <= i) {
                try array.append(value);
            } else {
                array.items[i] = value;
            }

            i += 1;
        }

        // Operate the numbers.
        if (calibrate(array.items[0], array.items[1], array.items[2..i])) {
            sum += array.items[0];
        }
    }

    return sum;
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
    const sum = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{sum});
}
