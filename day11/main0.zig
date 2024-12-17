const std = @import("std");

const Allocator = std.mem.Allocator;

const Program = []usize;
const Registers = struct {
    A: *usize,
    B: *usize,
    C: *usize,
    data: [3]usize,

    fn refresh(self: *Registers) void {
        self.A = &data[0];
        self.B = &data[1];
        self.C = &data[2];
    }
};

const OpCode = enum(usize) {
    adv, // A = A / 2^combo_operand.
    bxl, // B = B xor lit_operand.
    bst, // B = combo_operand % 8.
    jnz, // A == 0: no-op, A > 0: ptr = lit_operand.
    bxc, // B = B xor C.
    out, // combo_operand % 8, write to output.
    bdv, // B = A / 2^combo_operand.
    cdv, // C = A / 2^combo_operand.
};

fn parse(ally: Allocator, buf: []u8) !struct { Registers, Program } {
    var rgs: Registers = undefined;
    defer rgs.refresh();

    var prg_array = std.ArrayList(usize).init(ally);
    defer prg_array.deinit();

    var lineIt = std.mem.tokenizeScalar(u8, buf, '\n');
    var line_i: usize = 0;
    while (lineIt.next()) |line| : (line_i += 1) {
        if (line_i < 3) {
            // Read register values.
            const trim_l = "Register A: ".len;
            const val = try std.fmt.parseInt(usize, line[trim_l..], 10);
            rgs.data[line_i] = val;
            continue;
        }

        // Read program code.
        const trim_l = "Program: ".len;
        var it = std.mem.tokenizeScalar(u8, line[trim_l..], ',');
        while (it.next()) |op| {
            std.debug.print("{s}\n", .{op});
            const val = try std.fmt.parseInt(usize, op, 10);
            try prg_array.append(val);
        }
    }

    return .{ rgs, try prg_array.toOwnedSlice() };
}

fn process(ally: Allocator, buf: []u8) !usize {
    const rgs, const prg = try parse(ally, buf);
    std.debug.print("{any}\n{any}\n", .{ rgs, prg });

    var ptr: usize = 0;
    while (true) {
        // Operation code is the instruction type.
        const opcode: OpCode = @enumFromInt(prg[ptr]);

        // Evaluate ultimate operands.
        const lit_operand: usize = prg[ptr + 1];
        const combo_operand: usize = switch (lit_operand) {
            0...3 => |val| val,
            4 => rgs.A.*,
            5 => rgs.B.*,
            6 => rgs.C.*,
            7 => unreachable,
            else => unreachable,
        };

        switch (opcode) {
            .adv => rgs.A.* /= 2 << combo_operand, // A = A / 2^combo_operand.
            .bxl => rgs.B.* ^= combo_operand, // B = B xor lit_operand.
            .bst => rgs.B.* = @mod(combo_operand, 8), // B = combo_operand % 8.
            .jnz => {
                // A == 0: no-op, A > 0: ptr = lit_operand.
                if (rgs.A.* == 0) continue;
                ptr = lit_operand;
            },
            .bxc => rgs.B.* ^= rgs.C.*, // B = B xor C.
            .out => {}, // combo_operand % 8, write to output.
            .bdv => rgs.B.* = rgs.A.* / (2 << combo_operand), // B = A / 2^combo_operand.
            .cdv => rgs.C.* = rgs.A.* / (2 << combo_operand), // C = A / 2^combo_operand.
        }

        ptr += 2;
    }

    return 0;
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
    const out = try process(pg_ally, file_buff);
    std.debug.print("{}\n", .{out});
}
