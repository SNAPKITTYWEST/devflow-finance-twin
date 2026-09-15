package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"./sandbox"
	"./control"
	"./archive"
	"./audit"
)

var (
	sandboxWorkspaceRoot = "./sandbox_workspace"
	auditLedgerFile      = "audit.jsonl"
)

func main() {
	// Initialize sandbox environment
	if err := initSandbox(); err != nil {
		log.Fatalf("Failed to initialize sandbox: %v", err)
	}

	// Initialize audit ledger
	ledger := &audit.AuditLedger{Filename: auditLedgerFile}
	if err := ledger.Initialize(); err != nil {
		log.Fatalf("Failed to initialize audit ledger: %v", err)
	}

	// Initialize policy set with archive operation rules
	policies := &control.PolicySet{
		Rules: map[control.OperationType]control.PolicyRule{
			control.OP_CREATE_ARCHIVE: {
				AllowedPaths:         []string{"*"},
				MaxFileSize:          1e9,
				RequiresConfirmation: false,
			},
			control.OP_EXTRACT_ARCHIVE: {
				AllowedPaths:         []string{"*"},
				RequiresConfirmation: false,
			},
			control.OP_VERIFY_ARCHIVE: {
				AllowedPaths:         []string{"*"},
				RequiresConfirmation: false,
			},
		},
	}

	// Parse command-line arguments
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	// Initialize DAG scheduler for operation orchestration
	scheduler := control.NewDAGScheduler()

	// Route command to appropriate handler
	command := os.Args[1]

	switch command {
	case "create":
		handleCreateArchive(os.Args[2:], policies, ledger, scheduler)
	case "extract":
		handleExtractArchive(os.Args[2:], policies, ledger, scheduler)
	case "verify":
		handleVerifyArchive(os.Args[2:], policies, ledger, scheduler)
	case "audit":
		handleAuditCommand(os.Args[2:], ledger)
	case "help", "-h", "--help":
		printUsage()
	default:
		fmt.Printf("Unknown operation: %s\n", command)
		printUsage()
		os.Exit(1)
	}

	log.Println("Operation completed, audit sealed")
}

func initSandbox() error {
	sandbox.WorkspaceRoot = sandboxWorkspaceRoot
	if err := os.MkdirAll(sandbox.WorkspaceRoot, 0700); err != nil {
		return fmt.Errorf("failed to create sandbox workspace: %w", err)
	}
	return nil
}

func printUsage() {
	fmt.Println(`
Archive Manager - Secure Archive Operations

USAGE:
  archive-manager create <archive.zip> <file1> [file2] ...    Create a new archive
  archive-manager extract <archive.zip> [<output-dir>]        Extract archive to directory
  archive-manager verify <archive.zip>                         Verify archive integrity
  archive-manager audit [list|show]                            View audit ledger
  archive-manager help                                         Show this help

EXAMPLES:
  archive-manager create backup.zip file1.txt file2.txt
  archive-manager extract backup.zip extracted/
  archive-manager verify backup.zip
  archive-manager audit list
`)
}

func handleCreateArchive(args []string, policies *control.PolicySet,
	ledger *audit.AuditLedger, scheduler *control.DAGScheduler) {
	if len(args) < 2 {
		fmt.Println("Error: create requires archive path and at least one input file")
		os.Exit(1)
	}

	archivePath := args[0]
	inputFiles := args[1:]

	// Authorize via policy
	rule := policies.Rules[control.OP_CREATE_ARCHIVE]
	if !rule.Authorized() {
		fmt.Println("Operation not authorized by policy")
		os.Exit(1)
	}

	// Validate file paths are within sandbox
	for _, file := range inputFiles {
		if !sandbox.IsPathSafe(file) {
			fmt.Printf("Error: path traversal detected in %s\n", file)
			os.Exit(1)
		}
	}

	// Create DAG node for this operation
	nodeID := fmt.Sprintf("create_%d", time.Now().UnixNano())
	node := control.NewDAGNode(nodeID, control.OP_CREATE_ARCHIVE)
	node.Inputs = inputFiles
	node.Outputs = []string{archivePath}
	node.SetStatus(control.AUTHORIZED)

	// Add to scheduler
	if err := scheduler.AddNode(node); err != nil {
		log.Fatalf("Failed to add node to scheduler: %v", err)
	}

	// Execute archive creation
	createOp := &archive.CreateArchive{
		ArchivePath:      archivePath,
		InputFiles:       inputFiles,
		CompressionLevel: 6,
	}

	node.SetStatus(control.RUNNING)
	if err := createOp.Execute(); err != nil {
		node.ErrorMessage = err.Error()
		node.SetStatus(control.FAILED)
		ledger.LogEvent("ARCHIVE_CREATE_FAILED", nodeID, fmt.Sprintf("Error: %v", err))
		log.Fatalf("Failed to create archive: %v", err)
	}

	// Verify archive
	node.SetStatus(control.VERIFIED)
	if err := createOp.Verify(); err != nil {
		node.ErrorMessage = err.Error()
		node.SetStatus(control.FAILED)
		ledger.LogEvent("ARCHIVE_VERIFY_FAILED", nodeID, fmt.Sprintf("Error: %v", err))
		log.Fatalf("Failed to verify archive: %v", err)
	}

	// Generate decision seal
	seal := &audit.DecisionSeal{
		OperationID: nodeID,
		OperationType: "CREATE_ARCHIVE",
		Timestamp:   time.Now(),
		ResourceURI: archivePath,
		Decision:    "APPROVED",
		Reason:      "Archive creation successful",
	}
	if err := seal.GenerateHash(); err != nil {
		log.Fatalf("Failed to generate seal: %v", err)
	}

	// Record in audit ledger
	if err := ledger.AppendSeal(seal); err != nil {
		log.Fatalf("Failed to append seal to ledger: %v", err)
	}

	node.SetStatus(control.COMMITTED)
	fmt.Printf("Successfully created archive: %s\n", archivePath)
	fmt.Printf("Decision seal: %s\n", seal.Hash)
}

func handleExtractArchive(args []string, policies *control.PolicySet,
	ledger *audit.AuditLedger, scheduler *control.DAGScheduler) {
	if len(args) < 1 {
		fmt.Println("Error: extract requires archive path")
		os.Exit(1)
	}

	archivePath := args[0]
	outputDir := "."
	if len(args) > 1 {
		outputDir = args[1]
	}

	// Authorize via policy
	rule := policies.Rules[control.OP_EXTRACT_ARCHIVE]
	if !rule.Authorized() {
		fmt.Println("Operation not authorized by policy")
		os.Exit(1)
	}

	// Validate output directory is safe
	if !sandbox.IsPathSafe(outputDir) {
		fmt.Printf("Error: path traversal detected in %s\n", outputDir)
		os.Exit(1)
	}

	// Create output directory
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		log.Fatalf("Failed to create output directory: %v", err)
	}

	// Create DAG node
	nodeID := fmt.Sprintf("extract_%d", time.Now().UnixNano())
	node := control.NewDAGNode(nodeID, control.OP_EXTRACT_ARCHIVE)
	node.Inputs = []string{archivePath}
	node.Outputs = []string{outputDir}
	node.SetStatus(control.AUTHORIZED)

	if err := scheduler.AddNode(node); err != nil {
		log.Fatalf("Failed to add node to scheduler: %v", err)
	}

	// Execute extraction
	extractOp := &archive.ExtractArchive{
		ArchivePath: archivePath,
		OutputDir:   outputDir,
	}

	node.SetStatus(control.RUNNING)
	if err := extractOp.Execute(); err != nil {
		node.ErrorMessage = err.Error()
		node.SetStatus(control.FAILED)
		ledger.LogEvent("ARCHIVE_EXTRACT_FAILED", nodeID, fmt.Sprintf("Error: %v", err))
		log.Fatalf("Failed to extract archive: %v", err)
	}

	// Verify extraction
	node.SetStatus(control.VERIFIED)
	if err := extractOp.Verify(); err != nil {
		node.ErrorMessage = err.Error()
		node.SetStatus(control.FAILED)
		ledger.LogEvent("ARCHIVE_EXTRACT_VERIFY_FAILED", nodeID, fmt.Sprintf("Error: %v", err))
		log.Fatalf("Failed to verify extraction: %v", err)
	}

	// Generate decision seal
	seal := &audit.DecisionSeal{
		OperationID:   nodeID,
		OperationType: "EXTRACT_ARCHIVE",
		Timestamp:     time.Now(),
		ResourceURI:   archivePath,
		Decision:      "APPROVED",
		Reason:        "Archive extraction successful",
	}
	if err := seal.GenerateHash(); err != nil {
		log.Fatalf("Failed to generate seal: %v", err)
	}

	if err := ledger.AppendSeal(seal); err != nil {
		log.Fatalf("Failed to append seal to ledger: %v", err)
	}

	node.SetStatus(control.COMMITTED)
	fmt.Printf("Successfully extracted archive to: %s\n", outputDir)
	fmt.Printf("Decision seal: %s\n", seal.Hash)
}

func handleVerifyArchive(args []string, policies *control.PolicySet,
	ledger *audit.AuditLedger, scheduler *control.DAGScheduler) {
	if len(args) < 1 {
		fmt.Println("Error: verify requires archive path")
		os.Exit(1)
	}

	archivePath := args[0]

	// Authorize via policy
	rule := policies.Rules[control.OP_VERIFY_ARCHIVE]
	if !rule.Authorized() {
		fmt.Println("Operation not authorized by policy")
		os.Exit(1)
	}

	// Create DAG node
	nodeID := fmt.Sprintf("verify_%d", time.Now().UnixNano())
	node := control.NewDAGNode(nodeID, control.OP_VERIFY_ARCHIVE)
	node.Inputs = []string{archivePath}
	node.SetStatus(control.AUTHORIZED)

	if err := scheduler.AddNode(node); err != nil {
		log.Fatalf("Failed to add node to scheduler: %v", err)
	}

	// Execute verification
	verifyOp := &archive.VerifyArchive{
		ArchivePath: archivePath,
	}

	node.SetStatus(control.RUNNING)
	if err := verifyOp.Execute(); err != nil {
		node.ErrorMessage = err.Error()
		node.SetStatus(control.FAILED)
		ledger.LogEvent("ARCHIVE_VERIFY_FAILED", nodeID, fmt.Sprintf("Error: %v", err))
		log.Fatalf("Failed to verify archive: %v", err)
	}

	// Generate decision seal
	seal := &audit.DecisionSeal{
		OperationID:   nodeID,
		OperationType: "VERIFY_ARCHIVE",
		Timestamp:     time.Now(),
		ResourceURI:   archivePath,
		Decision:      "APPROVED",
		Reason:        "Archive verification successful",
	}
	if err := seal.GenerateHash(); err != nil {
		log.Fatalf("Failed to generate seal: %v", err)
	}

	if err := ledger.AppendSeal(seal); err != nil {
		log.Fatalf("Failed to append seal to ledger: %v", err)
	}

	node.SetStatus(control.COMMITTED)
	fmt.Printf("Archive integrity verified: %s\n", archivePath)
	fmt.Printf("Decision seal: %s\n", seal.Hash)
}

func handleAuditCommand(args []string, ledger *audit.AuditLedger) {
	if len(args) == 0 {
		args = []string{"list"}
	}

	command := args[0]

	switch command {
	case "list":
		entries, err := ledger.ListEntries()
		if err != nil {
			log.Fatalf("Failed to list audit entries: %v", err)
		}
		fmt.Printf("Audit ledger contains %d entries\n", len(entries))
		for i, entry := range entries {
			fmt.Printf("[%d] %s\n", i, entry)
		}

	case "show":
		if err := ledger.PrintLedger(); err != nil {
			log.Fatalf("Failed to print ledger: %v", err)
		}

	default:
		fmt.Printf("Unknown audit command: %s\n", command)
		os.Exit(1)
	}
}
