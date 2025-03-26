const std = @import("std");

pub fn Graph(comptime weighted: bool, comptime Storage: type) type {
    return struct {
        allocator: std.mem.Allocator,
        storage: Storage,
        heterogeneous: bool, // ✅ Restore heterogeneous support
        node_types: ?std.AutoHashMap(u64, []const u8), // ✅ Only allocated if converted to heterogeneous
        edge_types: ?std.AutoHashMap(u64, []const u8), // ✅ Only allocated if converted to heterogeneous

        /// 🚀 Initialize Graph with Chosen Storage
        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .allocator = allocator,
                .storage = Storage.init(allocator),
                .heterogeneous = false, // ✅ Default to homogeneous
                .node_types = null,
                .edge_types = null,
            };
        }

        /// 🚀 Deinitialize Graph
        pub fn deinit(self: *@This()) void {
            if (self.heterogeneous) {
                if (self.node_types) |*nt| {
                    var it = nt.iterator();
                    while (it.next()) |entry| {
                        self.allocator.free(entry.value_ptr.*);
                    }
                    nt.deinit();
                }

                if (self.edge_types) |*et| {
                    var it = et.iterator();
                    while (it.next()) |entry| {
                        self.allocator.free(entry.value_ptr.*);
                    }
                    et.deinit();
                }
            }

            self.storage.deinit();
        }

        /// 🚀 Convert Graph to Heterogeneous (Explicit User Action)
        pub fn convertToHeterogeneous(self: *@This()) !void {
            if (self.heterogeneous) return error.AlreadyHeterogeneous;
            self.node_types = std.AutoHashMap(u64, []const u8).init(self.allocator);
            self.edge_types = std.AutoHashMap(u64, []const u8).init(self.allocator);
            self.heterogeneous = true;
        }

        /// 🚀 Add Node (Supports Heterogeneous Graphs)
        pub fn addNode(self: *@This(), id: u64, label: []const u8, node_type: ?[]const u8) !void {
            try self.storage.addNode(id, label); // Ensure label is used!

            if (self.heterogeneous) {
                if (node_type == null) return error.MissingNodeType;
                const allocated_type = try self.allocator.dupe(u8, node_type.?);
                try self.node_types.?.put(id, allocated_type);
            } else if (node_type != null) {
                return error.GraphIsHomogeneous;
            }
        }

        pub fn removeNode(self: *@This(), node_id: u64) !void {
            try self.storage.removeNode(node_id);
            if (self.heterogeneous) {
                _ = self.node_types.?.remove(node_id);
            }
        }

        /// 🚀 Add Edge (Supports Heterogeneous Graphs)
        pub fn addEdge(self: *@This(), src: u64, dst: u64, weight: if (weighted) ?f64 else void, edge_type: ?[]const u8) !void {
            try self.storage.addEdge(src, dst, weight);

            if (self.heterogeneous) {
                if (edge_type == null) return error.MissingEdgeType;
                const edge_key = generateEdgeKey(src, dst);
                const hashed_key = hashEdgeKey(edge_key);
                const allocated_edge_type = try self.allocator.dupe(u8, edge_type.?);
                try self.edge_types.?.put(hashed_key, allocated_edge_type);
            } else if (edge_type != null) {
                return error.GraphIsHomogeneous;
            }
        }

        pub fn removeEdge(self: *@This(), src: u64, dst: u64) !void {
            try self.storage.removeEdge(src, dst);
            if (self.heterogeneous) {
                const edge_key = generateEdgeKey(src, dst);
                const hashed_key = hashEdgeKey(edge_key);
                _ = self.edge_types.?.remove(hashed_key);
            }
        }

        /// 🚀 Get Node Type (for Heterogeneous Graphs)
        pub fn getNodeType(self: *const @This(), id: u64) ?[]const u8 {
            if (!self.heterogeneous) return null;
            return self.node_types.?.get(id);
        }

        /// 🚀 Get Edge Type (for Heterogeneous Graphs)
        pub fn getEdgeType(self: *@This(), src: u64, dst: u64) ?[]const u8 {
            if (!self.heterogeneous) return null;
            const edge_key = generateEdgeKey(src, dst);
            const hashed_key = hashEdgeKey(edge_key);
            return self.edge_types.?.get(hashed_key);
        }

        /// 🚀 Debug Print (for Visualization)
        pub fn debugPrint(self: *@This()) void {
            std.debug.print("Graph:\n", .{});
            self.storage.debugPrint();

            if (self.heterogeneous) {
                std.debug.print("  Heterogeneous Node Types:\n", .{});
                var node_it = self.node_types.?.iterator();
                while (node_it.next()) |entry| {
                    std.debug.print("    Node {}: Type \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
                }

                std.debug.print("  Heterogeneous Edge Types:\n", .{});
                var edge_it = self.edge_types.?.iterator();
                while (edge_it.next()) |entry| {
                    std.debug.print("    Edge Hash {}: Type \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
                }
            }
        }

        /// 🚀 Helper Functions
        fn generateEdgeKey(src: u64, dst: u64) u128 {
            return (@as(u128, src) << 64) | dst;
        }

        fn hashEdgeKey(edge_key: u128) u64 {
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&edge_key));
        }
    };
}

// test "Graph: Initialize and Deinitialize" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     if (g.nodes.count() != 0 or g.edges.count() != 0) {
//         std.debug.print("\n[ERROR] Graph should be empty on initialization! Nodes: {d}, Edges: {d}\n", .{ g.nodes.count(), g.edges.count() });
//     }

//     try std.testing.expectEqual(@as(usize, 0), g.nodes.count());
//     try std.testing.expectEqual(@as(usize, 0), g.edges.count());
// }

// test "Graph: Add Nodes (Homogeneous)" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "NodeA", null);
//     try g.addNode(2, "NodeB", null);

//     if (!g.nodes.contains(1) or !g.nodes.contains(2)) {
//         std.debug.print("\n[ERROR] Nodes not added correctly! Node 1 exists: {any}, Node 2 exists: {any}\n", .{ g.nodes.contains(1), g.nodes.contains(2) });
//     }

//     try std.testing.expect(g.nodes.contains(1));
//     try std.testing.expect(g.nodes.contains(2));
// }

// test "Graph: Add Nodes (Heterogeneous)" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.convertToHeterogeneous();
//     try g.addNode(1, "NodeA", "TypeA");
//     try g.addNode(2, "NodeB", "TypeB");

//     if (g.getNodeType(1) == null or g.getNodeType(2) == null) {
//         std.debug.print("\n[ERROR] Node types missing! Node 1 Type: {?s}, Node 2 Type: {?s}\n", .{ g.getNodeType(1), g.getNodeType(2) });
//     }

//     try std.testing.expectEqualStrings("TypeA", g.getNodeType(1).?);
//     try std.testing.expectEqualStrings("TypeB", g.getNodeType(2).?);
// }

// test "Graph: Remove Node" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "NodeA", null);
//     try g.addNode(2, "NodeB", null);
//     try g.addEdge(1, 2, 3.5, null);

//     g.removeNode(1);

//     if (g.nodes.contains(1)) {
//         std.debug.print("\n[ERROR] Node 1 was not removed!\n", .{});
//     }

//     if (g.edges.get(1) != null) {
//         std.debug.print("\n[ERROR] Edges from Node 1 were not removed!\n", .{});
//     }

//     try std.testing.expect(!g.nodes.contains(1));
//     try std.testing.expect(g.edges.get(1) == null);
// }

// test "Graph: Add and Remove Edges (Homogeneous Directed)" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "NodeA", null);
//     try g.addNode(2, "NodeB", null);
//     try g.addEdge(1, 2, 3.5, null);

//     if (!g.edges.contains(1)) {
//         std.debug.print("\n[ERROR] Edge 1 -> 2 was not added!\n", .{});
//     }

//     try std.testing.expect(g.edges.contains(1));
//     try std.testing.expectEqual(@as(usize, 1), g.edges.get(1).?.items.len);

//     g.removeEdge(1, 2);

//     if (g.edges.contains(1)) {
//         std.debug.print("\n[ERROR] Edge 1 -> 2 was not removed!\n", .{});
//     }

//     try std.testing.expectEqual(@as(usize, 0), if (g.edges.get(1)) |e| e.items.len else 0);
// }

// test "Graph: Add and Remove Edges (Homogeneous Undirected)" {
//     var g = Graph(false, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "NodeA", null);
//     try g.addNode(2, "NodeB", null);
//     try g.addEdge(1, 2, 3.5, null);

//     if (!g.edges.contains(1) or !g.edges.contains(2)) {
//         std.debug.print("\n[ERROR] Undirected edges not added properly! Edges from 1: {any}, Edges from 2: {any}\n", .{ g.edges.get(1), g.edges.get(2) });
//     }

//     try std.testing.expectEqual(@as(usize, 1), g.edges.get(1).?.items.len);
//     try std.testing.expectEqual(@as(usize, 1), g.edges.get(2).?.items.len);

//     g.removeEdge(1, 2);

//     if (g.edges.contains(1) or g.edges.contains(2)) {
//         std.debug.print("\n[ERROR] Undirected edge 1 <-> 2 was not removed properly!\n", .{});
//     }

//     try std.testing.expectEqual(@as(usize, 0), if (g.edges.get(1)) |e| e.items.len else 0);
//     try std.testing.expectEqual(@as(usize, 0), if (g.edges.get(2)) |e| e.items.len else 0);
// }

// test "Graph: Add Edge (Heterogeneous)" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.convertToHeterogeneous();
//     try g.addNode(1, "NodeA", "TypeA");
//     try g.addNode(2, "NodeB", "TypeB");
//     try g.addEdge(1, 2, 2.5, "Strong Connection");

//     if (g.getEdgeType(1, 2) == null or !std.mem.eql(u8, g.getEdgeType(1, 2).?, "Strong Connection")) {
//         std.debug.print("\n[ERROR] Edge 1 -> 2 type mismatch! Expected: 'Strong Connection', Found: {?s}\n", .{g.getEdgeType(1, 2).?});
//     }

//     try std.testing.expectEqualStrings("Strong Connection", g.getEdgeType(1, 2).?);
// }

// test "Graph: Cycle Detection (Acyclic Graphs)" {
//     var g = Graph(true, true, false).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "A", null);
//     try g.addNode(2, "B", null);
//     try g.addEdge(1, 2, {}, null);

//     try std.testing.expectError(error.CycleDetected, g.addEdge(2, 1, {}, null));
// }

// test "Graph: Remove Edge" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "NodeA", null);
//     try g.addNode(2, "NodeB", null);
//     try g.addEdge(1, 2, 4.5, null);

//     g.removeEdge(1, 2);

//     if (g.edges.get(1) != null and g.edges.get(1).?.items.len > 0) {
//         std.debug.print("\n[ERROR] Edge 1 -> 2 was not removed correctly!\n", .{});
//     }

//     try std.testing.expectEqual(@as(usize, 0), if (g.edges.get(1)) |e| e.items.len else 0);
// }

// test "Graph: Debug Print (Only on Failure)" {
//     var g = Graph(true, false, true).init(std.testing.allocator);
//     defer g.deinit();

//     try g.addNode(1, "A", null);
//     try g.addNode(2, "B", null);
//     try g.addEdge(1, 2, 4.5, null);

//     if (!g.nodes.contains(1) or !g.nodes.contains(2) or !g.edges.contains(1)) {
//         std.debug.print("\n[ERROR] Debug Print - Graph is missing expected elements!\n", .{});
//         g.debugPrint();
//     }

//     try std.testing.expect(g.nodes.contains(1));
//     try std.testing.expect(g.nodes.contains(2));
//     try std.testing.expect(g.edges.contains(1));
// }
