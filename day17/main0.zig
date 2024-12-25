const std = @import("std");

const Allocator = std.mem.Allocator;

const Endpoint = u16;
const Connections = std.AutoHashMap(Endpoint, Connection);
const Graph = std.AutoHashMap(Endpoint, Connections);

const Connection = enum(u1) {
    Free,
    Blocked,
};

const Trackable = struct {
    me: Endpoint,
    from: Endpoint,
    target: Endpoint,

    depth: usize,
    pickle: usize,
};

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
    return (@as(Endpoint, @intCast(s[1])) << MoveBits) |
        @as(Endpoint, @intCast(s[0]));
}

/// Returns a Cycle hash based off the 3 given Endpoints.
const Cycles = struct {
    const Self = @This();
    const Cycle = u48;

    ally: Allocator,
    data: std.AutoHashMap(Cycle, void),

    fn init(ally: Allocator) Cycles {
        return Self{
            .ally = ally,
            .data = std.AutoHashMap(Cycle, void).init(ally),
        };
    }

    fn deinit(self: *Self) void {
        self.data.deinit();
    }

    /// Hashes the three given endpoints to form a cycle.
    /// If the cycle is already present, returns false.
    /// Otherwise, stores it and returns true.
    fn hash(self: *Self, es: *const [3]Endpoint) !bool {
        std.debug.print(
            "Given {s}-{s}-{s},",
            .{
                endpointAsSlice(&es[0]),
                endpointAsSlice(&es[1]),
                endpointAsSlice(&es[2]),
            },
        );

        std.sort.block(Endpoint, @constCast(es), {}, std.sort.asc(Endpoint));

        const cycle = (@as(Cycle, @intCast(es[2])) << @bitSizeOf(Endpoint) * 2) |
            @as(Cycle, @intCast(es[1])) << @bitSizeOf(Endpoint) |
            @as(Cycle, @intCast(es[0]));

        const cycleh = endpointAsSlice(&es[0]) ++ endpointAsSlice(&es[1]) ++ endpointAsSlice(&es[2]);

        const has_t = blk: {
            for (es) |e| {
                if ((e & 0x00ff) ^ @as(@TypeOf(e), 't') == 0) break :blk true;
            }
            break :blk false;
        };

        std.debug.print(
            "hash = {s}, has_t = {}\n",
            .{
                cycleh,
                has_t,
            },
        );

        return try self.data.fetchPut(cycle, {}) == null and has_t;
    }
};

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
            try connections.put(to, .Free);
        } else {
            var connections = Connections.init(ally);
            try connections.put(to, .Free);
            try graph.put(from, connections);
        }

        if (graph.getPtr(to)) |connections| {
            try connections.put(from, .Free);
        } else {
            var connections = Connections.init(ally);
            try connections.put(from, .Free);
            try graph.put(to, connections);
        }
    }

    return .{ graph, from };
}

fn dfs(graph: *Graph, trackable: Trackable, cycles: *Cycles) !usize {
    if (trackable.depth == 3) {
        // if ((trackable.me == trackable.target) and (trackable.pickle < 3)) return 1;
        return 0;
    }

    var loops: usize = 0;
    var connections = graph.get(trackable.me).?.iterator();

    while (connections.next()) |connection| {
        const neighbour: Endpoint = connection.key_ptr.*;
        const edge: *Connection = connection.value_ptr;

        if (neighbour == trackable.from) continue;

        // std.debug.print(
        //     "Want to reach {s} from {s}, continue through {s} at depth {d}, but new pickle will be {d}\n",
        //     .{
        //         endpointAsSlice(&trackable.target),
        //         endpointAsSlice(&trackable.me),
        //         endpointAsSlice(&neighbour),
        //         trackable.depth,
        //         trackable.pickle + @intFromEnum(edge.*),
        //     },
        // );

        const npickle = trackable.pickle + @intFromEnum(edge.*);
        if ((neighbour == trackable.target) and (trackable.depth == 2) and (npickle < 3)) {
            // edge.* = .Blocked;

            // const dedge = graph.get(neighbour).?.getPtr(trackable.me).?;
            // dedge.* = .Blocked;

            // std.debug.print(
            //     "\nLoop {s}-{s}-{s}\n\n",
            //     .{
            //         endpointAsSlice(&trackable.target),
            //         endpointAsSlice(&trackable.me),
            //         endpointAsSlice(&trackable.from),
            //     },
            // );

            // std.debug.print(
            //     "Marking edge {s}-{s} directional\n",
            //     .{
            //         endpointAsSlice(&trackable.me),
            //         endpointAsSlice(&neighbour),
            //     },
            // );

            loops += @intFromBool(
                try cycles.hash(&.{
                    trackable.target,
                    trackable.me,
                    trackable.from,
                }),
            );

            continue;
        }

        const local_loops = try dfs(
            graph,
            Trackable{
                .me = neighbour,
                .from = trackable.me,
                .target = trackable.target,
                .depth = trackable.depth + 1,
                .pickle = npickle,
            },
            cycles,
        );

        loops += local_loops;
    }

    return loops;
}

fn process(ally: Allocator, buff: []u8) !usize {
    var graph, _ = try read_graph(ally, buff);

    var cycles = Cycles.init(ally);
    defer cycles.deinit();

    var loops: usize = 0;

    var kit = graph.keyIterator();
    while (kit.next()) |key_ptr| {
        const root = key_ptr.*;

        loops += try dfs(
            &graph,
            Trackable{
                .me = root,
                .from = root,
                .target = root,
                .depth = 0,
                .pickle = 0,
            },
            &cycles,
        );
    }

    {
        // Free graph values.
        var vit = graph.valueIterator();
        while (vit.next()) |connections| {
            connections.deinit();
        }
        graph.deinit();
    }

    return loops;
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
