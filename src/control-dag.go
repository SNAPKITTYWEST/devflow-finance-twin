package control

import (
	"fmt"
	"sync"
	"time"
)

// NodeStatus represents the lifecycle state of a DAG node
type NodeStatus int

const (
	PENDING NodeStatus = iota
	AUTHORIZED
	RUNNING
	COMPLETED
	FAILED
	VERIFIED
	COMMITTED
)

// String representation of NodeStatus
func (ns NodeStatus) String() string {
	switch ns {
	case PENDING:
		return "PENDING"
	case AUTHORIZED:
		return "AUTHORIZED"
	case RUNNING:
		return "RUNNING"
	case COMPLETED:
		return "COMPLETED"
	case FAILED:
		return "FAILED"
	case VERIFIED:
		return "VERIFIED"
	case COMMITTED:
		return "COMMITTED"
	default:
		return "UNKNOWN"
	}
}

// DAGNode represents an operation in the dependency graph
type DAGNode struct {
	ID              string
	Operation       OperationType
	Inputs          []string // input file paths
	Outputs         []string // output file paths
	Dependencies    []string // node IDs this depends on
	Status          NodeStatus
	StartTime       time.Time
	EndTime         time.Time
	ErrorMessage    string
	ExecutionResult interface{} // arbitrary result from execution
	Retries         int
	MaxRetries      int
	Priority        int // higher = more priority
	mu              sync.RWMutex
}

// NewDAGNode creates a new node with defaults
func NewDAGNode(id string, op OperationType) *DAGNode {
	return &DAGNode{
		ID:         id,
		Operation:  op,
		Inputs:     []string{},
		Outputs:    []string{},
		Dependencies: []string{},
		Status:     PENDING,
		MaxRetries: 0,
		Priority:   0,
	}
}

// GetStatus returns the current status of the node (thread-safe)
func (n *DAGNode) GetStatus() NodeStatus {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.Status
}

// SetStatus updates the node status (thread-safe)
func (n *DAGNode) SetStatus(status NodeStatus) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.Status = status
}

// AddDependency adds a dependency on another node
func (n *DAGNode) AddDependency(nodeID string) {
	n.mu.Lock()
	defer n.mu.Unlock()

	// Avoid duplicates
	for _, dep := range n.Dependencies {
		if dep == nodeID {
			return
		}
	}
	n.Dependencies = append(n.Dependencies, nodeID)
}

// AddInput adds an input file
func (n *DAGNode) AddInput(path string) {
	n.mu.Lock()
	defer n.mu.Unlock()

	// Avoid duplicates
	for _, inp := range n.Inputs {
		if inp == path {
			return
		}
	}
	n.Inputs = append(n.Inputs, path)
}

// AddOutput adds an output file
func (n *DAGNode) AddOutput(path string) {
	n.mu.Lock()
	defer n.mu.Unlock()

	// Avoid duplicates
	for _, out := range n.Outputs {
		if out == path {
			return
		}
	}
	n.Outputs = append(n.Outputs, path)
}

// DAGScheduler manages the execution of a DAG of operations
type DAGScheduler struct {
	nodes        map[string]*DAGNode
	readiness    map[string]bool // tracks which nodes are ready to execute
	completed    []string
	failed       []string
	nodeOrder    []string // topological ordering
	mu           sync.RWMutex
	cycleDetector map[string]bool // for DFS cycle detection
	visitMarks    map[string]int   // 0: white, 1: gray, 2: black
}

// NewDAGScheduler creates a new scheduler
func NewDAGScheduler() *DAGScheduler {
	return &DAGScheduler{
		nodes:         make(map[string]*DAGNode),
		readiness:     make(map[string]bool),
		completed:     []string{},
		failed:        []string{},
		nodeOrder:     []string{},
		cycleDetector: make(map[string]bool),
		visitMarks:    make(map[string]int),
	}
}

// AddNode adds an operation to the DAG
// Returns error if adding the node would create a cycle
func (d *DAGScheduler) AddNode(node *DAGNode) error {
	if node == nil {
		return fmt.Errorf("cannot add nil node")
	}

	d.mu.Lock()
	defer d.mu.Unlock()

	// Check if node already exists
	if _, exists := d.nodes[node.ID]; exists {
		return fmt.Errorf("node %s already exists", node.ID)
	}

	// Check if all dependencies exist
	for _, dep := range node.Dependencies {
		if _, exists := d.nodes[dep]; !exists {
			return fmt.Errorf("dependency %s for node %s does not exist", dep, node.ID)
		}
	}

	// Add the node
	d.nodes[node.ID] = node
	d.readiness[node.ID] = len(node.Dependencies) == 0

	// Check for cycles
	if d.hasCycle() {
		delete(d.nodes, node.ID)
		delete(d.readiness, node.ID)
		return fmt.Errorf("adding node %s would create a cycle", node.ID)
	}

	return nil
}

// hasCycle checks if the graph contains a cycle using DFS
func (d *DAGScheduler) hasCycle() bool {
	// Reset visit marks
	d.visitMarks = make(map[string]int)
	for nodeID := range d.nodes {
		d.visitMarks[nodeID] = 0 // white
	}

	// DFS from all unvisited nodes
	for nodeID := range d.nodes {
		if d.visitMarks[nodeID] == 0 {
			if d.hasCycleDFS(nodeID) {
				return true
			}
		}
	}
	return false
}

// hasCycleDFS performs depth-first search for cycle detection
// Returns true if a back edge (cycle) is found
func (d *DAGScheduler) hasCycleDFS(nodeID string) bool {
	d.visitMarks[nodeID] = 1 // mark as gray (in progress)

	node, exists := d.nodes[nodeID]
	if !exists {
		return false
	}

	// Visit all dependencies
	for _, depID := range node.Dependencies {
		if d.visitMarks[depID] == 1 {
			// Back edge found (gray to gray) = cycle
			return true
		}
		if d.visitMarks[depID] == 0 {
			if d.hasCycleDFS(depID) {
				return true
			}
		}
	}

	d.visitMarks[nodeID] = 2 // mark as black (visited)
	return false
}

// ResolveReady returns all nodes ready to execute (all dependencies satisfied)
func (d *DAGScheduler) ResolveReady() []*DAGNode {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var ready []*DAGNode

	for nodeID, isReady := range d.readiness {
		if !isReady {
			continue
		}

		// Skip if already completed or failed
		if contains(d.completed, nodeID) || contains(d.failed, nodeID) {
			continue
		}

		node, exists := d.nodes[nodeID]
		if !exists {
			continue
		}

		// Check if node is in a ready state (not already running/completed)
		status := node.GetStatus()
		if status == PENDING || status == AUTHORIZED {
			ready = append(ready, node)
		}
	}

	return ready
}

// MarkComplete marks a node as complete and updates dependents' readiness
func (d *DAGScheduler) MarkComplete(nodeID string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	node, exists := d.nodes[nodeID]
	if !exists {
		return fmt.Errorf("node %s does not exist", nodeID)
	}

	// Check if already completed or failed
	if contains(d.completed, nodeID) {
		return fmt.Errorf("node %s already marked as complete", nodeID)
	}
	if contains(d.failed, nodeID) {
		return fmt.Errorf("node %s already marked as failed", nodeID)
	}

	// Mark as completed
	d.completed = append(d.completed, nodeID)
	node.SetStatus(COMPLETED)
	node.EndTime = time.Now()

	// Update readiness of dependent nodes
	for dependerID, dependerNode := range d.nodes {
		if contains(dependerNode.Dependencies, nodeID) {
			// Check if all dependencies of depender are now complete
			allDepsComplete := true
			for _, dep := range dependerNode.Dependencies {
				if !contains(d.completed, dep) {
					allDepsComplete = false
					break
				}
			}
			d.readiness[dependerID] = allDepsComplete
		}
	}

	return nil
}

// MarkFailed marks a node as failed and propagates failure to dependents
func (d *DAGScheduler) MarkFailed(nodeID, errorMsg string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	node, exists := d.nodes[nodeID]
	if !exists {
		return fmt.Errorf("node %s does not exist", nodeID)
	}

	if contains(d.completed, nodeID) || contains(d.failed, nodeID) {
		return fmt.Errorf("node %s already has a terminal status", nodeID)
	}

	// Mark as failed
	d.failed = append(d.failed, nodeID)
	node.SetStatus(FAILED)
	node.ErrorMessage = errorMsg
	node.EndTime = time.Now()

	// Mark all dependent nodes as failed (cascade)
	d.cascadeFailure(nodeID)

	return nil
}

// cascadeFailure marks all nodes that depend on a failed node as failed
func (d *DAGScheduler) cascadeFailure(failedNodeID string) {
	for dependerID, dependerNode := range d.nodes {
		if contains(dependerNode.Dependencies, failedNodeID) {
			if !contains(d.failed, dependerID) && !contains(d.completed, dependerID) {
				d.failed = append(d.failed, dependerID)
				dependerNode.SetStatus(FAILED)
				dependerNode.ErrorMessage = fmt.Sprintf("Cascaded from %s", failedNodeID)
				dependerNode.EndTime = time.Now()
				// Recursively cascade
				d.cascadeFailure(dependerID)
			}
		}
	}
}

// FailedNodes returns all nodes that failed
func (d *DAGScheduler) FailedNodes() []*DAGNode {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var failed []*DAGNode
	for _, nodeID := range d.failed {
		if node, exists := d.nodes[nodeID]; exists {
			failed = append(failed, node)
		}
	}
	return failed
}

// CompletedNodes returns all nodes that completed successfully
func (d *DAGScheduler) CompletedNodes() []*DAGNode {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var completed []*DAGNode
	for _, nodeID := range d.completed {
		if node, exists := d.nodes[nodeID]; exists {
			completed = append(completed, node)
		}
	}
	return completed
}

// GetNode retrieves a node by ID
func (d *DAGScheduler) GetNode(nodeID string) (*DAGNode, bool) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	node, exists := d.nodes[nodeID]
	return node, exists
}

// GetAllNodes returns all nodes in the DAG
func (d *DAGScheduler) GetAllNodes() []*DAGNode {
	d.mu.RLock()
	defer d.mu.RUnlock()

	nodes := make([]*DAGNode, 0, len(d.nodes))
	for _, node := range d.nodes {
		nodes = append(nodes, node)
	}
	return nodes
}

// GetStatus returns the overall execution status
func (d *DAGScheduler) GetStatus() DAGStatus {
	d.mu.RLock()
	defer d.mu.RUnlock()

	totalNodes := len(d.nodes)
	completedCount := len(d.completed)
	failedCount := len(d.failed)
	pendingCount := totalNodes - completedCount - failedCount

	return DAGStatus{
		TotalNodes:  totalNodes,
		Completed:   completedCount,
		Failed:      failedCount,
		Pending:     pendingCount,
		IsComplete:  pendingCount == 0 && failedCount == 0,
		HasFailures: failedCount > 0,
	}
}

// DAGStatus represents the current execution state
type DAGStatus struct {
	TotalNodes  int
	Completed   int
	Failed      int
	Pending     int
	IsComplete  bool
	HasFailures bool
}

// TopologicalSort returns nodes in topological order
func (d *DAGScheduler) TopologicalSort() ([]string, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	// Kahn's algorithm for topological sort
	inDegree := make(map[string]int)
	adj := make(map[string][]string)

	// Initialize
	for nodeID := range d.nodes {
		inDegree[nodeID] = 0
		adj[nodeID] = []string{}
	}

	// Build adjacency list and in-degree counts
	for nodeID, node := range d.nodes {
		for _, depID := range node.Dependencies {
			adj[depID] = append(adj[depID], nodeID)
			inDegree[nodeID]++
		}
	}

	// Find all nodes with in-degree 0
	queue := []string{}
	for nodeID, degree := range inDegree {
		if degree == 0 {
			queue = append(queue, nodeID)
		}
	}

	result := []string{}
	for len(queue) > 0 {
		// Remove from queue
		nodeID := queue[0]
		queue = queue[1:]
		result = append(result, nodeID)

		// For each adjacent node
		for _, adjacent := range adj[nodeID] {
			inDegree[adjacent]--
			if inDegree[adjacent] == 0 {
				queue = append(queue, adjacent)
			}
		}
	}

	if len(result) != len(d.nodes) {
		return nil, fmt.Errorf("cycle detected in DAG")
	}

	return result, nil
}

// ExecutionPlan represents a plan for executing the DAG
type ExecutionPlan struct {
	NodeOrder    []string
	Levels       [][]string // nodes grouped by execution level
	Dependencies map[string][]string
}

// GenerateExecutionPlan creates a plan showing execution levels
func (d *DAGScheduler) GenerateExecutionPlan() (*ExecutionPlan, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	plan := &ExecutionPlan{
		NodeOrder:    []string{},
		Levels:       [][]string{},
		Dependencies: make(map[string][]string),
	}

	// Build level-based execution plan
	levels := make(map[string]int) // nodeID -> level
	for nodeID := range d.nodes {
		levels[nodeID] = 0
	}

	// Compute level for each node (max level of dependencies + 1)
	changed := true
	for changed {
		changed = false
		for nodeID, node := range d.nodes {
			maxDepLevel := -1
			for _, depID := range node.Dependencies {
				if levels[depID] > maxDepLevel {
					maxDepLevel = levels[depID]
				}
			}
			newLevel := maxDepLevel + 1
			if newLevel > levels[nodeID] {
				levels[nodeID] = newLevel
				changed = true
			}
		}
	}

	// Group nodes by level
	maxLevel := 0
	for _, level := range levels {
		if level > maxLevel {
			maxLevel = level
		}
	}

	for i := 0; i <= maxLevel; i++ {
		plan.Levels = append(plan.Levels, []string{})
	}

	for nodeID, level := range levels {
		plan.Levels[level] = append(plan.Levels[level], nodeID)
		plan.NodeOrder = append(plan.NodeOrder, nodeID)
	}

	// Copy dependencies
	for nodeID, node := range d.nodes {
		plan.Dependencies[nodeID] = append([]string{}, node.Dependencies...)
	}

	return plan, nil
}

// Retry attempts to retry a failed node
func (d *DAGScheduler) Retry(nodeID string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	node, exists := d.nodes[nodeID]
	if !exists {
		return fmt.Errorf("node %s does not exist", nodeID)
	}

	if !contains(d.failed, nodeID) {
		return fmt.Errorf("node %s is not in failed state", nodeID)
	}

	if node.MaxRetries > 0 && node.Retries >= node.MaxRetries {
		return fmt.Errorf("node %s has exceeded max retries (%d)", nodeID, node.MaxRetries)
	}

	// Remove from failed list
	d.failed = removeString(d.failed, nodeID)

	// Reset status
	node.SetStatus(PENDING)
	node.ErrorMessage = ""
	node.Retries++
	node.StartTime = time.Time{}
	node.EndTime = time.Time{}

	// Update readiness
	allDepsComplete := true
	for _, dep := range node.Dependencies {
		if !contains(d.completed, dep) {
			allDepsComplete = false
			break
		}
	}
	d.readiness[nodeID] = allDepsComplete

	return nil
}

// Clear resets the scheduler state
func (d *DAGScheduler) Clear() {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.nodes = make(map[string]*DAGNode)
	d.readiness = make(map[string]bool)
	d.completed = []string{}
	d.failed = []string{}
	d.nodeOrder = []string{}
	d.cycleDetector = make(map[string]bool)
	d.visitMarks = make(map[string]int)
}

// Utility functions

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func removeString(slice []string, item string) []string {
	result := []string{}
	for _, s := range slice {
		if s != item {
			result = append(result, s)
		}
	}
	return result
}

// DAGValidator validates DAG structure and semantics
type DAGValidator struct {
	scheduler *DAGScheduler
}

// NewDAGValidator creates a validator
func NewDAGValidator(scheduler *DAGScheduler) *DAGValidator {
	return &DAGValidator{scheduler: scheduler}
}

// Validate checks DAG for structural issues
func (dv *DAGValidator) Validate() []string {
	var issues []string

	dv.scheduler.mu.RLock()
	defer dv.scheduler.mu.RUnlock()

	if len(dv.scheduler.nodes) == 0 {
		issues = append(issues, "DAG contains no nodes")
		return issues
	}

	// Check for disconnected components
	visited := make(map[string]bool)
	for nodeID := range dv.scheduler.nodes {
		if !visited[nodeID] {
			dv.markReachable(nodeID, visited)
		}
	}

	if len(visited) != len(dv.scheduler.nodes) {
		issues = append(issues, "DAG contains disconnected components")
	}

	// Check node structure
	for nodeID, node := range dv.scheduler.nodes {
		if node.ID == "" {
			issues = append(issues, fmt.Sprintf("Node has empty ID"))
		}
		for _, depID := range node.Dependencies {
			if _, exists := dv.scheduler.nodes[depID]; !exists {
				issues = append(issues, fmt.Sprintf("Node %s depends on non-existent node %s", nodeID, depID))
			}
		}
	}

	return issues
}

func (dv *DAGValidator) markReachable(nodeID string, visited map[string]bool) {
	if visited[nodeID] {
		return
	}
	visited[nodeID] = true

	node, exists := dv.scheduler.nodes[nodeID]
	if !exists {
		return
	}

	for _, depID := range node.Dependencies {
		dv.markReachable(depID, visited)
	}
}
