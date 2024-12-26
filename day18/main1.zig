const std = @import("std");

const Allocator = std.mem.Allocator;

const Id = u24;
const State = u1;

const Outputs = std.AutoHashMap(Id, State);

const Procedure = struct {
    depends: [2]Id,
    output: Id,
    produce: *const fn (State, State) State,
    produce_utf: *const [3]u8,
};

const Zeta = struct {
    const Value = usize;

    // For our input, maximum zeta bit is 45,
    // which fits within the 64-bit usize type.
    bits: [@bitSizeOf(Value)]State,

    bits_x: [@bitSizeOf(Value)]State,
    bits_y: [@bitSizeOf(Value)]State,
    bits_sum: [@bitSizeOf(Value)]State,

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

    var zeta: Zeta = .{
        .bits = undefined,

        .bits_x = undefined,
        .bits_y = undefined,
        .bits_sum = undefined,

        .pending = 0,
    };

    @memset(&zeta.bits, @as(u1, 0));

    @memset(&zeta.bits_x, @as(u1, 0));
    @memset(&zeta.bits_y, @as(u1, 0));
    @memset(&zeta.bits_sum, @as(u1, 0));

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

            const id_utf = parser.next().?.ptr;

            const id = idFromSlice(@ptrCast(id_utf));
            const state: State = @intCast(parser.next().?[0] - '0');

            try outputs.putNoClobber(id, state);

            const z_bit = zeta.bits.len - 1 -
                (@as(usize, @intCast((id_utf[1] - '0'))) * 10 +
                @as(usize, @intCast(id_utf[2] - '0')));

            if (id_utf[0] == 'x') {
                zeta.bits_x[z_bit] = state;
            } else if (id_utf[0] == 'y') {
                zeta.bits_y[z_bit] = state;
            }

            continue;
        }

        var parser = std.mem.tokenizeScalar(u8, line, ' ');

        var procedure: Procedure = undefined;
        procedure.depends[0] = idFromSlice(@ptrCast(parser.next().?.ptr));

        const produce_utf = parser.next().?;
        procedure.produce = blk: {
            if (std.mem.order(u8, produce_utf, "XOR") == .eq) {
                procedure.produce_utf = "XOR";
                break :blk fnXor;
            } else if (std.mem.order(u8, produce_utf, "OR") == .eq) {
                procedure.produce_utf = " OR";
                break :blk fnOr;
            } else {
                procedure.produce_utf = "AND";
                break :blk fnAnd;
            }
        };

        procedure.depends[1] = idFromSlice(@ptrCast(parser.next().?.ptr));
        _ = parser.next().?;

        const output_utf: *const [3]u8 = @ptrCast(parser.next().?.ptr);
        procedure.output = idFromSlice(output_utf);

        // const input0 = outputs.get(procedure.depends[0]);
        // const input1 = outputs.get(procedure.depends[1]);
        //
        // if ((input0 != null) and
        //     (input1 != null))
        // {
        //     // Dependencies already satisfied,
        //     // produce output immediately.
        //
        //     const output = procedure.produce(input0.?, input1.?);
        //     try outputs.putNoClobber(procedure.output, output);
        //
        //     if (output_utf[0] == 'z') {
        //         // Assign this z bit to the final value.
        //         const z_bit = zeta.bits.len - 1 -
        //             (@as(usize, @intCast((output_utf[1] - '0'))) * 10 +
        //             @as(usize, @intCast(output_utf[2] - '0')));
        //         zeta.bits[z_bit] = output;
        //     }
        //
        //     continue;
        // }

        if (output_utf[0] == 'z') {
            zeta.pending += 1;
        }

        try procedures.append(procedure);
    }

    // Construct an expectable sum of two bit numbers.
    var carry: State = 0;
    for (0..zeta.bits.len) |ir| {
        const i = zeta.bits.len - 1 - ir;

        const s: u2 =
            @as(u2, @intCast(zeta.bits_x[i])) +
            @as(u2, @intCast(zeta.bits_y[i])) +
            @as(u2, @intCast(carry));

        if (s <= 1) {
            zeta.bits_sum[i] = @intCast(s);
            carry = 0;
        } else {
            zeta.bits_sum[i] = @intCast(s - 2);
            carry = 1;
        }
    }

    return .{ outputs, try procedures.toOwnedSlice(), zeta };
}

fn process(ally: Allocator, buff: []const u8) !usize {
    var outputs, const procedures, var zeta = try parse(ally, buff);

    defer {
        outputs.deinit();
        ally.free(procedures);
    }

    var queue = Queue.init(ally, .{});
    defer queue.deinit();

    var map = std.AutoHashMap(Id, Procedure).init(ally);
    defer map.deinit();

    // Add all procedures to the queue to await processing.
    for (procedures) |procedure| {
        try queue.add(procedure);
        try map.putNoClobber(procedure.output, procedure);
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

    std.debug.print("\n   X bits:", .{});
    for (zeta.bits_x) |bit| {
        std.debug.print("{d}", .{bit});
    }

    std.debug.print("\n   Y bits:", .{});
    for (zeta.bits_y) |bit| {
        std.debug.print("{d}", .{bit});
    }

    std.debug.print("\n", .{});

    std.debug.print("\nHave bits:", .{});
    for (zeta.bits) |bit| {
        std.debug.print("{d}", .{bit});
    }

    std.debug.print("\nWant bits:", .{});
    for (zeta.bits_sum) |bit| {
        std.debug.print("{d}", .{bit});
    }

    // std.debug.print("\nWant bits:0000000000000000001101100000010111000100110010011010001011001110", .{});

    std.debug.print("\n", .{});

    for (0..zeta.bits.len) |ir| {
        const i = zeta.bits.len - 1 - ir;

        if (zeta.bits[i] == zeta.bits_sum[i]) continue;
        std.debug.print("Wrong bit z{d}\n", .{ir});

        // For a n-bit full adder, each valid zxx output
        // (except z00, z45 - the first and the last bits) is determined by
        // solving the following combinations of gates:
        //
        //    zxx
        //     |
        //     |
        //    XOR
        //    | |
        //    | +---------------+
        //    |                 |
        //   XOR                OR
        //   | |               +  +
        //   | +-+             |  |
        //   |   |         +---+  +-------------------+   z(x-1)(x-1)
        //  xxx yxx        |                          |    ^
        //                 |                          |    |
        //                AND                        AND  XOR
        //                | |                        | |  | |
        //              +-+ |                        | +--+ |
        //              |   |                        | ^    |
        //     x(x-1)(x-1)  y(x-1)(x-1)              +------+
        //                                           |
        //                                           ^
        //
        // The first gate input that does not come from the correct
        // combination of gates should be swapped.

        const z_id = idFromSlice(&.{
            'z',
            @as(u8, @intCast(ir / 10)) + '0',
            @as(u8, @intCast(ir % 10)) + '0',
        });

        const z_id_lower = idFromSlice(&.{
            'z',
            @as(u8, @intCast((ir - 1) / 10)) + '0',
            @as(u8, @intCast((ir - 1) % 10)) + '0',
        });

        const z_procedure = map.get(z_id).?;
        const z_lower_procedure = map.get(z_id_lower).?;

        std.debug.print("Please have a look:\n", .{});
        std.debug.print("z{d} = {s} {s} {s}, should be XOR\n", .{
            ir,
            idAsSlice(&z_procedure.depends[0]),
            z_procedure.produce_utf,
            idAsSlice(&z_procedure.depends[1]),
        });

        if (map.get(z_procedure.depends[0])) |procedure_1_0| {
            std.debug.print("{s} = {s} {s} {s}, should be XOR or OR\n", .{
                idAsSlice(&procedure_1_0.output),
                idAsSlice(&procedure_1_0.depends[0]),
                procedure_1_0.produce_utf,
                idAsSlice(&procedure_1_0.depends[1]),
            });

            if (map.get(procedure_1_0.depends[0])) |procedure_2_0| {
                std.debug.print("{s} = {s} {s} {s}, should be AND\n", .{
                    idAsSlice(&procedure_2_0.output),
                    idAsSlice(&procedure_2_0.depends[0]),
                    procedure_2_0.produce_utf,
                    idAsSlice(&procedure_2_0.depends[1]),
                });

                std.debug.print("z{d} = {s} {s} {s}, ?should be {s} XOR {s}\n", .{
                    ir - 1,
                    idAsSlice(&procedure_2_0.depends[0]),
                    z_lower_procedure.produce_utf,
                    idAsSlice(&procedure_2_0.depends[1]),

                    idAsSlice(&z_lower_procedure.depends[0]),
                    idAsSlice(&z_lower_procedure.depends[1]),
                });
            }

            if (map.get(procedure_1_0.depends[1])) |procedure_2_1| {
                std.debug.print("{s} = {s} {s} {s}, should be AND\n", .{
                    idAsSlice(&procedure_2_1.output),
                    idAsSlice(&procedure_2_1.depends[0]),
                    procedure_2_1.produce_utf,
                    idAsSlice(&procedure_2_1.depends[1]),
                });

                std.debug.print("z{d} = {s} {s} {s}, ?should be {s} XOR {s}\n", .{
                    ir - 1,
                    idAsSlice(&procedure_2_1.depends[0]),
                    z_lower_procedure.produce_utf,
                    idAsSlice(&procedure_2_1.depends[1]),

                    idAsSlice(&z_lower_procedure.depends[0]),
                    idAsSlice(&z_lower_procedure.depends[1]),
                });
            }
        }

        if (map.get(z_procedure.depends[1])) |procedure_1_1| {
            std.debug.print("{s} = {s} {s} {s}, should be XOR or OR\n", .{
                idAsSlice(&procedure_1_1.output),
                idAsSlice(&procedure_1_1.depends[0]),
                procedure_1_1.produce_utf,
                idAsSlice(&procedure_1_1.depends[1]),
            });

            if (map.get(procedure_1_1.depends[0])) |procedure_2_0| {
                std.debug.print("{s} = {s} {s} {s}, should be AND\n", .{
                    idAsSlice(&procedure_2_0.output),
                    idAsSlice(&procedure_2_0.depends[0]),
                    procedure_2_0.produce_utf,
                    idAsSlice(&procedure_2_0.depends[1]),
                });

                std.debug.print("z{d} = {s} {s} {s}, ?should be {s} XOR {s}\n", .{
                    ir - 1,
                    idAsSlice(&procedure_2_0.depends[0]),
                    z_lower_procedure.produce_utf,
                    idAsSlice(&procedure_2_0.depends[1]),

                    idAsSlice(&z_lower_procedure.depends[0]),
                    idAsSlice(&z_lower_procedure.depends[1]),
                });
            }

            if (map.get(procedure_1_1.depends[1])) |procedure_2_1| {
                std.debug.print("{s} = {s} {s} {s}, should be AND\n", .{
                    idAsSlice(&procedure_2_1.output),
                    idAsSlice(&procedure_2_1.depends[0]),
                    procedure_2_1.produce_utf,
                    idAsSlice(&procedure_2_1.depends[1]),
                });

                std.debug.print("z{d} = {s} {s} {s}, ?should be {s} XOR {s}\n", .{
                    ir - 1,
                    idAsSlice(&procedure_2_1.depends[0]),
                    z_lower_procedure.produce_utf,
                    idAsSlice(&procedure_2_1.depends[1]),

                    idAsSlice(&z_lower_procedure.depends[0]),
                    idAsSlice(&z_lower_procedure.depends[1]),
                });
            }
        }

        std.debug.print("\n\n", .{});
    }

    // To swap:
    // z07 with gmt
    // cbj with qjj
    // z18 with dmn
    // z35 with cfk

    var to_swap = [_]Id{
        idFromSlice("z07"),
        idFromSlice("gmt"),
        idFromSlice("cbj"),
        idFromSlice("qjj"),
        idFromSlice("z18"),
        idFromSlice("dmn"),
        idFromSlice("z35"),
        idFromSlice("cfk"),
    };

    // var to_swap = try ally.alloc(Id, to_swap_sentinel.len);
    to_swap[0] = to_swap[0];
    // defer ally.free(to_swap);
    // @memcpy(to_swap.ptr, to_swap_sentinel);

    std.mem.sort(Id, &to_swap, {}, lessThan);

    for (to_swap) |output| {
        std.debug.print("{s},", .{idAsSlice(&output)});
    }
    std.debug.print("\n", .{});

    return zeta.asDecimal();
}

fn lessThan(_: void, lhs: Id, rhs: Id) bool {
    return std.mem.order(u8, idAsSlice(&lhs), idAsSlice(&rhs)) == .lt;
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
