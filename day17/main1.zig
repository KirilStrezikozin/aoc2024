const std = @import("std");

const Allocator = std.mem.Allocator;

const Endpoint = u16;
const Set = std.AutoHashMap(Endpoint, void);
const Graph = std.AutoHashMap(Endpoint, Set);

const Trackable = struct {
    me: Endpoint,
    from: Endpoint,
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

fn lessThan(_: void, lhs: Endpoint, rhs: Endpoint) bool {
    return std.mem.order(u8, endpointAsSlice(&lhs), endpointAsSlice(&rhs)) == .lt;
}

/// Hashes the given set of Endpoints into a slice of Endpoints
/// ordered lexicographically. Caller owns the returned memory.
fn hash(ally: Allocator, set: *Set) ![]const Endpoint {
    var se = try ally.alloc(Endpoint, set.count());

    var i: usize = 0;
    var kit = set.keyIterator();
    while (kit.next()) |key_ptr| {
        se[i] = key_ptr.*;
        i += 1;
    }

    std.sort.block(Endpoint, se, {}, lessThan);

    return se;
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
            var connections = Set.init(ally);
            try connections.put(to, void{});
            try graph.put(from, connections);
        }

        if (graph.getPtr(to)) |connections| {
            try connections.put(from, void{});
        } else {
            var connections = Set.init(ally);
            try connections.put(from, void{});
            try graph.put(to, connections);
        }
    }

    return .{ graph, from };
}

fn dfs(graph: *Graph, trackable: Trackable, set: *Set) !void {
    var connections = graph.get(trackable.me).?.iterator();

    neighbours: while (connections.next()) |connection| {
        const neighbour: Endpoint = connection.key_ptr.*;

        if ((neighbour == trackable.from) or set.contains(neighbour)) continue;

        // Check if neighbour has connections to every member in set.
        var set_it = set.keyIterator();
        while (set_it.next()) |must| {
            if (!graph.get(neighbour).?.contains(must.*)) continue :neighbours;
        }

        try set.putNoClobber(neighbour, void{});

        // Inspect connections of this neighbour.
        try dfs(graph, Trackable{ .me = neighbour, .from = trackable.me }, set);
    }
}

fn process(ally: Allocator, buff: []u8) !usize {
    var graph, _ = try read_graph(ally, buff);

    var max: usize = 0;
    var password: []const Endpoint = undefined;

    var kit = graph.keyIterator();
    while (kit.next()) |key_ptr| {
        const root = key_ptr.*;

        var set = std.AutoHashMap(Endpoint, void).init(ally);
        try set.put(root, void{});

        try dfs(&graph, Trackable{ .me = root, .from = root }, &set);

        if (set.count() <= max) {
            set.deinit();
            continue;
        }

        if (max != 0) {
            ally.free(password);
        }

        max = set.count();
        password = try hash(ally, &set);
        set.deinit();
    }

    {
        // Free graph values.
        var vit = graph.valueIterator();
        while (vit.next()) |connections| {
            connections.deinit();
        }
        graph.deinit();
    }

    std.debug.print("Password is: ", .{});
    for (password) |e| {
        std.debug.print("{s},", .{endpointAsSlice(&e)});
    }
    std.debug.print("\n", .{});

    if (max != 0) {
        ally.free(password);
    }

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
    const count = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{count});
}
