const std = @import("std");

// 97902811429005 too high
// 97902809387716 too high

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
fn concat(a: TestValue, b: TestValue) TestValue {
    var chop = @as(TestValue, 1);

    while (b / chop >= 10) {
        chop *= 10;
    }

    var a_new: TestValue = a;
    var b_mod: TestValue = b;
    while (chop > 0) {
        a_new = a_new * 10 + b_mod / chop;
        b_mod %= chop;
        chop /= 10;
    }

    return a_new;
}

/// Operators to apply during equation calibration.
const operators = [_]Operator{ concat, mul, add };

/// Calibrates the given slice of test values by recursively applying operators.
/// Returns a true if the test values were calibrated.
fn calibrate(reach: TestValue, curr: TestValue, nums: []const TestValue, i: usize) bool {
    if (i >= nums.len) return curr == reach;
    for (operators) |operator| {
        if (calibrate(reach, operator(curr, nums[i]), nums, i + 1)) return true;
    }
    return false;
}

/// Processes the given buffer and returns a sum of calibrated equations.
fn process(ally: *const Allocator, buff: []const u8) !TestValue {
    var sum: TestValue = 0;

    var array = std.ArrayList(TestValue).init(ally.*);
    defer array.deinit();

    var lines = std.mem.tokenizeScalar(u8, buff, '\n');
    while (lines.next()) |line| {
        var i: usize = 0;

        // Parse numbers in each line in buff.
        var it = std.mem.tokenizeAny(u8, line, " :");
        while (it.next()) |token| {
            const value = try std.fmt.parseUnsigned(TestValue, token, 10);

            if (array.items.len <= i) {
                try array.append(value);
            } else {
                array.items[i] = value;
            }

            i += 1;
        }

        // Operate the numbers.
        if (calibrate(array.items[0], array.items[1], array.items[2..i], 0)) {
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
