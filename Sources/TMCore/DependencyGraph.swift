import Foundation

// MARK: - Dependency Graph

/// A directed acyclic graph for tracking dependencies between integer-keyed
/// nodes, used by the snippet engine to order mirror updates.
///
/// Ports the C++ `oak::dependency_graph` from `dependency_graph.h`.
///
/// Example: if tab stop 2 contains a mirror of tab stop 1, then node 2 depends
/// on node 1. When tab stop 1 is edited, `touch(1)` returns `{1, 2}` and
/// `topologicalOrder()` yields `[1, 2]` so mirrors are updated in order.
public struct DependencyGraph: Sendable {
	/// Adjacency: node → set of nodes it depends on.
	private var dependencies: [Int: Set<Int>] = [:]

	public init() {}

	/// Registers a node in the graph.
	public mutating func addNode(_ node: Int) {
		if dependencies[node] == nil {
			dependencies[node] = []
		}
	}

	/// Adds a dependency edge: `node` depends on `dependsOn`.
	public mutating func addEdge(from node: Int, dependsOn: Int) {
		dependencies[node, default: []].insert(dependsOn)
	}

	/// Marks `node` as modified and returns all transitively affected nodes.
	///
	/// Walks reverse edges to find every node that directly or indirectly
	/// depends on `node`.
	public func touch(_ node: Int) -> Set<Int> {
		guard dependencies[node] != nil else { return [] }
		var result = Set<Int>()
		var active = [node]

		while let n = active.popLast() {
			result.insert(n)
			for (dependent, deps) in dependencies {
				if deps.contains(n), !result.contains(dependent) {
					active.append(dependent)
				}
			}
		}

		return result
	}

	/// Returns nodes in topological order: for each node, all nodes it depends
	/// on appear earlier in the result.
	///
	/// Uses Kahn's algorithm.
	public func topologicalOrder() -> [Int] {
		var remaining = dependencies
		var result: [Int] = []

		// Start with nodes that have no dependencies
		var active = remaining.filter(\.value.isEmpty).map(\.key)

		while let n = active.popLast() {
			result.append(n)

			// Remove n from all dependency sets
			for key in remaining.keys {
				if remaining[key]?.remove(n) != nil, remaining[key]?.isEmpty == true {
					active.append(key)
				}
			}
		}

		return result
	}
}
