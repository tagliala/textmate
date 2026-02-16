import Testing
@testable import TMCore

@Suite("DependencyGraph — DAG & Topological Sort")
struct DependencyGraphTests {
	@Test func emptyGraph() {
		let graph = DependencyGraph()
		#expect(graph.topologicalOrder().isEmpty)
		#expect(graph.touch(0).isEmpty)
	}

	@Test func singleNode() {
		var graph = DependencyGraph()
		graph.addNode(1)
		#expect(graph.topologicalOrder() == [1])
		#expect(graph.touch(1) == [1])
	}

	@Test func linearChain() throws {
		var graph = DependencyGraph()
		graph.addNode(1)
		graph.addNode(2)
		graph.addNode(3)
		graph.addEdge(from: 2, dependsOn: 1)
		graph.addEdge(from: 3, dependsOn: 2)

		let order = graph.topologicalOrder()
		#expect(try #require(order.firstIndex(of: 1)) < order.firstIndex(of: 2)!)
		#expect(try #require(order.firstIndex(of: 2)) < order.firstIndex(of: 3)!)
	}

	@Test func touchPropagates() {
		var graph = DependencyGraph()
		graph.addNode(1)
		graph.addNode(2)
		graph.addNode(3)
		graph.addEdge(from: 2, dependsOn: 1)
		graph.addEdge(from: 3, dependsOn: 2)

		let affected = graph.touch(1)
		#expect(affected == [1, 2, 3])
	}

	@Test func touchIsolated() {
		var graph = DependencyGraph()
		graph.addNode(1)
		graph.addNode(2)
		graph.addNode(3)
		graph.addEdge(from: 3, dependsOn: 2)

		let affected = graph.touch(1)
		#expect(affected == [1])
	}

	@Test func diamondDependency() throws {
		var graph = DependencyGraph()
		graph.addNode(1)
		graph.addNode(2)
		graph.addNode(3)
		graph.addNode(4)
		graph.addEdge(from: 2, dependsOn: 1)
		graph.addEdge(from: 3, dependsOn: 1)
		graph.addEdge(from: 4, dependsOn: 2)
		graph.addEdge(from: 4, dependsOn: 3)

		let order = graph.topologicalOrder()
		#expect(try #require(order.firstIndex(of: 1)) < order.firstIndex(of: 2)!)
		#expect(try #require(order.firstIndex(of: 1)) < order.firstIndex(of: 3)!)
		#expect(try #require(order.firstIndex(of: 2)) < order.firstIndex(of: 4)!)
		#expect(try #require(order.firstIndex(of: 3)) < order.firstIndex(of: 4)!)

		let affected = graph.touch(1)
		#expect(affected.count == 4)
		#expect(affected.contains(1))
		#expect(affected.contains(4))
	}

	@Test func multipleDependencies() throws {
		var graph = DependencyGraph()
		graph.addNode(1)
		graph.addNode(2)
		graph.addNode(3)
		graph.addEdge(from: 3, dependsOn: 1)
		graph.addEdge(from: 3, dependsOn: 2)

		let order = graph.topologicalOrder()
		#expect(try #require(order.firstIndex(of: 1)) < order.firstIndex(of: 3)!)
		#expect(try #require(order.firstIndex(of: 2)) < order.firstIndex(of: 3)!)
	}

	@Test func touchLeafNode() {
		var graph = DependencyGraph()
		graph.addNode(1)
		graph.addNode(2)
		graph.addEdge(from: 2, dependsOn: 1)

		let affected = graph.touch(2)
		#expect(affected == [2])
	}
}
