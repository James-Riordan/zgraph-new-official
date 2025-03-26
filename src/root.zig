const std = @import("std");

// ✅ Core Graph Components
pub const Graph = @import("lib/core/graph.zig").Graph;
pub const Node = @import("lib/core/node.zig").Node;
pub const Edge = @import("lib/core/edge.zig").Edge;
pub const GraphStorage = @import("lib/core/graph_storage.zig").GraphStorage;

// ✅ Data Structures (Graph Representations)
pub const AdjacencyList = @import("lib/data_structures/adjacency_list.zig");
pub const AdjacencyMatrix = @import("lib/data_structures/adjacency_matrix.zig");
pub const IncidenceMatrix = @import("lib/data_structures/incidence_matrix.zig");

// pub const LaplacianMatrix = @import("lib/data_structures/laplacian_matrix.zig");

pub const data_structures = struct {
    pub const AdjacencyList = @import("lib/data_structures/adjacency_list.zig");
    pub const AdjacencyMatrix = @import("lib/data_structures/adjacency_matrix.zig");
    pub const IncidenceMatrix = @import("lib/data_structures/incidence_matrix.zig");
};
// // ✅ Graph Formats (Serialization & Parsing)
// pub const ZGraphFormat = @import("lib/formats/zgraph.zig");
// pub const JSONFormat = @import("lib/formats/json.zig");
// pub const DotFormat = @import("lib/formats/dot.zig");

// // ✅ Graph Algorithms
// pub const algorithms = struct {
//     pub const traversal = struct {
//         pub const bfs = @import("lib/algorithms/traversal/bfs.zig");
//         pub const dfs = @import("lib/algorithms/traversal/dfs.zig");
//     };

//     pub const shortest_path = struct {
//         pub const dijkstra = @import("lib/algorithms/shortest_path/dijkstra.zig");
//         pub const bellman_ford = @import("lib/algorithms/shortest_path/bellman_ford.zig");
//         pub const floyd_warshall = @import("lib/algorithms/shortest_path/floyd_warshall.zig");
//     };

//     pub const mst = struct {
//         pub const kruskal = @import("lib/algorithms/mst/kruskal.zig");
//         pub const prim = @import("lib/algorithms/mst/prim.zig");
//     };

//     pub const flow = struct {
//         pub const edmonds_karp = @import("lib/algorithms/flow/edmonds_karp.zig");
//         pub const ford_fulkerson = @import("lib/algorithms/flow/ford_fulkerson.zig");
//     };

//     pub const spectral = struct {
//         pub const laplacian_matrix = @import("lib/algorithms/spectral/laplacian_matrix.zig");
//         // pub const eigenvector_centrality = @import("lib/algorithms/spectral/eigenvector_centrality.zig");
//     };
// };

// // ✅ Utilities
// pub const utilities = struct {
//     pub const debug = @import("lib/utilities/debug.zig");
// };

// ✅ Ensure Zig detects all public functions and runs tests for this module
test {
    std.testing.refAllDecls(@This());
}
