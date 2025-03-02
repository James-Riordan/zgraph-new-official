const std = @import("std");
const Allocator = std.mem.Allocator;
const Edge = @import("../core/edge.zig").Edge;

pub fn AdjacencyMatrix(comptime directed: bool, comptime weighted: bool) type {
    return struct {
        allocator: Allocator,
        matrix: std.ArrayList([]if (weighted) ?f64 else bool),
        node_count: usize,

        pub fn init(allocator: Allocator, initial_capacity: usize) !@This() {
            var matrix = try std.ArrayList([]if (weighted) ?f64 else bool).initCapacity(allocator, initial_capacity);
            for (0..initial_capacity) |_| {
                const row = try allocator.alloc(if (weighted) ?f64 else bool, initial_capacity);
                @memset(row, if (weighted) null else false);
                try matrix.append(row);
            }

            return @This(){
                .allocator = allocator,
                .matrix = matrix,
                .node_count = initial_capacity,
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.matrix.items) |row| {
                self.allocator.free(row);
            }
            self.matrix.deinit();
        }

        pub fn addNode(self: *@This()) !usize {
            const new_id = self.node_count;
            self.node_count += 1;

            // Expand rows
            for (self.matrix.items) |*row| {
                row.* = try self.allocator.realloc(row.*, self.node_count);
                row.*[new_id] = if (weighted) null else false;
            }

            // Add new row
            const new_row = try self.allocator.alloc(if (weighted) ?f64 else bool, self.node_count);
            @memset(new_row, if (weighted) null else false);
            try self.matrix.append(new_row);

            return new_id;
        }

        pub fn removeNode(self: *@This(), node_id: usize) void {
            if (node_id >= self.node_count) return; // Prevent out-of-bounds removal

            // Free the row corresponding to `node_id`
            self.allocator.free(self.matrix.items[node_id]);

            // Shift rows up to fill the gap
            var i: usize = node_id;
            while (i < self.node_count - 1) : (i += 1) {
                self.matrix.items[i] = self.matrix.items[i + 1]; // ✅ Corrected
            }

            // Shrink matrix row array
            self.matrix.shrinkAndFree(self.node_count - 1);

            // Remove the corresponding column from each row
            for (self.matrix.items[0 .. self.node_count - 1]) |*row| {
                row.* = self.allocator.realloc(row.*, self.node_count - 1) catch unreachable;
            }

            // ✅ Update node count
            self.node_count -= 1;
        }

        pub fn addEdge(self: *@This(), src: usize, dst: usize, weight: if (weighted) ?f64 else void) !void {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;
            self.matrix.items[src][dst] = if (weighted) weight.? else true;
            if (!directed) {
                self.matrix.items[dst][src] = if (weighted) weight.? else true;
            }
        }

        pub fn removeEdge(self: *@This(), src: usize, dst: usize) !void {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;
            self.matrix.items[src][dst] = if (weighted) null else false;
            if (!directed) {
                self.matrix.items[dst][src] = if (weighted) null else false;
            }
        }

        pub fn getNeighbors(self: *@This(), node_id: usize) !std.ArrayList(usize) {
            if (node_id >= self.node_count) return error.InvalidNode;

            var neighbors = std.ArrayList(usize).init(self.allocator);
            errdefer neighbors.deinit();

            for (0..self.matrix.items[node_id].len) |i| { // ✅ Optimized iteration
                if (self.matrix.items[node_id][i] != if (weighted) null else false) {
                    try neighbors.append(i);
                }
            }
            return neighbors;
        }
    };
}

// Unit Tests
test "AdjacencyMatrix: Initialize and Deinitialize" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 5);
    defer matrix.deinit();
    try std.testing.expectEqual(@as(usize, 5), matrix.node_count);
}

test "AdjacencyMatrix: Add and Remove Nodes" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 2);
    defer matrix.deinit();

    const id = try matrix.addNode();
    try std.testing.expectEqual(@as(usize, 3), matrix.node_count);

    // ✅ Use `id` in the test to avoid unused constant error
    try std.testing.expect(id == 2); // The new node should be at index 2

    matrix.removeNode(1);
    try std.testing.expectEqual(@as(usize, 2), matrix.node_count);
}

test "AdjacencyMatrix: Add and Remove Edges" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(0, 1, 3.5);
    try std.testing.expect(matrix.matrix.items[0][1] != null);

    try matrix.removeEdge(0, 1);
    try std.testing.expect(matrix.matrix.items[0][1] == null);
}

test "AdjacencyMatrix: Get Neighbors" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 4);
    defer matrix.deinit();

    try matrix.addEdge(1, 2, {});
    try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit(); // ✅ Prevent memory leak

    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);
}
test "AdjacencyMatrix: Self-Loops" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(1, 1, 7.5);
    try std.testing.expect(matrix.matrix.items[1][1] == 7.5);
}

test "AdjacencyMatrix: Remove Nonexistent Edge" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.removeEdge(0, 2); // Should not panic or crash
}

test "AdjacencyMatrix: Add and Remove Many Nodes" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 2);
    defer matrix.deinit();

    for (0..10) |_| _ = try matrix.addNode();
    try std.testing.expectEqual(@as(usize, 12), matrix.node_count);

    for (0..5) |_| matrix.removeNode(0);
    try std.testing.expectEqual(@as(usize, 7), matrix.node_count);
}

test "AdjacencyMatrix: Remove Last Node" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    matrix.removeNode(2); // Should not panic or cause an error
    try std.testing.expectEqual(@as(usize, 2), matrix.node_count);
}

test "AdjacencyMatrix: Get Neighbors of Isolated Node" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 0), neighbors.items.len);
}

test "AdjacencyMatrix: Undirected Edge Propagation" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(0, 1, {});
    try std.testing.expect(matrix.matrix.items[1][0]); // Should also be true
}

test "AdjacencyMatrix: Handle Large Graphs" {
    var matrix = try AdjacencyMatrix(false, true).init(std.testing.allocator, 10_000);
    defer matrix.deinit();

    for (0..9_999) |i| {
        try matrix.addEdge(i, i + 1, @floatFromInt(i % 100));
    }

    try std.testing.expectEqual(@as(usize, 10_000), matrix.node_count);
}

test "AdjacencyMatrix: Fully Connected Large Graph" {
    var matrix = try AdjacencyMatrix(false, true).init(std.testing.allocator, 100);
    defer matrix.deinit();

    for (0..100) |i| {
        for (0..100) |j| {
            if (i != j) try matrix.addEdge(i, j, @floatFromInt(i + j));
        }
    }

    var neighbors = try matrix.getNeighbors(50);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 99), neighbors.items.len);
}
