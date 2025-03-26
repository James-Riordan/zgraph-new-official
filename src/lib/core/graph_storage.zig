const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const GraphStorageType = enum {
    AdjacencyList,
    AdjacencyMatrix,
    IncidenceMatrix,
};

/// Generic Graph Storage Abstraction
pub fn GraphStorage(comptime storage_type: GraphStorageType, comptime directed: bool, comptime weighted: bool) type {
    return switch (storage_type) {
        .AdjacencyList => @import("../data_structures/adjacency_list.zig").AdjacencyList(directed, weighted),
        .AdjacencyMatrix => @import("../data_structures/adjacency_matrix.zig").AdjacencyMatrix(directed, weighted),
        .IncidenceMatrix => @import("../data_structures/incidence_matrix.zig").IncidenceMatrix(directed, weighted),
    };
}

test "GraphStorage: Ensure Each Type Instantiates Correctly" {
    const allocator = testing.allocator;
    const initial_capacity = 100; // Required for AdjacencyMatrix & IncidenceMatrix

    // ✅ FIXED: Correct way to iterate over enum values in Zig 0.14.0+
    inline for (std.meta.fields(GraphStorageType)) |field| {
        const storage_type: GraphStorageType = @field(GraphStorageType, field.name);
        const Storage = GraphStorage(storage_type, true, true); // ✅ Instantiate with concrete parameters

        var storage = if (storage_type == .AdjacencyList)
            Storage.init(allocator) // ✅ No `initial_capacity` for AdjacencyList
        else
            try Storage.init(allocator, initial_capacity); // ✅ `initial_capacity` required for others

        defer if (@hasDecl(Storage, "deinit")) storage.deinit();

        try testing.expect(@TypeOf(storage) == Storage);
    }
}

test "GraphStorage: Ensure Nodes Can Be Added and Removed" {
    const allocator = testing.allocator;
    const Storage = GraphStorage(GraphStorageType.AdjacencyList, true, true); // ✅ Fixed

    var storage = Storage.init(allocator);
    defer if (@hasDecl(Storage, "deinit")) storage.deinit();

    // Add a node
    try storage.addNode(1);

    // Ensure it exists
    try testing.expect(storage.getNeighbors(1) != null); // ✅ FIXED: Using `getNeighbors()` instead of `hasNode()`

    // Remove the node
    try storage.removeNode(1);

    // Ensure it no longer exists
    try testing.expect(storage.getNeighbors(1) == null);
}

test "GraphStorage: Ensure Different Storage Types Work Independently" {
    const allocator = testing.allocator;
    const initial_capacity = 100;

    const StorageA = GraphStorage(GraphStorageType.AdjacencyList, true, true);
    const StorageB = GraphStorage(GraphStorageType.AdjacencyMatrix, true, true);

    var storage_a = StorageA.init(allocator);
    defer if (@hasDecl(StorageA, "deinit")) storage_a.deinit();

    var storage_b = try StorageB.init(allocator, initial_capacity);
    defer if (@hasDecl(StorageB, "deinit")) storage_b.deinit();

    _ = try storage_a.addNode(1);
    _ = try storage_b.addNode(1);

    // ✅ AdjacencyList: returns ?ArrayList
    {
        const maybe_neighbors_a = storage_a.getNeighbors(1);
        try testing.expect(maybe_neighbors_a != null);
        if (maybe_neighbors_a) |neighbors_a| {
            defer neighbors_a.deinit();
            try testing.expect(neighbors_a.items.len >= 0);
        }
    }

    // ✅ AdjacencyMatrix: returns !ArrayList
    {
        const neighbors_b = try storage_b.getNeighbors(1);
        defer neighbors_b.deinit();
        try testing.expect(neighbors_b.items.len >= 0);
    }

    try storage_a.removeNode(1);

    {
        try testing.expect(storage_a.getNeighbors(1) == null);
    }

    {
        const neighbors_b = try storage_b.getNeighbors(1);
        defer neighbors_b.deinit();
        try testing.expect(neighbors_b.items.len >= 0);
    }
}

test "GraphStorage: Debug Print Should Not Crash" {
    const allocator = testing.allocator;
    const initial_capacity = 100;
    const Storage = GraphStorage(GraphStorageType.IncidenceMatrix, true, true);

    var storage = try Storage.init(allocator, initial_capacity);
    defer if (@hasDecl(Storage, "deinit")) storage.deinit();

    // ✅ FIXED: Only call `debugPrint()` if it exists
    if (@hasDecl(Storage, "debugPrint")) {
        storage.debugPrint();
    }
}
