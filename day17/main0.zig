const std = @import("std");

const Allocator = std.mem.Allocator;

const Endpoint = u16;
const Connections = std.AutoHashMap(Endpoint, void);
const Graph = std.AutoHashMap(Endpoint, Connections);

const Trackable = struct {
    const Self = @This();

    me: Endpoint,
    target: Endpoint,

    depth: usize,

    fn compareFn(_: void, a: Self, b: Self) std.math.Order {
        const target_order = std.math.order(b.target, a.target);
        if (target_order != .eq) return target_order;

        const depth_order = std.math.order(b.depth, a.depth);
        if (depth_order == .eq) return std.math.order(b.me, a.me);
        return depth_order;
    }
};

const Queue = std.PriorityQueue(Trackable, void, Trackable.compareFn);

const MoveBits = @bitSizeOf(u8);
const DescriptorSize = 2 + 1 + 2; // In bytes.

/// Returns a copy of the given endpoint as a string.
fn sliceFromEndpoint(e: Endpoint) [2]u8 {
    return [2]u8{
        @intCast(e & ((1 << MoveBits) - 1)),
        @intCast(e >> MoveBits),
    };
}

/// Returns the given endpoint interpreted as a string.
/// Modifying the resulting string modifies the endpoint.
fn endpointAsSlice(e: *const Endpoint) *const [2]u8 {
    return @ptrCast(e);
}

/// Returns a copy of the given string as an endpoint.
fn endpointFromSlice(s: *const [2]u8) Endpoint {
    return (@as(Endpoint, @intCast(s[1])) << MoveBits) +
        @as(Endpoint, @intCast(s[0]));
}

/// Reads a graph of connections from the buff.
/// Call deinit on the result to free the memory.
fn read_graph(ally: Allocator, buff: []u8) !struct { Graph, Endpoint } {
    var graph = Graph.init(ally);

    var from: Endpoint = undefined;

    var it = std.mem.tokenizeScalar(u8, buff, '\n');
    while (it.next()) |line| { // Parse connection descriptors.
        if (line.len != DescriptorSize) {
            @panic("Invalid descriptor size");
        }

        var ds: *const [DescriptorSize]u8 = @ptrCast(line.ptr);

        from = endpointFromSlice(ds[0..2]);
        const to = endpointFromSlice(ds[3..]);

        // Assign bi-directional connections.

        if (graph.getPtr(from)) |connections| {
            try connections.put(to, void{});
        } else {
            var connections = Connections.init(ally);
            try connections.put(to, void{});
            try graph.put(from, connections);
        }

        if (graph.getPtr(to)) |connections| {
            try connections.put(from, void{});
        } else {
            var connections = Connections.init(ally);
            try connections.put(from, void{});
            try graph.put(to, connections);
        }
    }

    return .{ graph, from };
}

fn process(ally: Allocator, buff: []u8) !usize {
    var graph, const first = try read_graph(ally, buff);
    defer graph.deinit();

    // blk: {
    //     // Test connections from kh computer.
    //     const kh = graph.get(endpointFromSlice("kh")) orelse break :blk;
    //
    //     var kit = kh.keyIterator();
    //     while (kit.next()) |key_ptr| {
    //         std.debug.print("kh-{s}\n", .{endpointAsSlice(key_ptr)});
    //     }
    // }

    var visited = std.AutoHashMap(Endpoint, void).init(ally);
    defer visited.deinit();

    var queue = Queue.init(ally, void{});
    defer queue.deinit();

    try queue.add(
        Trackable{
            .me = first,
            .target = first,
            .depth = 0,
        },
    );

    // var decade: usize = 0;
    while (queue.removeOrNull()) |trackable| {
        // if (trackable.depth > 3) continue;
        if (trackable.me == trackable.target) {
            // if (trackable.depth == 3) {
            // Found a loop.
            std.debug.print("Found a loop to {s}\n", .{endpointAsSlice(&trackable.target)});
            // continue;
            // } else if (trackable.depth != 0) continue;
        } else if ((trackable.depth == 0) and (visited.contains(trackable.me))) {
            // std.debug.print("??Found a loop to {s}\n", .{endpointAsSlice(&trackable.target)});
            continue;
        }

        var from_me = graph.get(trackable.me).?.keyIterator();
        while (from_me.next()) |target_ptr| {
            const target: Endpoint = target_ptr.*;

            try queue.add(
                Trackable{
                    .me = target,
                    .target = trackable.target,
                    .depth = trackable.depth + 1,
                },
            );

            // if (visited.contains(target)) continue;

            // try queue.add(
            //     Trackable{
            //         .me = target,
            //         .target = target,
            //         .depth = 0,
            //     },
            // );
        }

        if (trackable.depth == 0) {
            if (visited.contains(trackable.me)) {
                std.debug.print("Btw, {any} already visited ({s})\n", .{ trackable, endpointAsSlice(&trackable.me) });
            }
            try visited.putNoClobber(trackable.me, void{});
        } else if (!visited.contains(trackable.me)) {
            try queue.add(
                Trackable{
                    .me = trackable.me,
                    .target = trackable.target,
                    .depth = 0,
                },
            );
        }

        // decade += 1;
        // if (decade > 7) break;
    }

    {
        std.debug.print("After evaluating {s}:\n", .{endpointAsSlice(&first)});

        while (queue.removeOrNull()) |trackable| {
            std.debug.print("In Queue: ( {s}->{s}, {d} )\n", .{
                endpointAsSlice(&trackable.me),
                endpointAsSlice(&trackable.target),
                trackable.depth,
            });
        }
    }

    // {
    //     var it = graph.iterator();
    //     while (it.next()) |entry| {
    //         var kit1 = entry.value_ptr.keyIterator();
    //
    //         while (kit1.next()) |second_ptr| {
    //             if (visited.contains(second_ptr.*)) continue;
    //
    //             var kit2 = graph.get(second_ptr.*).?.keyIterator();
    //
    //             while (kit2.next()) |third_ptr| {
    //                 if (visited.contains(third_ptr.*)) continue;
    //
    //                 if (graph.get(third_ptr.*).?.contains(entry.key_ptr.*)) {
    //                     std.debug.print("Loop: {s}-{s}-{s}\n", .{
    //                         endpointAsSlice(entry.key_ptr),
    //                         endpointAsSlice(second_ptr),
    //                         endpointAsSlice(third_ptr),
    //                     });
    //
    //                     break;
    //                 }
    //             }
    //         }
    //
    //         try visited.put(entry.key_ptr.*, void{});
    //     }
    // }

    {
        // Free graph values.
        var vit = graph.valueIterator();
        while (vit.next()) |connections| {
            connections.deinit();
        }
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
    const count = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{count});
}
