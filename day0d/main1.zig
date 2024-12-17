const std = @import("std");

const Allocator = std.mem.Allocator;

const Button = struct { dx: f64, dy: f64 };
const Location = struct { x: f64, y: f64 };

const ClawMachine = struct { buttons: [2]Button, prize: Location };

const PriceA: f64 = 3;
const PriceB: f64 = 1;

const max_f64 = std.math.inf(f64);

const delta: f64 = 10000000000000;
// const delta: f64 = 0;

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
    var lineData = [_]f64{0} ** 6;
    var token_i: usize = 0;

    var line_i: usize = 0;
    var lineIt = std.mem.tokenizeScalar(u8, buff, '\n');
    while (lineIt.next()) |line| {
        if (line.len == 0) continue; // Empty line.

        const parser = parse_table[line_i];
        var it = std.mem.tokenizeSequence(u8, line[parser.trim_left..], parser.delim);

        // Parse numerical data in this line.
        while (it.next()) |token| {
            const num = try std.fmt.parseFloat(f64, token[parser.delta..]);
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
                .prize = .{ .x = lineData[4] + delta, .y = lineData[5] + delta },
            });

            line_i = 0;
            token_i = 0;
        }
    }

    return array.toOwnedSlice();
}

fn solve_diophantine_u(cm: *const ClawMachine) f64 {
    var price: f64 = max_f64;
    for (0..101) |ka| {
        for (0..101) |kb| {
            const ka_f64 = @as(f64, @floatFromInt(ka));
            const kb_f64 = @as(f64, @floatFromInt(kb));

            const loc: Location = .{
                .x = ka_f64 * cm.buttons[0].dx + kb_f64 * cm.buttons[1].dx,
                .y = ka_f64 * cm.buttons[0].dy + kb_f64 * cm.buttons[1].dy,
            };

            const nprice = ka_f64 * PriceA + kb_f64 * PriceB;
            if ((loc.x == cm.prize.x) and (loc.y == cm.prize.y) and nprice < price) {
                price = nprice;
            }
        }
    }

    if (price == max_f64) return 0;
    return price;
}

fn fc_round(v: f64, tolerance: f64) f64 {
    const vr = @floor(v + 0.5);
    return if (std.math.approxEqRel(f64, v, vr, tolerance)) vr else v;
}

fn solve_diophantine_f(cm: *const ClawMachine) f64 {
    const tolerance = 0.000000000000001;
    // const tolerance = std.math.sqrt(std.math.floatEps(f64));

    const ka = fc_round((cm.prize.y - cm.buttons[1].dy * cm.prize.x / cm.buttons[1].dx) / (cm.buttons[0].dy - cm.buttons[1].dy * cm.buttons[0].dx / cm.buttons[1].dx), tolerance);
    const kb = fc_round((cm.prize.y - cm.buttons[0].dy * cm.prize.x / cm.buttons[0].dx) / (cm.buttons[1].dy - cm.buttons[0].dy * cm.buttons[1].dx / cm.buttons[0].dx), tolerance);

    if ((@floor(ka) != ka) or (@floor(kb) != kb)) return 0;
    // if ((ka > 100) or (kb > 100)) return 0;

    return ka * PriceA + kb * PriceB;
}

fn process(ally: *const Allocator, buff: []u8) !f64 {
    var sum: f64 = 0;

    const cms = try parse(ally, buff);
    for (cms) |cm| {
        // const price_i = solve_diophantine_u(&cm);
        const price_f = solve_diophantine_f(&cm);
        std.debug.print("Price int: {any} Price float: {}\n", .{ 0, price_f });
        sum += price_f;
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

    // std.debug.print("{}\n", .{fc_round(34.99999999999999999, 0.0000000001)});
    // std.debug.print("{}\n", .{fc_round(34.3847837, 0.0000000001)});
}
