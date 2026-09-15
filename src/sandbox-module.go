package sandbox

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// WorkspaceRoot is the root directory for sandbox operations
var WorkspaceRoot string

// IsPathSafe checks if a given path is safe and does not attempt traversal
// Returns true if the path is safe, false if it contains traversal attempts
func IsPathSafe(path string) bool {
	// Reject empty paths
	if path == "" {
		return false
	}

	// Normalize path separators to forward slashes for consistent checking
	normalized := filepath.ToSlash(path)

	// Reject absolute paths
	if filepath.IsAbs(path) {
		return false
	}

	// Reject paths that contain ".." components
	if strings.Contains(normalized, "..") {
		return false
	}

	// Split path and check each component
	components := strings.Split(normalized, "/")
	for _, component := range components {
		// Reject "." or ".." as individual components
		if component == "." || component == ".." {
			return false
		}

		// Reject components that are just dots
		if strings.TrimSpace(component) != component {
			return false
		}
	}

	// Check for null bytes (path traversal attempt in Windows)
	if strings.Contains(path, "\x00") {
		return false
	}

	return true
}

// ResolvePath resolves a path within the sandbox workspace
// Returns the full path if safe, error otherwise
func ResolvePath(relativePath string) (string, error) {
	if !IsPathSafe(relativePath) {
		return "", fmt.Errorf("unsafe path: %s", relativePath)
	}

	// If WorkspaceRoot is not set, use current directory
	root := WorkspaceRoot
	if root == "" {
		root = "."
	}

	fullPath := filepath.Join(root, relativePath)

	// Final safety check: verify the resolved path is within workspace
	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		return "", fmt.Errorf("failed to resolve absolute path: %w", err)
	}

	absRoot, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("failed to resolve workspace root: %w", err)
	}

	// Ensure resolved path starts with root
	if !strings.HasPrefix(absPath, absRoot) {
		return "", fmt.Errorf("path escapes workspace: %s", absPath)
	}

	return fullPath, nil
}

// CreateSandboxDirectory creates a directory within the sandbox
func CreateSandboxDirectory(relativePath string) error {
	fullPath, err := ResolvePath(relativePath)
	if err != nil {
		return err
	}

	if err := os.MkdirAll(fullPath, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	return nil
}

// GetWorkspaceInfo returns information about the workspace
func GetWorkspaceInfo() map[string]interface{} {
	info := make(map[string]interface{})

	if WorkspaceRoot == "" {
		info["root"] = "not configured"
		return info
	}

	info["root"] = WorkspaceRoot

	fileInfo, err := os.Stat(WorkspaceRoot)
	if err != nil {
		info["status"] = "error: " + err.Error()
		return info
	}

	info["exists"] = fileInfo.IsDir()
	info["mode"] = fileInfo.Mode().String()

	// Count files in workspace
	count := 0
	filepath.Walk(WorkspaceRoot, func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			count++
		}
		return nil
	})
	info["file_count"] = count

	return info
}

// CleanupSandbox removes sandbox workspace
func CleanupSandbox() error {
	if WorkspaceRoot == "" {
		return fmt.Errorf("workspace root not configured")
	}

	if err := os.RemoveAll(WorkspaceRoot); err != nil {
		return fmt.Errorf("failed to cleanup sandbox: %w", err)
	}

	return nil
}
