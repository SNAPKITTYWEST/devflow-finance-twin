package sandbox

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// PathViolation enum for sandbox violations
type PathViolation int

const (
	SAFE PathViolation = iota
	TRAVERSAL_ATTEMPT
	ABSOLUTE_ESCAPE
	SYMLINK_ESCAPE
	JUNCTION_ESCAPE
	NULL_BYTE
	RESERVED_NAME
)

var violationNames = map[PathViolation]string{
	SAFE:               "SAFE",
	TRAVERSAL_ATTEMPT:  "TRAVERSAL_ATTEMPT",
	ABSOLUTE_ESCAPE:    "ABSOLUTE_ESCAPE",
	SYMLINK_ESCAPE:     "SYMLINK_ESCAPE",
	JUNCTION_ESCAPE:    "JUNCTION_ESCAPE",
	NULL_BYTE:          "NULL_BYTE",
	RESERVED_NAME:      "RESERVED_NAME",
}

func (v PathViolation) String() string {
	if name, ok := violationNames[v]; ok {
		return name
	}
	return "UNKNOWN"
}

var WorkspaceRoot string = ""

var windowsReservedNames = map[string]bool{
	"CON":  true,
	"PRN":  true,
	"AUX":  true,
	"NUL":  true,
	"COM1": true,
	"COM2": true,
	"COM3": true,
	"COM4": true,
	"COM5": true,
	"COM6": true,
	"COM7": true,
	"COM8": true,
	"COM9": true,
	"LPT1": true,
	"LPT2": true,
	"LPT3": true,
	"LPT4": true,
	"LPT5": true,
	"LPT6": true,
	"LPT7": true,
	"LPT8": true,
	"LPT9": true,
}

// CanonicalPath validates and canonicalizes a path within sandbox
func CanonicalPath(input string, allowTraversal bool) (string, PathViolation, error) {
	if input == "" {
		return "", TRAVERSAL_ATTEMPT, errors.New("empty path")
	}

	// Check for null bytes
	if strings.Contains(input, "\x00") {
		return "", NULL_BYTE, errors.New("null byte in path")
	}

	// Check if absolute path
	if filepath.IsAbs(input) {
		// Absolute paths must start with sandbox root
		absInput, err := filepath.Abs(input)
		if err != nil {
			return "", ABSOLUTE_ESCAPE, fmt.Errorf("cannot resolve absolute path: %w", err)
		}
		sandboxAbs, err := filepath.Abs(WorkspaceRoot)
		if err != nil {
			return "", ABSOLUTE_ESCAPE, fmt.Errorf("cannot resolve sandbox root: %w", err)
		}
		if !strings.HasPrefix(absInput, sandboxAbs) && absInput != sandboxAbs {
			return "", ABSOLUTE_ESCAPE, errors.New("absolute path outside sandbox")
		}
		// Verify no traversal components remain
		rel, err := filepath.Rel(sandboxAbs, absInput)
		if err != nil {
			return "", ABSOLUTE_ESCAPE, fmt.Errorf("cannot compute relative path: %w", err)
		}
		if strings.Contains(rel, "..") {
			return "", TRAVERSAL_ATTEMPT, errors.New("traversal detected in absolute path")
		}
		return absInput, SAFE, nil
	}

	// Relative path: check for traversal attempts
	if strings.Contains(input, "..") && !allowTraversal {
		return "", TRAVERSAL_ATTEMPT, errors.New("traversal attempt detected")
	}

	// Split and validate each component
	parts := strings.Split(filepath.Clean(input), string(filepath.Separator))
	for _, part := range parts {
		if part == "" || part == "." {
			continue
		}
		if part == ".." {
			if !allowTraversal {
				return "", TRAVERSAL_ATTEMPT, errors.New("traversal component rejected")
			}
		}
		// Check Windows reserved names
		if windowsReservedNames[strings.ToUpper(part)] {
			return "", RESERVED_NAME, fmt.Errorf("reserved name not allowed: %s", part)
		}
	}

	// Resolve relative to workspace root
	joined := filepath.Join(WorkspaceRoot, input)
	canonical, err := filepath.Abs(joined)
	if err != nil {
		return "", TRAVERSAL_ATTEMPT, fmt.Errorf("cannot canonicalize path: %w", err)
	}

	// Final check: canonical must be within sandbox
	sandboxAbs, err := filepath.Abs(WorkspaceRoot)
	if err != nil {
		return "", ABSOLUTE_ESCAPE, fmt.Errorf("cannot resolve sandbox root: %w", err)
	}

	if !strings.HasPrefix(canonical, sandboxAbs) && canonical != sandboxAbs {
		return "", ABSOLUTE_ESCAPE, errors.New("canonical path escaped sandbox")
	}

	return canonical, SAFE, nil
}

// IsPathInSandbox verifies path is within workspace
func IsPathInSandbox(path string) bool {
	canonical, violation, err := CanonicalPath(path, false)
	if err != nil || violation != SAFE {
		return false
	}
	sandboxAbs, err := filepath.Abs(WorkspaceRoot)
	if err != nil {
		return false
	}
	return strings.HasPrefix(canonical, sandboxAbs) || canonical == sandboxAbs
}

// DetectSymlinkEscape detects symlink/junction attacks
func DetectSymlinkEscape(path string) error {
	canonical, err := filepath.EvalSymlinks(path)
	if err != nil {
		return fmt.Errorf("cannot resolve symlinks: %w", err)
	}

	sandboxAbs, err := filepath.Abs(WorkspaceRoot)
	if err != nil {
		return fmt.Errorf("cannot resolve sandbox root: %w", err)
	}

	if !strings.HasPrefix(canonical, sandboxAbs) && canonical != sandboxAbs {
		return errors.New("symlink points outside sandbox")
	}

	return nil
}

// PreflightExtraction checks archive extraction safety before operation
func PreflightExtraction(archivePath, destPath string, entries []string) error {
	// Validate archive path
	if _, violation, err := CanonicalPath(archivePath, false); err != nil || violation != SAFE {
		return fmt.Errorf("archive path invalid: %w", err)
	}

	// Validate destination
	if _, violation, err := CanonicalPath(destPath, false); err != nil || violation != SAFE {
		return fmt.Errorf("destination path invalid: %w", err)
	}

	// Validate all entries don't escape sandbox
	destAbs, _ := filepath.Abs(destPath)
	sandboxAbs, _ := filepath.Abs(WorkspaceRoot)

	for _, entry := range entries {
		// Check for traversal in entry name
		if strings.Contains(entry, "..") {
			return fmt.Errorf("traversal in entry name: %s", entry)
		}

		// Check if absolute
		if filepath.IsAbs(entry) {
			return fmt.Errorf("absolute entry name not allowed: %s", entry)
		}

		// Resolve final path
		fullPath := filepath.Join(destAbs, entry)
		canonical, err := filepath.Abs(fullPath)
		if err != nil {
			return fmt.Errorf("cannot resolve entry path: %w", err)
		}

		// Must be within sandbox
		if !strings.HasPrefix(canonical, sandboxAbs) && canonical != sandboxAbs {
			return fmt.Errorf("entry would escape sandbox: %s", entry)
		}
	}

	return nil
}

// PostflightVerification verifies extracted files remain in sandbox
func PostflightVerification(destPath string, expectedFiles []string) error {
	destAbs, err := filepath.Abs(destPath)
	if err != nil {
		return fmt.Errorf("cannot resolve destination: %w", err)
	}

	sandboxAbs, err := filepath.Abs(WorkspaceRoot)
	if err != nil {
		return fmt.Errorf("cannot resolve sandbox root: %w", err)
	}

	// Verify all expected files exist and are in sandbox
	for _, file := range expectedFiles {
		fullPath := filepath.Join(destAbs, file)
		canonical, err := filepath.Abs(fullPath)
		if err != nil {
			return fmt.Errorf("cannot verify file %s: %w", file, err)
		}

		// Check within sandbox
		if !strings.HasPrefix(canonical, sandboxAbs) && canonical != sandboxAbs {
			return fmt.Errorf("extracted file outside sandbox: %s", file)
		}

		// Check file exists
		if _, err := os.Stat(canonical); err != nil {
			return fmt.Errorf("extracted file not found: %s", file)
		}
	}

	// Scan for unexpected files (symlinks pointing outside, etc)
	err = filepath.Walk(destAbs, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Check each file is within sandbox
		canonical, err := filepath.Abs(path)
		if err != nil {
			return fmt.Errorf("cannot verify %s: %w", path, err)
		}

		if !strings.HasPrefix(canonical, sandboxAbs) && canonical != sandboxAbs {
			return fmt.Errorf("unexpected file outside sandbox: %s", path)
		}

		// Check symlinks don't escape
		if info.Mode()&os.ModeSymlink != 0 {
			target, err := os.Readlink(path)
			if err != nil {
				return fmt.Errorf("cannot read symlink %s: %w", path, err)
			}
			targetAbs := filepath.Join(filepath.Dir(canonical), target)
			targetCanonical, err := filepath.Abs(targetAbs)
			if err != nil {
				return fmt.Errorf("cannot resolve symlink target: %w", err)
			}
			if !strings.HasPrefix(targetCanonical, sandboxAbs) && targetCanonical != sandboxAbs {
				return fmt.Errorf("symlink escapes sandbox: %s -> %s", path, target)
			}
		}

		return nil
	})

	return err
}
