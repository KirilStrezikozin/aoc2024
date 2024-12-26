const std = @import("std");

const Allocator = std.mem.Allocator;

const Id = u24;
const State = u1;

const Outputs = std.AutoHashMap(Id, State);

const Procedure = struct {
    depends: [2]Id,
    output: Id,
    produce: *const fn (State, State) State,
};

const Zeta = struct {
    const Value = usize;

    // For our input, maximum zeta bit is 45,
    // which fits within the 64-bit usize type.
    bits: [@bitSizeOf(Value)]State,

    /// The number of Zeta's bits left to fill with values.
    pending: usize,

    /// Returns Zeta's bits interpreted as a decimal.
    fn asDecimal(self: @This()) Value {
        var value: Value = 0;

        for (0..self.bits.len) |i| {
            const bit_i = self.bits.len - 1 - i;
            value += std.math.pow(Value, 2, i) * @as(Value, @intCast(self.bits[bit_i]));
        }

        return value;
    }
};

const QueueContext = struct {
    fn compareFn(_: @This(), a: Procedure, b: Procedure) std.math.Order {
        return std.math.order(a.output, b.output);
    }
};

const Queue = std.PriorityQueue(Procedure, QueueContext, QueueContext.compareFn);

fn fnXor(a: State, b: State) State {
    return a ^ b;
}

fn fnOr(a: State, b: State) State {
    return a | b;
}

fn fnAnd(a: State, b: State) State {
    return a & b;
}

/// Returns the given id interpreted as a string.
fn idAsSlice(id: *const Id) *const [3]u8 {
    return @ptrCast(id);
}

/// Returns a copy of the given string as an id.
fn idFromSlice(s: *const [3]u8) Id {
    return (@as(Id, @intCast(s[2])) << @bitSizeOf(u8) * 2) |
        (@as(Id, @intCast(s[1])) << @bitSizeOf(u8)) |
        @as(Id, @intCast(s[0]));
}

/// Caller owns both the returned outputs and procedures.
fn parse(ally: Allocator, buff: []const u8) !struct { Outputs, []Procedure, Zeta } {
    var read_procedures: bool = false;

    var zeta: Zeta = .{ .bits = undefined, .pending = 0 };
    @memset(&zeta.bits, @as(u1, 0));

    var outputs = Outputs.init(ally);
    var procedures = try std.ArrayList(Procedure).initCapacity(ally, 1 << 8);
    defer procedures.deinit();

    var it = std.mem.splitScalar(u8, buff, '\n');
    while (it.next()) |line| {
        if (line.len == 0) {
            read_procedures = true;
            continue;
        }

        if (!read_procedures) {
            var parser = std.mem.tokenizeSequence(u8, line, ": ");

            const id = idFromSlice(@ptrCast(parser.next().?.ptr));
            const state: State = @intCast(parser.next().?[0] - '0');

            try outputs.putNoClobber(id, state);
            continue;
        }

        var parser = std.mem.tokenizeScalar(u8, line, ' ');

        var procedure: Procedure = undefined;
        procedure.depends[0] = idFromSlice(@ptrCast(parser.next().?.ptr));

        const produce_utf = parser.next().?;
        procedure.produce = blk: {
            if (std.mem.order(u8, produce_utf, "XOR") == .eq) {
                break :blk fnXor;
            } else if (std.mem.order(u8, produce_utf, "OR") == .eq) {
                break :blk fnOr;
            } else {
                break :blk fnAnd;
            }
        };

        procedure.depends[1] = idFromSlice(@ptrCast(parser.next().?.ptr));
        _ = parser.next().?;

        const output_utf: *const [3]u8 = @ptrCast(parser.next().?.ptr);
        procedure.output = idFromSlice(output_utf);

        const input0 = outputs.get(procedure.depends[0]);
        const input1 = outputs.get(procedure.depends[1]);

        if ((input0 != null) and
            (input1 != null))
        {
            // Dependencies already satisfied,
            // produce output immediately.

            const output = procedure.produce(input0.?, input1.?);
            try outputs.putNoClobber(procedure.output, output);

            if (output_utf[0] == 'z') {
                // Assign this z bit to the final value.
                std.debug.print("{s} index={d}*10+{d}\n", .{
                    output_utf,
                    output_utf[1] - '0',
                    output_utf[2] - '0',
                });

                const z_bit = zeta.bits.len - 1 -
                    (@as(usize, @intCast((output_utf[1] - '0'))) * 10 +
                    @as(usize, @intCast(output_utf[2] - '0')));
                zeta.bits[z_bit] = output;
            }

            continue;
        }

        if (output_utf[0] == 'z') {
            zeta.pending += 1;
        }

        try procedures.append(procedure);
    }

    return .{ outputs, try procedures.toOwnedSlice(), zeta };
}

fn process(ally: Allocator, buff: []const u8) !usize {
    var outputs, const procedures, var zeta = try parse(ally, buff);

    defer {
        outputs.deinit();
        ally.free(procedures);
    }

    {
        // Print parsed input.
        var it = outputs.iterator();
        while (it.next()) |entry| {
            std.debug.print("{s}: {d}\n", .{ idAsSlice(entry.key_ptr), entry.value_ptr.* });
        }

        for (procedures) |procedure| {
            std.debug.print("{s}", .{idAsSlice(&procedure.depends[0])});
            std.debug.print(" {s} ", .{@typeName(@TypeOf(procedure.produce))});
            std.debug.print("{s} -> ", .{idAsSlice(&procedure.depends[1])});
            std.debug.print("{s}\n", .{idAsSlice(&procedure.output)});
        }
    }

    var queue = Queue.init(ally, .{});
    defer queue.deinit();

    // Add all procedures to the queue to await processing.
    for (procedures) |procedure| {
        try queue.add(procedure);
    }

    var it = queue.iterator();
    while (it.next()) |procedure| {
        if (zeta.pending == 0) break;

        const input0 = outputs.get(procedure.depends[0]);
        const input1 = outputs.get(procedure.depends[1]);

        if ((input0 == null) or
            (input1 == null))
        {
            continue;
        }

        const output = procedure.produce(input0.?, input1.?);
        try outputs.putNoClobber(procedure.output, output);

        _ = queue.removeIndex(it.count - 1);
        it.reset();

        const output_utf = idAsSlice(&procedure.output);
        if (output_utf[0] == 'z') {
            zeta.pending -= 1;

            // Assign this z bit to the final value.
            const z_bit = zeta.bits.len - 1 -
                (@as(usize, @intCast((output_utf[1] - '0'))) * 10 +
                @as(usize, @intCast(output_utf[2] - '0')));

            zeta.bits[z_bit] = output;
        }
    }

    std.debug.print("Bits: {any}\n", .{zeta.bits});
    return zeta.asDecimal();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    defer {
        if (gpa.deinit() == .leak) {
            @panic("Not all allocated memory was freed");
        }
    }

    // Process command-line arguments passed to main.
    const args = try std.process.argsAlloc(ally);
    defer std.process.argsFree(ally, args);

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
    const file_buff = try file.readToEndAlloc(ally, stat.size);
    defer ally.free(file_buff);

    // Process the file.
    const num = try process(ally, file_buff);
    std.debug.print("{d}\n", .{num});
}
