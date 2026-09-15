package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// TestPathSandboxing tests basic path safety within sandbox
func TestPathSandboxing(t *testing.T) {
	tests := []struct {
		name      string
		path      string
		shouldErr bool
	}{
		{"safe relative", "documents/file.txt", false},
		{"traversal attempt", "../../../etc/passwd", true},
		{"absolute path outside", "/etc/passwd", true},
		{"null byte", "file\x00.txt", true},
	}

	for _, tt := range tests {
		_, violation, err := CanonicalPath(tt.path, false)
		hasErr := err != nil || violation != SAFE
		if hasErr != tt.shouldErr {
			t.Errorf("%s: expected err=%v, got err=%v, violation=%v", tt.name, tt.shouldErr, err, violation)
		}
	}
}

// TestSymlinkDetection tests symlink escape prevention
func TestSymlinkDetection(t *testing.T) {
	tmpDir := t.TempDir()
	WorkspaceRoot = tmpDir

	// Create a file outside sandbox
	outsideFile := filepath.Join(tmpDir, "..", "outside.txt")
	os.MkdirAll(filepath.Dir(outsideFile), 0700)
	os.WriteFile(outsideFile, []byte("outside"), 0600)

	// Create symlink inside sandbox pointing outside
	symlinkPath := filepath.Join(tmpDir, "malicious_link")
	os.Symlink(outsideFile, symlinkPath)

	// Detect should fail
	err := DetectSymlinkEscape(symlinkPath)
	if err == nil {
		t.Errorf("symlink escape not detected")
	}
}

// TestArchiveCreation tests archive creation with verification
func TestArchiveCreation(t *testing.T) {
	tmpDir := t.TempDir()
	WorkspaceRoot = tmpDir

	// Create test files
	file1 := filepath.Join(tmpDir, "file1.txt")
	file2 := filepath.Join(tmpDir, "file2.txt")
	os.WriteFile(file1, []byte("content1"), 0600)
	os.WriteFile(file2, []byte("content2"), 0600)

	// Create archive
	archivePath := filepath.Join(tmpDir, "test.zip")
	createOp := CreateArchive{
		ArchivePath:      archivePath,
		InputFiles:       []string{file1, file2},
		CompressionLevel: 6,
	}

	if err := createOp.Execute(); err != nil {
		t.Fatalf("execute failed: %v", err)
	}

	if err := createOp.Verify(); err != nil {
		t.Fatalf("verify failed: %v", err)
	}

	// Verify archive exists
	if _, err := os.Stat(archivePath); err != nil {
		t.Fatalf("archive not created: %v", err)
	}
}

// TestExtractionSafety tests extraction with path safety checks
func TestExtractionSafety(t *testing.T) {
	tmpDir := t.TempDir()
	WorkspaceRoot = tmpDir

	// Create archive
	file1 := filepath.Join(tmpDir, "file1.txt")
	os.WriteFile(file1, []byte("content"), 0600)

	archivePath := filepath.Join(tmpDir, "test.zip")
	createOp := CreateArchive{
		ArchivePath:      archivePath,
		InputFiles:       []string{file1},
		CompressionLevel: 6,
	}
	createOp.Execute()

	// Extract with safety checks
	destDir := filepath.Join(tmpDir, "extracted")
	extractOp := ExtractArchive{
		ArchivePath:     archivePath,
		DestinationPath: destDir,
	}

	if err := extractOp.Execute(); err != nil {
		t.Fatalf("extract failed: %v", err)
	}

	// Verify extraction safety
	if err := PostflightVerification(destDir, extractOp.ExtractedFiles); err != nil {
		t.Fatalf("postflight failed: %v", err)
	}
}

// TestPolicyEnforcement tests policy authorization
func TestPolicyEnforcement(t *testing.T) {
	policies := PolicySet{
		Rules: map[OperationType]PolicyRule{
			OP_CREATE_ARCHIVE: {
				AllowedPaths:    []string{"*"},
				MaxFileSize:     1e6,
				RateLimitPerMin: 10,
			},
		},
	}

	// Authorize valid operation
	authorized, _ := policies.EvaluatePolicy(OP_CREATE_ARCHIVE, "/valid/path")
	if !authorized {
		t.Errorf("valid operation rejected")
	}
}

// TestAuditLedger tests audit seal generation and verification
func TestAuditLedger(t *testing.T) {
	tmpDir := t.TempDir()
	ledgerFile := filepath.Join(tmpDir, "audit.jsonl")

	ledger := NewAuditLedger(ledgerFile)

	// Append record
	seal := &DecisionSeal{
		OperationID:       "test-op-1",
		UserRequest:       "create archive",
		NormalizedTask:    "create_archive:test.zip",
		PolicyDecision:    "AUTHORIZED",
		ExecutionResult:   "SUCCESS",
		VerificationResult: "VERIFIED",
		Timestamp:         time.Now(),
	}

	if err := ledger.AppendRecord(seal); err != nil {
		t.Fatalf("append failed: %v", err)
	}

	// Verify seal hash
	if seal.SealHash == "" {
		t.Errorf("seal hash not set")
	}

	// Verify chain
	if err := ledger.VerifyChain(); err != nil {
		t.Fatalf("chain verification failed: %v", err)
	}
}

// TestTamperingDetection tests audit ledger tampering detection
func TestTamperingDetection(t *testing.T) {
	tmpDir := t.TempDir()
	ledgerFile := filepath.Join(tmpDir, "audit.jsonl")

	ledger := NewAuditLedger(ledgerFile)

	seal := &DecisionSeal{
		OperationID: "test-op-1",
		Timestamp:   time.Now(),
	}

	ledger.AppendRecord(seal)

	// Tamper with seal
	if len(ledger.Records) > 0 {
		ledger.Records[0].SealHash = "tampered"
	}

	// Detection should work
	tampered, _ := ledger.DetectTampering()
	if !tampered {
		t.Errorf("tampering not detected")
	}
}

// TestDAGCycleDetection tests DAG cycle prevention
func TestDAGCycleDetection(t *testing.T) {
	scheduler := &DAGScheduler{
		Nodes:     make(map[string]*DAGNode),
		Readiness: make(map[string]bool),
	}

	node1 := &DAGNode{ID: "task1", Dependencies: []string{"task2"}}
	node2 := &DAGNode{ID: "task2", Dependencies: []string{"task1"}}

	scheduler.AddNode(node1)
	err := scheduler.AddNode(node2)

	if err == nil {
		t.Errorf("cycle not detected")
	}
}

// TestTopologicalSort tests dependency resolution
func TestTopologicalSort(t *testing.T) {
	scheduler := &DAGScheduler{
		Nodes:     make(map[string]*DAGNode),
		Readiness: make(map[string]bool),
	}

	// Create dependency chain: 1 -> 2 -> 3
	node3 := &DAGNode{ID: "task3", Dependencies: []string{}}
	node2 := &DAGNode{ID: "task2", Dependencies: []string{"task3"}}
	node1 := &DAGNode{ID: "task1", Dependencies: []string{"task2"}}

	scheduler.AddNode(node1)
	scheduler.AddNode(node2)
	scheduler.AddNode(node3)

	// First ready nodes should be task3
	ready := scheduler.ResolveReady()
	if len(ready) != 1 || ready[0].ID != "task3" {
		t.Errorf("incorrect ready nodes")
	}

	// Mark complete and check next
	scheduler.MarkComplete("task3")
	ready = scheduler.ResolveReady()
	if len(ready) != 1 || ready[0].ID != "task2" {
		t.Errorf("incorrect ready nodes after task3 complete")
	}
}

// TestEndToEndWorkflow tests complete create-extract cycle
func TestEndToEndWorkflow(t *testing.T) {
	tmpDir := t.TempDir()
	WorkspaceRoot = tmpDir

	// Setup
	policies := &PolicySet{
		Rules: map[OperationType]PolicyRule{
			OP_CREATE_ARCHIVE:   {AllowedPaths: []string{"*"}},
			OP_EXTRACT_ARCHIVE: {AllowedPaths: []string{"*"}},
		},
	}

	// Create test files
	file1 := filepath.Join(tmpDir, "data.txt")
	os.WriteFile(file1, []byte("important data"), 0600)

	// Create archive
	archivePath := filepath.Join(tmpDir, "backup.zip")
	createOp := CreateArchive{
		ArchivePath:      archivePath,
		InputFiles:       []string{file1},
		CompressionLevel: 6,
	}

	if err := createOp.Execute(); err != nil {
		t.Fatalf("create failed: %v", err)
	}
	if err := createOp.Verify(); err != nil {
		t.Fatalf("create verify failed: %v", err)
	}

	// Extract archive
	destDir := filepath.Join(tmpDir, "restored")
	extractOp := ExtractArchive{
		ArchivePath:     archivePath,
		DestinationPath: destDir,
	}

	if err := extractOp.Execute(); err != nil {
		t.Fatalf("extract failed: %v", err)
	}
	if err := extractOp.Verify(); err != nil {
		t.Fatalf("extract verify failed: %v", err)
	}

	// Verify restoration
	restoredFile := filepath.Join(destDir, filepath.Base(file1))
	data, err := os.ReadFile(restoredFile)
	if err != nil || string(data) != "important data" {
		t.Fatalf("data restoration failed")
	}

	fmt.Printf("✓ End-to-end test passed: create -> extract -> verify\n")
}

// Run all tests
func main() {
	fmt.Println("Running acceptance tests...")
	// Tests would be run with 'go test'
