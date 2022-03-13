import Foundation
//import XCTest


/*:
 ### Understanding the statement
 
 Objective: Implement a 'state-based' 'LWW-Element-Graph' with test cases.
 
 Requirement:
 
 State based, LWW element graph with operations:
 
* add a vertex/edge,
* remove a vertex/edge,
* check if a vertex is in the graph,
* query for all vertices connected to a vertex,
* find any path between two vertices, and
* merge with concurrent changes from other graph/replica. (commutative, associative and idempotent)

 The LWW part dictates that there be a timestamp attached with add and remove operations and that must be used when determining state of a node and while merging. Use latest timestamp in case of conflict.
 
 If timestamps are equal, a bias needs to be introduced. In this case, I have biased with source and add operation.
*/


/// Indicates entities which can be synced and conflict-resolved
protocol ConflictResolvable: AnyObject {
    func merge(against element: Self)
}


/*:
    Node is meant as a general data container with ability to be represented uniquely by being `Identifiable` and usable in sets due to `Hashable` property.
 
The `Identifiable` property is introduced to simulate conflict across syncing nodes. Without this, the nodes will differ in their identity when data changes, leading to duplication of nodes which are meant to represent same data and no-conflicts ever, which hinders our sync ability.
 */
struct Node: Hashable, Identifiable {
    
    var id = UUID()
    var data: Int
    
    init(_ value: Int) {
        data = value
    }
    
    internal init(id: UUID, value: Int) {
        self.id = id
        self.data = value
    }
    
    /// This is a special function added in Swift 5.2 which allow object instance to be called as a function with our custom implementation
    /// The current implement saves the trouble of calling `.data` property every time and makes code simple.
    /// - Returns: returns data
    func callAsFunction() -> Int {
        return data
    }
}


/*:
   > Link is the general bi-directional link representation supported further by `Hashable`.
 Bi-directional links are taken as they are more permissive and they have trivial work required to convert to uni-directional links.
 
A custom implementation of `Equatable` and `Hashable` is provided to maintain the bi-directional transparency when used in Dictionary, Sets and Array for comparison (more specifically equality).
 */
struct Link: Hashable {
    
    let origin: Node.ID
    let destination: Node.ID
    
    
    init(_ source: Node.ID, _ sink: Node.ID) {
        origin = source
        destination = sink
    }
    
    
/*:
 By arranging the hashing order in ascending order, the hashing algorithm produces same hash value
 even in case of swap of origin and destination, maintaining the bi-directionality property of links.
 */
    
    func hash(into hasher: inout Hasher) {
        if origin.hashValue < destination.hashValue {
            hasher.combine(origin.hashValue)
            hasher.combine(destination.hashValue)
        } else {
            hasher.combine(destination.hashValue)
            hasher.combine(origin.hashValue)
        }
    }
    
    
    static func == (lhs: Link, rhs: Link) -> Bool {
        return (lhs.origin == rhs.origin && lhs.destination == rhs.destination)
        || (lhs.origin == rhs.destination && lhs.destination == rhs.origin)
    }
    
    
}


/*:
 SyncGraph is conflict resolvable bi-directional graph, containing add and remove records with timestamps along with slough of features.
 This is made using reference semantics (class) with the assumption the graph is a more persistent entity across devices which updates it components.
 The graph merge uses state based LWW CRDT configuration in combination with private functions to  the implementation and provide the simplest interface possible.
 */
class SyncGraph: ConflictResolvable {
    
    // Add Set
    var nodes: [Node: Date] = [:]
    var links: [Link: Date] = [:]
    
    // Remove Set
    var deletedNodes: [Node: Date] = [:]
    var deletedLinks: [Link: Date] = [:]
    
    
    /// Finds all the Edges which has vertex has one of its endpoint.
    /// The `from` parameter is given to make it more versatile, removing dependency on current object
    /// - Parameters:
    ///   - vertex: node to find attached edges to
    ///   - edges: set of edges to search from
    /// - Returns: Edges which have vertex has their either endpoint
    private func edges(for vertex: Node, from edges: [Link]) -> [Link] {
        edges.filter { link in
            return link.origin == vertex.id || link.destination == vertex.id
        }
    }
    
    
    /// Adds node if not present and updates the timestamp.
    /// - Parameter node: node to be included in graph
    func add(vertex node: Node) {
        nodes[node] = Date()
    }
    
    
    ///  Adds node to remove set, after checking if node exist in add set, along with current timestamp
    /// - Parameter node: pre-existing node to be removed
    func remove(vertex node: Node) {
        guard nodes[node] != nil else { return }
        deletedNodes[node] = Date()
    }
    
    
    /// Adds a link between first 2 nodes, after confirming that nodes are part of the graph.
    /// If there are less than 2 nodes, the function simply returns.
    ///
    /// Use variadic parameters to reduce complexity exposed.
    ///
    /// - Parameter vertices: initial 2 nodes to be linked
    func add(edge vertices: Node...) {
        guard vertices.count > 1 else { return }
        
        guard nodes[vertices[0]] != nil && nodes[vertices[1]] != nil else { return }
        
        let link = Link(vertices[0].id, vertices[1].id)
        links[link] = Date()
    }
    
    
    /// Add a link between 2 nodes to remove set, after checking:
    ///     - node count is 2 or greater
    ///     - pre-existing link exist
    ///
    /// - Parameter nodes: initial 2 nodes to be de-linked
    func remove(edge nodes: Node...) {
        guard nodes.count > 1 else { return }
        let link = Link(nodes[0].id, nodes[1].id)
        guard links[link] != nil else { return }
        deletedLinks[link] = Date()
    }
    
    
    /// Checks if the vertex is part of  the graph based on criteria:
    ///     - node exists in set of nodes
    ///     - node does not exist in the remove set with later timestamp than the add timestamp
    ///
    /// - Parameter node: node to be checked in graph
    /// - Returns: true if node is part of the graph
    func contains(vertex node: Node) -> Bool {
        /// The reason `.distantPast` is used for nodes check, is because the first part of the statement confirms existing time for node.
        nodes[node] != nil && (deletedNodes[node] == nil ||  (nodes[node] ?? Date.distantFuture > deletedNodes[node] ?? Date.distantPast )  )
    }
    
    
    /// Checks if a link exist between nodes for criteria:
    ///         - node count is greater than 2
    ///         - link exist in add set
    ///         - link does not exist in remove set with later timestamp than the add timestamp
    ///
    /// - Parameter nodes: nodes representing the link
    /// - Returns: true if edge is part of the graph
    func contains(edge nodes: Node...) -> Bool {
        guard nodes.count > 1 else { return false }
        
        let link = Link(nodes[0].id, nodes[1].id)
        
        return (links[link] != nil && (deletedLinks[link] == nil ||  (links[link] ?? Date.distantFuture > deletedLinks[link] ?? Date.distantPast) ))
    }
    
    
    /// Finds all vertices connected to the node. Finds all links to or from the node and translates the node id to Node.
    /// - Parameter node: target node to find connected nodes to
    /// - Returns: Set of nodes connected to the node
    func verticesConnected(with node: Node) -> Set<Node> {
        let connectedNodes = edges(for: node, from: Array(links.keys)) // filter edges which contain node
            .compactMap { link in
                let nodeID = link.origin == node.id ? link.destination : link.origin // Select the other end of edge
                
                // TODO: can this call be improved?
                return nodes.first(where: { $0.key.id == nodeID })?.key // Convert node id to node
            }
            .filter { contains(vertex: $0) } // filter out removed node
        
        return Set(connectedNodes) // remove duplicated nodes
    }
    
    
    /// Finds all the paths from between origin and destination node using Bread First Search.
    /// - Parameters:
    ///   - origin: origin node
    ///   - destination: destination node
    func paths(from origin: Node, to destination: Node) {
        
        guard contains(vertex: origin) && contains(vertex: destination) else {
            print("Nodes not part of the graph")
            return
        }
        
        var travelNodes: [[Node]] = [[origin]]
        
        var paths: [[Node]] = []
        
        while !travelNodes.isEmpty {
            let previousPath = travelNodes.removeFirst()
            let lastNode = previousPath.last!
            
            if lastNode == destination {
                paths.append(previousPath)
            }
            
            let vertices = verticesConnected(with: lastNode)
            
            for node in vertices where !previousPath.contains(node) {
                let newPath = previousPath + [node]
                travelNodes.append(newPath)
            }
        }
        
        paths.forEach { path in
            path.forEach { node in
                print(node(), terminator: ", ")
            }
            print()
        }
        
    }
    
/*:
 `converge<T>(from:against:)` performs the state based CRDT by merging 2 different records using LWW criteria.
 
    Mutually exclusive records are added with their corresponding timestamps.
    Conflicting records are compared against time stamp with source and add operation bias. The record satisfying this criteria are kept in the result set.
 
 Note that the latest timestamp from the new record is used instead of assigning current one. This ensures that even if other instances are waiting to be converged, they won't be impacted by these operation. Assigning the current timestamp will override the changes other records in the pipeline may hold which may be more recent.
 
 `segregate<T>(_:_:)` makes sure the record either exist in remove set or add set.
 
 This is supposed to be performed after converging the add and remove set as a record can be either in add set or remove set after merging. This also removes duplicate records across the sets.
 
 It simplifies the complexity, follows add set bias.
 
 
 `merge(against:)` is the overall wrapper (in this case) which takes care of the order in which merge is done and finally assigning value to concerned entities.
 */
    
    /// Converges 2 records (add or remove) using LWW criteria with add and source set bias.
    /// - Returns: merged record
    private func converge<T>(from source: [T: Date], against target: [T: Date]) -> [T: Date] {
        
        var result: [T: Date] = [:]
        
        let sourceSet = Set(source.keys)
        var targetSet = Set(target.keys)
        
        sourceSet.forEach { node in
            
            var targetNode: T? = nil
            
            /// This step makes the whole function agnostic to data type being merged. Due to different in data semantics, selection step needs to be custom for each T.
            if node is Node {
                targetNode = targetSet.first(where: { ($0 as! Node).id == (node as! Node).id }) // Node uses value for hashing as well, so its value will be different hence custom call
            } else if node is Link {
                if targetSet.contains(node) {
                    targetNode = node
                }
            }
            
            if let targetNode = targetNode {
                
                let isConflictLatest = target[targetNode] ?? .distantPast > source[node] ?? .distantPast // Source Bias
                
                _ = targetSet.remove(node)
                
                if isConflictLatest {
                    result[targetNode] = target[targetNode]
                    return
                }
                
            }
            
            result[node] = source[node]
            
        }
        
        // Add remaining elements as they are unique
        targetSet.forEach { node in
            result[node] = target[node]
        }
        
        return result
    }
    
    
    /// Performs mutual exclusion for similar records to decide final state
    /// - Returns: mutually exclusive (addSet, removeSet) tuple
    private func segregate<T>(_ addRecord: [T: Date], _ removeRecord: [T: Date]) -> ([T: Date], [T: Date]) {
        var addRecord = addRecord
        var removeRecord = removeRecord
        
        addRecord
            .filter({ removeRecord[$0.key] != nil  }) // select only common elements
            .forEach { node in
                let latestAdd = node.value >= removeRecord[node.key]! //  Adding bias
                
                _ = latestAdd ? removeRecord.removeValue(forKey: node.key) : addRecord.removeValue(forKey: node.key) // remove from either set
            }
        
        return (addRecord, removeRecord)
    }
    
    
    /// Merge current graph against other graph
    /// - Parameter element: graph to be merged against
    func merge(against element: SyncGraph) {
        
        var activeNodes: [Node: Date] = converge(from: nodes, against: element.nodes) // Add node record
        var inactiveNodes: [Node: Date] = converge(from: deletedNodes, against: element.deletedNodes) // remove node record
        
        var activeLinks: [Link: Date] = converge(from: links, against: element.links) // add link record
        var inactiveLinks: [Link: Date] = converge(from: deletedLinks, against: element.deletedLinks) // remove link record
        
        
        (activeNodes, inactiveNodes) = segregate(activeNodes, inactiveNodes) // mutual exclusion in nodes
        (activeLinks, inactiveLinks) = segregate(activeLinks, inactiveLinks) // mutual exclusion in links
        
        
        nodes = activeNodes
        element.nodes = activeNodes
        
        deletedNodes = inactiveNodes
        element.deletedNodes = inactiveNodes
        
        links = activeLinks
        element.links = activeLinks
        
        deletedLinks = inactiveLinks
        element.deletedLinks = inactiveLinks
    }
    
}
//
//
func main() {
    // A small example
    let graph = SyncGraph()
    
    let n1 = Node(1)
    let n2 = Node(2)
    let n3 = Node(3)
    let n4 = Node(4)
    let n5 = Node(5)
    let n6 = Node(6)
    
    graph.add(vertex: n1)
    graph.add(vertex: n2)
    graph.add(vertex: n3)
    graph.add(vertex: n4)
    graph.add(vertex: n5)
    graph.add(vertex: n6)
    
    graph.add(edge: n1, n2)
    graph.add(edge: n1, n3)
    graph.add(edge: n2, n3)
    graph.add(edge: n2, n4)
    graph.add(edge: n3, n4)
    graph.add(edge: n5, n6)
    graph.add(edge: n6, n3)
    
    graph.paths(from: n1, to: n4)
}

///// Test Node - hash, equality, set, dictionary
//class NodeTest: XCTestCase {
//
//    var nodes: [Node] = []
//    var nodeSet: Set<Node> = []
//    var nodeRef: [Node: Int] = [:]
//
//    override func setUpWithError() throws {
//        let node1 = Node(1)
//        let node2 = Node(2)
//        let node3 = Node(id: node1.id, value: 3)
//        let node4 = Node(id: node1.id, value: 1)
//
//        nodes = [node1, node2, node3, node4]
//
//        nodeRef[node1] = 1
//
//        nodeSet.insert(node1)
//        nodeSet.insert(node2)
//        nodeSet.insert(node3)
//        nodeSet.insert(node4)
//
//        try testSetCount()
//        try testDictionaryReference()
//    }
//
//
//    override func tearDownWithError() throws {
//
//    }
//
//    func testSetCount() throws {
//        XCTAssert(nodeSet.count == 3)
////            fatalError()
//    }
//
//    func testDictionaryReference() throws {
//        XCTAssert(nodeRef[nodes.last!] == 1 && nodeRef[nodes[2]] == nil)
//    }
//
//}
//
//let nodeTestCase = NodeTest()
////nodeTestCase.run()
//
///// Test Link - equality, hash, set, dictionary
//class LinkTest: XCTestCase {
//
//    let node1 = Node(1)
//    let node2 = Node(2)
//    let node3 = Node(3)
//    var link1: Link!
//    var link2: Link!
//    var link3: Link!
//
//    override func setUpWithError() throws {
//        link1 = Link(node1.id, node2.id)
//        link2 = Link(node2.id, node1.id)
//        link3 = Link(node3.id, node1.id)
//
//        try testEquality()
//        try testSet()
//        try testDictionary()
//    }
//
//    override func tearDownWithError() throws {
//
//    }
//
//    func testEquality() throws {
//        XCTAssertEqual(link1, link2)
//        XCTAssertNotEqual(link2, link3)
//    }
//
//    func testSet() throws {
//        var set = Set<Link>()
//
//        set.insert(link1)
//
//        let result = set.insert(link2).inserted
//
//        XCTAssertFalse(result)
//
//    }
//
//    func testDictionary() throws {
//        let dictTest = [link1: 2]
//
//        XCTAssertEqual(dictTest[link2], 2)
//    }
//}
//
//
//let linkTestCase = LinkTest()
////linkTestCase.run()
//
///*:
//
// The test for Graph Sync should look different than other tests. This should have more of integration level semantics.
//
// The changes will be made at higher level and cross verified using lower-level functions and direct access. This will ensure the impact expected from high-level functions is reflected when manipulated with different channels
//
// */
//// Graph - add, remove, contain, vertices connected, paths, merge
//class GraphSyncTest: XCTestCase {
//
//    var graph1: SyncGraph!
//    var graph2: SyncGraph!
//
//    let n1 = Node(1)
//    let n2 = Node(2)
//    let n3 = Node(3)
//    let n4 = Node(4)
//    let n5 = Node(5)
//    let n6 = Node(6)
//
//    override func setUpWithError() throws {
//        graph1 = SyncGraph()
//        graph2 = SyncGraph()
//
//        graph1.add(vertex: n1)
//        graph1.add(vertex: n2)
//        graph1.add(vertex: n3)
//
//        graph2.add(vertex: n1)
//        graph2.add(vertex: n4)
//        graph2.add(vertex: n5)
//        graph2.add(vertex: n6)
//
//        try testAddVertex()
//
//        graph1.add(edge: n1, n2)
//        graph1.add(edge: n1, n3)
//        graph1.add(edge: n2, n3)
//
//        graph2.add(edge: n1, n6)
//        graph2.add(edge: n5, n6)
//
//        try testAddEdge()
//
//        graph2.remove(vertex: n6)
//        try testRemoveVertex(vertex: n6)
//
//        graph2.remove(edge: n6, n1)
//        try testRemoveEdge(node1: n1, node2: n6)
//
//
//        try testConnectedVertices()
//
//
//        graph1.merge(against: graph2)
//
//        graph1.add(edge: n6, n3) // This won't be added as n6 is in remove set
//
//        graph1.add(edge: n2, n4)
//        graph1.add(edge: n3, n4)
//
//        try testMerge()
//
//        graph1.paths(from: n1, to: n4)
///*:
//Should print:
//
// 1, 2, 4,
//
// 1, 3, 4,
//
// 1, 2, 3, 4,
//
// 1, 3, 2, 4,
//*/
//    }
//
//
//    func testAddVertex() throws {
//        XCTAssertTrue(graph1.nodes.count == 3)
//        XCTAssertTrue(graph2.nodes.count == 4)
//    }
//
//    func testAddEdge() throws {
//        XCTAssertTrue(graph1.links.count == 3)
//        XCTAssertTrue(graph2.links.count == 2)
//    }
//
//    func testRemoveVertex(vertex: Node) throws {
//        XCTAssertFalse(graph2.contains(vertex: vertex))
//    }
//
//    func testRemoveEdge(node1: Node, node2: Node) throws {
//        XCTAssertFalse(graph2.contains(edge: node1, node2))
//    }
//
//    func testConnectedVertices() throws {
//        XCTAssertEqual(graph1.verticesConnected(with: n2), Set([n1, n3]))
//        XCTAssertEqual(graph1.verticesConnected(with: n1), Set([n2, n3]))
//    }
//
//    func testMerge() throws {
//        XCTAssertEqual(graph1.nodes.count, 5)
//        XCTAssertEqual(graph1.deletedNodes.count, 1)
//
//        XCTAssertEqual(graph1.links.count, 6)
//        XCTAssertEqual(graph2.links.count, 4)
//        XCTAssertEqual(graph1.deletedLinks.count, 1)
//
//        XCTAssertFalse(graph1.contains(vertex: n6))
//        XCTAssertFalse(graph1.contains(edge: n1, n6))
//
//        XCTAssertTrue(graph1.contains(edge: n4, n2))
//        XCTAssertFalse(graph1.contains(edge: n3, n6))
//
//    }
//
//    override func tearDownWithError() throws {
//
//    }
//}
//
//let graphTestCase = GraphSyncTest()
////graphTestCase.run()
//
///*:
// # Further Steps
//
// 1. Simplify Add and Remove implementation. Return status flag for operation.
// 2. Explore other format to organize records apart from dictionary
// 3. Add Logging
// 4. "Performance" improvements - BE VERY CAREFUL.
// */
