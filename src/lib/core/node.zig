const std = @import("std");

/// 🚀 Generic Node Definition with Arbitrary Data Support
pub const Node = struct {
    id: u64,
    label: []const u8,
    data: std.StringHashMap([]const u8), // ✅ Stores arbitrary key-value pairs

    pub fn init(allocator: std.mem.Allocator, id: u64, label: []const u8) !Node {
        const map = std.StringHashMap([]const u8).init(allocator);
        return Node{ .id = id, .label = label, .data = map };
    }

    pub fn deinit(self: *Node) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn setData(self: *Node, key: []const u8, value: []const u8) !void {
        try self.data.put(key, value); // ✅ Store data dynamically
    }

    pub fn getData(self: *Node, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn debugPrint(self: *const @This()) void {
        std.debug.print("Node {}: \"{s}\"\n", .{ self.id, self.label });
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            std.debug.print("  {s}: \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
};

// ✅ Unit Tests for Node
test "Node: Debug Print" {
    var n = try Node.init(std.testing.allocator, 1, "Test Node"); // ✅ Fix: Use init function
    defer n.data.deinit();
    n.debugPrint();
}
