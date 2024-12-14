const std = @import("std");

const Allocator = std.mem.Allocator;

const Button = struct { dx: i64, dy: i64 };
const Location = struct { x: i64, y: i64 };

const ClawMachine = struct { buttons: [2]Button, prize: Location };

const PriceA: i64 = 3;
const PriceB: i64 = 1;

const max_i64 = std.math.maxInt(i64);

const parse_table = [_]struct {
    trim_left: usize,
    delim: []const u8,
    delta: usize,
}{
    .{ .trim_left = "Button A: ".len, .delim = ", ", .delta = 2 },
    .{ .trim_left = "Button B: ".len, .delim = ", ", .delta = 2 },
    .{ .trim_left = "Prize: ".len, .delim = ", ", .delta = 2 },
};

fn parse(ally: *const Allocator, buff: []u8) ![]ClawMachine {
    var array = std.ArrayList(ClawMachine).init(ally.*);
    defer array.deinit();

    // Holds numerical data for one machine description.
    var lineData = [_]i64{0} ** 6;
    var token_i: usize = 0;

    var line_i: usize = 0;
    var lineIt = std.mem.tokenizeScalar(u8, buff, '\n');
    while (lineIt.next()) |line| {
        if (line.len == 0) continue; // Empty line.

        const parser = parse_table[line_i];
        var it = std.mem.tokenizeSequence(u8, line[parser.trim_left..], parser.delim);

        // Parse numerical data in this line.
        while (it.next()) |token| {
            const num = try std.fmt.parseInt(i64, token[parser.delta..], 10);
            lineData[token_i] = num;
            token_i += 1;
        }

        line_i += 1;
        if (line_i == 3) {
            // Add a claw machine entry.
            try array.append(.{
                .buttons = .{
                    .{ .dx = lineData[0], .dy = lineData[1] },
                    .{ .dx = lineData[2], .dy = lineData[3] },
                },
                .prize = .{ .x = lineData[4], .y = lineData[5] },
            });

            line_i = 0;
            token_i = 0;
        }
    }

    return array.toOwnedSlice();
}

fn solve_diophantine_u(cm: *const ClawMachine) i64 {
    var price: i64 = max_i64;
    for (0..101) |ka| {
        for (0..101) |kb| {
            const ka_i64 = @as(i64, @intCast(ka));
            const kb_i64 = @as(i64, @intCast(kb));

            const loc: Location = .{
                .x = ka_i64 * cm.buttons[0].dx + kb_i64 * cm.buttons[1].dx,
                .y = ka_i64 * cm.buttons[0].dy + kb_i64 * cm.buttons[1].dy,
            };

            const nprice = ka * PriceA + kb * PriceB;
            if ((loc.x == cm.prize.x) and (loc.y == cm.prize.y) and nprice < price) {
                price = nprice;
            }
        }
    }

    if (price == max_i64) return 0;
    return price;
}

fn solve_diophantine_f(cm: *const ClawMachine) i64 {
    const ka = @divTrunc(cm.prize.y - @divTrunc(cm.buttons[1].dy * cm.prize.x, cm.buttons[1].dx), cm.buttons[0].dy - @divTrunc(cm.buttons[1].dy * cm.buttons[0].dx, cm.buttons[1].dx));
    const kb = @divTrunc(cm.prize.y - @divTrunc(cm.buttons[0].dy * cm.prize.x, cm.buttons[0].dx), cm.buttons[1].dy - @divTrunc(cm.buttons[0].dy * cm.buttons[1].dx, cm.buttons[0].dx));

    if ((ka > 100) or (kb > 100)) return 0;

    return ka * PriceA + kb * PriceB;
}

fn process(ally: *const Allocator, buff: []u8) !i64 {
    var sum: i64 = 0;

    const cms = try parse(ally, buff);
    for (cms) |cm| {
        const price = solve_diophantine_u(&cm);
        // std.debug.print("{any} Price {}\n", .{ cm, price });
        sum += price;
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
    const tokens = try process(&pg_ally, file_buff);
    std.debug.print("{d}\n", .{tokens});
}
