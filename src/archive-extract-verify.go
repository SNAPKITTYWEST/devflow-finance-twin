package archive

import (
	"archive/zip"
	"crypto/sha256"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
)

// ExtractArchive extracts a ZIP archive to a specified output directory.
// Implements path safety checks to prevent directory traversal attacks.
type ExtractArchive struct {
	ArchivePath     string
	OutputDir       string
	extractedFiles  []string
	extractedHashes map[string]string
}

// Execute extracts the archive contents to the output directory with safety checks
func (e *ExtractArchive) Execute() error {
	if e.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}
	if e.OutputDir == "" {
		return fmt.Errorf("output directory cannot be empty")
	}

	// Create output directory if it doesn't exist
	if err := os.MkdirAll(e.OutputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Open the archive
	reader, err := zip.OpenReader(e.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	e.extractedFiles = make([]string, 0)
	e.extractedHashes = make(map[string]string)

	// Extract each file with safety checks
	for _, file := range reader.File {
		// Prevent directory traversal attacks
		if err := e.sanitizeAndExtractFile(file); err != nil {
			return err
		}
	}

	return nil
}

// sanitizeAndExtractFile safely extracts a single file from the archive
func (e *ExtractArchive) sanitizeAndExtractFile(file *zip.File) error {
	// Sanitize the file path to prevent traversal
	sanitizedPath := filepath.Join(e.OutputDir, filepath.Base(file.Name))

	// Verify the final path is within output directory
	absOutputDir, err := filepath.Abs(e.OutputDir)
	if err != nil {
		return fmt.Errorf("failed to get absolute output dir: %w", err)
	}

	absSanitizedPath, err := filepath.Abs(sanitizedPath)
	if err != nil {
		return fmt.Errorf("failed to get absolute sanitized path: %w", err)
	}

	// Ensure path is within output directory
	if !strings.HasPrefix(absSanitizedPath, absOutputDir) {
		return fmt.Errorf("path escape detected: %s", file.Name)
	}

	// Skip if it's a directory entry
	if file.FileInfo().IsDir() {
		return nil
	}

	// Skip symlinks and special files
	if (file.ExternalAttrs >> 16) & 0o170000 == 0o120000 {
		// This is a symlink - skip it for security
		return nil
	}

	// Open the file from archive
	rc, err := file.Open()
	if err != nil {
		return fmt.Errorf("failed to open file in archive: %w", err)
	}
	defer rc.Close()

	// Read and hash the content
	content, err := ioutil.ReadAll(rc)
	if err != nil {
		return fmt.Errorf("failed to read file from archive: %w", err)
	}

	// Create the extracted file
	if err := ioutil.WriteFile(sanitizedPath, content, 0644); err != nil {
		return fmt.Errorf("failed to write extracted file: %w", err)
	}

	// Compute hash of extracted content
	hash := sha256.Sum256(content)
	hashHex := fmt.Sprintf("%x", hash)
	e.extractedHashes[sanitizedPath] = hashHex

	e.extractedFiles = append(e.extractedFiles, sanitizedPath)

	return nil
}

// Verify checks the integrity of extracted files
func (e *ExtractArchive) Verify() error {
	if len(e.extractedFiles) == 0 {
		return fmt.Errorf("no files were extracted")
	}

	// Verify all extracted files exist and are readable
	for _, filePath := range e.extractedFiles {
		if _, err := os.Stat(filePath); err != nil {
			return fmt.Errorf("extracted file not found: %s: %w", filePath, err)
		}

		// Verify the hash
		content, err := ioutil.ReadFile(filePath)
		if err != nil {
			return fmt.Errorf("failed to read extracted file for verification: %w", err)
		}

		hash := sha256.Sum256(content)
		hashHex := fmt.Sprintf("%x", hash)

		expectedHash := e.extractedHashes[filePath]
		if hashHex != expectedHash {
			return fmt.Errorf("hash mismatch for extracted file: %s", filePath)
		}
	}

	return nil
}

// Rollback removes extracted files if needed
func (e *ExtractArchive) Rollback() error {
	for _, filePath := range e.extractedFiles {
		if err := os.Remove(filePath); err != nil {
			if !os.IsNotExist(err) {
				return fmt.Errorf("failed to remove extracted file during rollback: %w", err)
			}
		}
	}

	// Remove output directory if it's empty
	entries, err := ioutil.ReadDir(e.OutputDir)
	if err == nil && len(entries) == 0 {
		os.Remove(e.OutputDir)
	}

	return nil
}

// VerifyArchive verifies the integrity and structure of a ZIP archive
// without extracting its contents. Detects archive bombs and validates CRC.
type VerifyArchive struct {
	ArchivePath      string
	fileCount        int
	totalSize        int64
	compressedSize   int64
	uncompressedSize int64
	entries          []string
}

// Execute verifies the archive integrity and checks for security issues
func (v *VerifyArchive) Execute() error {
	if v.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}

	// Verify archive exists
	fileInfo, err := os.Stat(v.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to stat archive: %w", err)
	}

	v.compressedSize = fileInfo.Size()

	// Open and read the archive
	reader, err := zip.OpenReader(v.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive for verification: %w", err)
	}
	defer reader.Close()

	v.fileCount = len(reader.File)
	v.entries = make([]string, 0, v.fileCount)
	v.uncompressedSize = 0

	// Check each entry
	for _, file := range reader.File {
		// Skip directories
		if file.FileInfo().IsDir() {
			continue
		}

		// Add to entries
		v.entries = append(v.entries, file.Name)

		// Track uncompressed size
		v.uncompressedSize += int64(file.UncompressedSize64)

		// Check for potential archive bomb
		if v.uncompressedSize > 5e9 { // 5GB limit
			return fmt.Errorf("archive bomb detected: uncompressed size exceeds 5GB")
		}

		// Check compression ratio
		if file.CompressedSize64 > 0 {
			ratio := float64(file.UncompressedSize64) / float64(file.CompressedSize64)
			if ratio > 100 && file.UncompressedSize64 > 10*1024*1024 { // 100:1 ratio and > 10MB
				return fmt.Errorf("suspicious compression ratio for file %s: %.0f:1", file.Name, ratio)
			}
		}

		// Verify CRC by reading entry
		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("failed to open entry %s: %w", file.Name, err)
		}

		_, err = io.Copy(ioutil.Discard, rc)
		rc.Close()
		if err != nil {
			return fmt.Errorf("CRC verification failed for entry %s: %w", file.Name, err)
		}

		// Check for path traversal in entry names
		if strings.Contains(file.Name, "..") || filepath.IsAbs(file.Name) {
			return fmt.Errorf("path traversal detected in archive entry: %s", file.Name)
		}
	}

	return nil
}

// Verify is a no-op for VerifyArchive as verification is done in Execute
func (v *VerifyArchive) Verify() error {
	return nil
}

// Rollback is a no-op for VerifyArchive since no files were modified
func (v *VerifyArchive) Rollback() error {
	return nil
}

// GetEntryCount returns the number of files in the archive
func (v *VerifyArchive) GetEntryCount() int {
	return v.fileCount
}

// GetCompressedSize returns the total compressed size
func (v *VerifyArchive) GetCompressedSize() int64 {
	return v.compressedSize
}

// GetUncompressedSize returns the total uncompressed size
func (v *VerifyArchive) GetUncompressedSize() int64 {
	return v.uncompressedSize
}

// GetCompressionRatio returns the compression ratio
func (v *VerifyArchive) GetCompressionRatio() float64 {
	if v.uncompressedSize == 0 {
		return 0
	}
	return float64(v.compressedSize) / float64(v.uncompressedSize)
}

// GetEntries returns the list of entries in the archive
func (v *VerifyArchive) GetEntries() []string {
	return v.entries
}
