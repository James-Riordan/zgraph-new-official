const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

fn createGraph() !IncidenceMatrix(false, true) {
    var block_alloc = try BlockAllocator.init(std.heap.page_allocator, 1024);
    defer block_alloc.deinit();
    const allocator = block_alloc.getAllocator();
    return IncidenceMatrix(false, true).init(allocator, 10);
}

const BlockAllocator = struct {
    allocator: std.mem.Allocator,
    block_size: usize,
    blocks: std.ArrayList([]i8),

    pub fn init(underlying_allocator: std.mem.Allocator, block_size: usize) !BlockAllocator {
        return BlockAllocator{
            .allocator = underlying_allocator,
            .block_size = block_size,
            .blocks = std.ArrayList([]i8).init(underlying_allocator),
        };
    }

    pub fn getAllocator(self: *BlockAllocator) std.mem.Allocator {
        return self.allocator;
    }

    pub fn allocate(self: *BlockAllocator) ![]i8 {
        const block = try self.allocator.alloc(i8, self.block_size);
        try self.blocks.append(block);
        return block;
    }

    pub fn deinit(self: *BlockAllocator) void {
        for (self.blocks.items) |block| {
            self.allocator.free(block);
        }
        self.blocks.deinit();
    }
};

/// Incidence Matrix Graph Structure
/// Supports directed/undirected and weighted/unweighted graphs.
/// Uses an incidence matrix for edge representation.
pub fn IncidenceMatrix(comptime directed: bool, comptime weighted: bool) type {
    return struct {
        const Mutex = std.Thread.Mutex;

        allocator: Allocator,
        matrix: std.ArrayList([]if (weighted) ?f64 else i8),
        node_count: usize,
        edge_count: usize,
        edge_set: std.AutoHashMap(struct { usize, usize }, void),
        mutex: Mutex,

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !@This() {
            var matrix = std.ArrayList([]if (weighted) ?f64 else i8).initCapacity(allocator, initial_capacity) catch |err| {
                return err;
            };

            for (0..initial_capacity) |_| {
                const row = try allocator.alloc(if (weighted) ?f64 else i8, 0);
                try matrix.append(row);
            }

            return @This(){
                .allocator = allocator,
                .matrix = matrix,
                .node_count = initial_capacity,
                .edge_count = 0,
                .edge_set = std.AutoHashMap(struct { usize, usize }, void).init(allocator),
                .mutex = Mutex{},
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.matrix.items) |row| {
                self.allocator.free(row);
            }
            self.matrix.deinit();
            self.edge_set.deinit();
        }

        fn resizeMatrix(self: *@This(), node_id: usize, new_capacity: usize) !void {
            if (node_id >= self.node_count) return error.InvalidNode;

            if (self.matrix.items[node_id].len < new_capacity) {
                self.matrix.items[node_id] = try self.allocator.realloc(self.matrix.items[node_id], new_capacity);
                @memset(self.matrix.items[node_id][self.edge_count..new_capacity], if (weighted) null else 0);
            }
        }

        pub fn addNode(self: *@This()) !usize {
            const new_id = self.node_count;
            self.node_count += 1;

            const new_row = try self.allocator.alloc(if (weighted) ?f64 else i8, self.edge_count);
            @memset(new_row, if (weighted) @as(?f64, null) else @as(i8, 0));

            try self.matrix.append(new_row);

            return new_id;
        }

        pub fn removeNode(self: *@This(), node_id: usize) !void {
            if (node_id >= self.node_count) return error.InvalidNode;

            self.mutex.lock();
            defer self.mutex.unlock();

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (key[0] == node_id or key[1] == node_id) {
                    _ = self.edge_set.remove(key);
                }
            }

            self.allocator.free(self.matrix.items[node_id]);
            _ = self.matrix.orderedRemove(node_id);

            self.node_count -= 1;
        }

        pub fn addEdge(self: *@This(), src: usize, dst: usize, weight: if (weighted) ?f64 else void) !usize {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.edge_set.contains(.{ src, dst })) return error.EdgeAlreadyExists;

            // ✅ Use resizeMatrix to ensure rows are large enough
            try self.resizeMatrix(src, self.edge_count + 1);
            try self.resizeMatrix(dst, self.edge_count + 1);

            if (weighted) {
                self.matrix.items[src][self.edge_count] = weight.?;
                self.matrix.items[dst][self.edge_count] = if (directed) -weight.? else weight.?;
            } else {
                self.matrix.items[src][self.edge_count] = 1;
                self.matrix.items[dst][self.edge_count] = if (directed) -1 else 1;
            }

            try self.edge_set.put(.{ src, dst }, {});
            if (!directed) {
                try self.edge_set.put(.{ dst, src }, {});
            }

            self.edge_count += 1;

            return self.edge_count - 1;
        }

        pub fn hasEdge(self: *@This(), src: usize, dst: usize) bool {
            if (src >= self.node_count or dst >= self.node_count) return false;

            if (self.edge_set.contains(.{ src, dst })) {
                return true;
            }

            for (0..self.edge_count) |edge_id| {
                if (self.matrix.items[src].len > edge_id and self.matrix.items[dst].len > edge_id) {
                    if ((weighted and self.matrix.items[src][edge_id] != null) or (!weighted and self.matrix.items[src][edge_id] != 0)) {
                        return true;
                    }
                }
            }

            return false;
        }

        pub fn updateEdgeWeight(self: *@This(), src: usize, dst: usize, new_weight: f64) !void {
            if (!weighted) return error.GraphNotWeighted;
            if (!self.hasEdge(src, dst)) return error.EdgeDoesNotExist;

            self.mutex.lock(); // 🔒 Ensure thread safety
            defer self.mutex.unlock();

            self.matrix.items[src][self.edge_count - 1] = new_weight;
            self.matrix.items[dst][self.edge_count - 1] = if (directed) -new_weight else new_weight;
        }

        pub fn reserveEdges(self: *@This(), additional_edges: usize) !void {
            const new_capacity = self.edge_count + additional_edges;

            for (0..self.node_count) |node_id| {
                try self.resizeMatrix(node_id, new_capacity);
            }
        }

        pub fn prepareParallelEdges(self: *@This(), additional_edges: usize) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (0..self.node_count) |node_id| {
                try self.resizeMatrix(node_id, self.edge_count + additional_edges);
            }
        }

        pub fn addEdgesParallel(self: *@This(), start: usize, end: usize) !void {
            const num_threads = try std.Thread.getCpuCount();
            var threads = try std.ArrayList(std.Thread).initCapacity(self.allocator, num_threads);
            defer threads.deinit();

            // Precompute batches
            var batches = try self.allocator.alloc(std.ArrayList(struct { usize, usize }), num_threads);
            defer self.allocator.free(batches);

            for (0..num_threads) |i| {
                batches[i] = std.ArrayList(struct { usize, usize }).init(self.allocator);
                errdefer batches[i].deinit();
            }

            for (start..end) |i| {
                for (i + 1..self.node_count) |j| {
                    try batches[i % num_threads].append(.{ i, j });
                }
            }

            for (0..num_threads) |i| {
                try threads.append(try std.Thread.spawn(.{}, worker, .{ self, batches[i].items }));
            }

            for (threads.items) |*thread| {
                thread.join();
            }

            for (0..num_threads) |i| {
                batches[i].deinit();
            }
        }

        pub fn worker(graph: *IncidenceMatrix(false, false), edges: []struct { usize, usize }) void {
            var count: usize = 0;
            for (edges) |edge| {
                _ = graph.addEdge(edge[0], edge[1], {}) catch |err| {
                    if (err == error.EdgeAlreadyExists) continue;
                    continue;
                };
                count += 1;
            }
        }

        pub fn removeEdge(self: *@This(), edge_id: usize) !void {
            if (edge_id >= self.edge_count) return; // ✅ Prevent out-of-bounds removal

            self.mutex.lock();
            defer self.mutex.unlock();

            // Collect edges to remove
            var edges_to_remove = std.ArrayList(struct { usize, usize }).init(self.allocator);
            defer edges_to_remove.deinit();

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (self.matrix.items[key[0]].len > edge_id and self.matrix.items[key[1]].len > edge_id) {
                    try edges_to_remove.append(key);
                }
            }

            // Remove collected edges
            for (edges_to_remove.items) |edge| {
                _ = self.edge_set.remove(edge);
                if (!directed) {
                    _ = self.edge_set.remove(.{ edge[1], edge[0] }); // ✅ Remove reverse for undirected graphs
                }
            }

            // ✅ Shift adjacency matrix elements left to remove the edge
            for (self.matrix.items) |*row| {
                if (row.*.len > 0 and edge_id < row.*.len - 1) { // 🔥 Fix integer overflow
                    @memcpy(row.*[edge_id .. row.*.len - 1], row.*[edge_id + 1 ..]);
                }

                if (row.*.len > 0) { // 🔥 Only shrink if there's something left
                    row.* = try self.allocator.realloc(row.*, row.*.len - 1);
                }
            }

            self.edge_count -= 1;
        }

        pub fn getNeighbors(self: *@This(), node_id: usize) !std.ArrayList(usize) {
            if (node_id >= self.node_count) return error.InvalidNode;

            var neighbors = std.ArrayList(usize).init(self.allocator);
            errdefer neighbors.deinit();

            var seen = std.AutoHashMap(usize, bool).init(self.allocator);
            defer seen.deinit();

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (key[0] == node_id) {
                    if (!seen.contains(key[1])) {
                        try seen.put(key[1], true);
                        try neighbors.append(key[1]);
                    }
                } else if (key[1] == node_id) {
                    if (!seen.contains(key[0])) {
                        try seen.put(key[0], true);
                        try neighbors.append(key[0]);
                    }
                }
            }

            return neighbors;
        }

        pub fn toAdjacencyList(self: *@This()) !std.AutoHashMap(usize, std.ArrayList(usize)) {
            var adj_list = std.AutoHashMap(usize, std.ArrayList(usize)).init(self.allocator);
            errdefer adj_list.deinit();

            for (0..self.node_count) |node| {
                const neighbors = try self.getNeighbors(node);
                try adj_list.put(node, neighbors);
            }

            return adj_list;
        }
    };
}

fn getRandomNode(max: usize) usize {
    var buf: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&buf)); // Fill the `u64` buffer with random bytes
    return @as(usize, buf % max); // Ensure the value is within range
}

test "IncidenceMatrix: Initialize and Deinitialize" {
    std.debug.print("\n====== Test: Initialization ======\n", .{});
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(true, true).init(allocator, 5);
    defer matrix.deinit();

    try std.testing.expectEqual(@as(usize, 5), matrix.node_count);
    try std.testing.expectEqual(@as(usize, 0), matrix.edge_count);
}

test "IncidenceMatrix: Add and Remove Nodes" {
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(true, true).init(allocator, 2);
    defer matrix.deinit();

    const id = try matrix.addNode();
    try std.testing.expectEqual(@as(usize, 3), matrix.node_count);
    try std.testing.expect(id == 2);
}

test "IncidenceMatrix: Add and Remove Edges" {
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    const edge_id = try matrix.addEdge(0, 1, 3.5);
    try std.testing.expectEqual(@as(usize, 1), matrix.edge_count);

    try matrix.removeEdge(edge_id);
    try std.testing.expectEqual(@as(usize, 0), matrix.edge_count);
}

test "IncidenceMatrix: Get Neighbors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 4);
    defer matrix.deinit();

    _ = try matrix.addEdge(1, 2, {});
    _ = try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    // ✅ Ensure we have exactly 2 neighbors
    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);

    // ✅ Ensure both 2 and 3 exist, regardless of order
    try std.testing.expect((neighbors.items[0] == 2 and neighbors.items[1] == 3) or
        (neighbors.items[0] == 3 and neighbors.items[1] == 2));
}

test "IncidenceMatrix: Get Neighbors (Debug Check)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 4);
    defer matrix.deinit();

    _ = try matrix.addEdge(1, 2, {});
    _ = try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    // ✅ Ensure exactly 2 neighbors
    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);

    // ✅ Check that both 2 and 3 exist, regardless of order
    try std.testing.expect((neighbors.items[0] == 2 and neighbors.items[1] == 3) or
        (neighbors.items[0] == 3 and neighbors.items[1] == 2));
}

test "IncidenceMatrix: Invalid Node in AddEdge" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    const result = matrix.addEdge(0, 10, 2.5);
    try std.testing.expectError(error.InvalidNode, result);
}

test "IncidenceMatrix: Invalid Edge Removal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    try matrix.removeEdge(10); // ✅ Should not panic
}

test "IncidenceMatrix: Directed Edge Correctness" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, false).init(allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addEdge(0, 1, {});

    if (matrix.matrix.items.len > 0) {
        try std.testing.expectEqual(@as(i8, 1), matrix.matrix.items[0][0]);
    } else return error.RowNotAllocated;

    if (matrix.matrix.items.len > 1) {
        try std.testing.expectEqual(@as(i8, -1), matrix.matrix.items[1][0]);
    } else return error.RowNotAllocated;
}

test "IncidenceMatrix: Weighted Edge Correctness" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addEdge(0, 1, 7.5);

    if (matrix.matrix.items.len > 0) {
        try std.testing.expectEqual(@as(f64, 7.5), matrix.matrix.items[0][0]);
    } else return error.RowNotAllocated;

    if (matrix.matrix.items.len > 1) {
        try std.testing.expectEqual(@as(f64, -7.5), matrix.matrix.items[1][0]);
    } else return error.RowNotAllocated;
}

test "IncidenceMatrix: High-Precision Edge Weights" {
    var matrix = try IncidenceMatrix(true, true).init(std.heap.page_allocator, 5);
    defer matrix.deinit();

    _ = try matrix.addEdge(0, 1, 1.0000001);
    _ = try matrix.addEdge(1, 2, 3.1415926535);

    try std.testing.expectEqual(@as(f64, 1.0000001), matrix.matrix.items[0][0]);
    try std.testing.expectEqual(@as(f64, -3.1415926535), matrix.matrix.items[2][1]);
}

test "IncidenceMatrix: Large Fully Connected Graph" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 100);
    defer matrix.deinit();

    for (0..100) |i| {
        for (i + 1..100) |j| {
            _ = try matrix.addEdge(i, j, {});
        }
    }

    try std.testing.expectEqual(@as(usize, 100 * 99 / 2), matrix.edge_count);
}

test "IncidenceMatrix: Large Dense Graph (Optimized)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const node_count = 100;
    var matrix = try IncidenceMatrix(false, true).init(allocator, node_count);
    defer matrix.deinit();

    for (0..node_count) |i| {
        for (i + 1..node_count) |j| {
            _ = try matrix.addEdge(i, j, @floatFromInt(i + j));
        }
    }

    try std.testing.expectEqual(@as(usize, node_count * (node_count - 1) / 2), matrix.edge_count);
}

test "IncidenceMatrix: Large Dense Graph (Parallel, Optimized)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // ✅ Use GPA for parallel test
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const node_count = 100;
    var matrix = try IncidenceMatrix(false, false).init(allocator, node_count);
    defer matrix.deinit();

    try matrix.prepareParallelEdges(node_count * (node_count - 1) / 2);

    // **✅ New Parallel Edge Processing**
    try matrix.addEdgesParallel(0, node_count);

    try std.testing.expectEqual(@as(usize, node_count * (node_count - 1) / 2), matrix.edge_count);
}

test "IncidenceMatrix: Massive Graph Stress Test" {
    var matrix = try IncidenceMatrix(false, false).init(std.heap.page_allocator, 1000);
    defer matrix.deinit();

    for (0..1000) |i| {
        for (i + 1..1000) |j| {
            _ = try matrix.addEdge(i, j, {});
        }
    }

    try std.testing.expectEqual(@as(usize, 1000 * 999 / 2), matrix.edge_count);
}
