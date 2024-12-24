const std = @import("std");

const Allocator = std.mem.Allocator;
const Generations = @as(usize, 2000);

const Secret = usize;
const Keep = @as(Secret, 0xffffff);

const Digit = i8;
const SequenceSize = @as(usize, 4);
const Sequence = packed struct {
    n1: Digit,
    n2: Digit,
    n3: Digit,
    n4: Digit,
};

const SequenceBucket = std.AutoHashMap(Secret, usize);
const SequenceHashMap = std.AutoHashMap(Sequence, SequenceBucket);

// Evolves the given secret number into its next generation.
inline fn evolve(secret: Secret) Secret {
    var s = (secret ^ (secret << 6)) & Keep;
    s = (s ^ (s >> 5)) & Keep;
    return (s ^ (s << 11)) & Keep;
}

fn process(ally: Allocator, buff: []const u8) !usize {
    // Cache pairs Sequence with the total numbers of bananas she yields.
    var cache = SequenceHashMap.init(ally);
    defer cache.deinit();

    var it = std.mem.tokenizeScalar(u8, buff, '\n');
    while (it.next()) |token| {
        var secret = try std.fmt.parseInt(Secret, token, 10);
        const secret_backup = secret;

        // Sequence holds the last 4 price digits.
        // It is a bit cast from Sequence structure type to
        // easily iterate over and rotate its memory.
        var seq: [SequenceSize]Digit = @bitCast(Sequence{
            .n1 = undefined,
            .n2 = undefined,
            .n3 = undefined,
            .n4 = undefined,
        });

        var seq_nprev: Digit = @intCast(secret % 10);

        // Checkout the first 3 price changes.
        inline for (1..seq.len) |i| {
            secret = evolve(secret);

            const seq_nnew: Digit = @intCast(secret % 10);
            seq[i] = seq_nnew - seq_nprev;
            seq_nprev = seq_nnew;
        }

        for (seq.len..Generations) |_| {
            // A more efficient way of rotating a slice by 1.
            std.mem.copyForwards(Digit, seq[0 .. seq.len - 1], seq[1..]);

            secret = evolve(secret);

            const seq_nnew: Digit = @intCast(secret % 10);
            seq[seq.len - 1] = seq_nnew - seq_nprev;
            seq_nprev = seq_nnew;

            // std.debug.print("Secret {d}: Writing seq: {any}, digit: {d}\n", .{ secret_backup, seq, seq_nprev });

            // Each secret is only allowed to cache its price once.
            const seq_inner: Sequence = @bitCast(seq);
            if (cache.getPtr(seq_inner)) |bucket| {
                if (!bucket.contains(secret_backup)) {
                    try bucket.put(secret_backup, @intCast(seq_nnew));
                }
            } else {
                var bucket = SequenceBucket.init(ally);
                try bucket.put(secret_backup, @intCast(seq_nnew));
                try cache.put(seq_inner, bucket);
            }
        }
    }

    var max: usize = 0;
    var max_key: *Sequence = undefined;

    var cache_it = cache.iterator();
    while (cache_it.next()) |entry| {
        const bucket = entry.value_ptr;

        var value: usize = 0;
        var bucket_vit = bucket.valueIterator();
        while (bucket_vit.next()) |value_ptr| {
            value += value_ptr.*;
        }

        if (value > max) {
            max = value;
            max_key = entry.key_ptr;
        }

        bucket.deinit();
    }

    // std.debug.print("Seq with max price: {any}\n", .{max_key.*});
    return max;
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
    const sum = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{sum});
}
