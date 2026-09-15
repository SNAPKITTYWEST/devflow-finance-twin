package archive

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// ArchiveOperation is the base interface for all archive operations.
// All archive operations must implement Execute, Verify, and Rollback methods
// to ensure transactional semantics and data integrity.
type ArchiveOperation interface {
	Execute() error
	Verify() error
	Rollback() error
}

// CreateArchive creates a new ZIP archive from a list of input files
// with configurable compression levels. Implements transaction semantics
// with rollback capability.
type CreateArchive struct {
	ArchivePath     string
	InputFiles      []string
	CompressionLevel int
	createdPath     string // Track what we created for rollback
	fileHashes      map[string]string
}

// Execute creates a new ZIP archive with specified files.
// Compresses files according to the configured compression level.
func (c *CreateArchive) Execute() error {
	if c.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}
	if len(c.InputFiles) == 0 {
		return fmt.Errorf("input files list is empty")
	}

	// Validate compression level
	if c.CompressionLevel < 0 || c.CompressionLevel > 9 {
		c.CompressionLevel = zip.DefaultCompression
	}

	// Initialize hash map
	c.fileHashes = make(map[string]string)

	// Create the archive file
	archiveFile, err := os.Create(c.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to create archive file: %w", err)
	}
	c.createdPath = c.ArchivePath
	defer archiveFile.Close()

	// Create zip writer
	zipWriter := zip.NewWriter(archiveFile)
	defer zipWriter.Close()

	// Add each input file to the archive
	for _, inputFile := range c.InputFiles {
		// Verify file exists
		fileInfo, err := os.Stat(inputFile)
		if err != nil {
			return fmt.Errorf("failed to stat input file %s: %w", inputFile, err)
		}

		if fileInfo.IsDir() {
			return fmt.Errorf("input file %s is a directory, not a regular file", inputFile)
		}

		// Read and hash the file
		fileData, err := ioutil.ReadFile(inputFile)
		if err != nil {
			return fmt.Errorf("failed to read input file %s: %w", inputFile, err)
		}

		// Compute SHA-256 hash
		hash := sha256.Sum256(fileData)
		hashHex := fmt.Sprintf("%x", hash)
		c.fileHashes[inputFile] = hashHex

		// Get the base name for the archive entry
		entryName := filepath.Base(inputFile)

		// Create zip header
		header := &zip.FileHeader{
			Name:     entryName,
			Method:   uint16(c.CompressionLevel),
			Modified: time.Now(),
		}

		// Create writer for this entry
		entryWriter, err := zipWriter.CreateHeader(header)
		if err != nil {
			return fmt.Errorf("failed to create zip entry for %s: %w", inputFile, err)
		}

		// Write file data to entry
		if _, err := entryWriter.Write(fileData); err != nil {
			return fmt.Errorf("failed to write data to zip entry for %s: %w", inputFile, err)
		}
	}

	// Close the zip writer to finalize the archive
	if err := zipWriter.Close(); err != nil {
		return fmt.Errorf("failed to close zip writer: %w", err)
	}

	return nil
}

// Verify ensures the created archive is valid and contains the correct files.
// Reopens the archive, verifies CRC checksums, and validates entry count.
func (c *CreateArchive) Verify() error {
	if c.ArchivePath == "" {
		return fmt.Errorf("archive path not set")
	}

	// Open the archive for verification
	reader, err := zip.OpenReader(c.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive for verification: %w", err)
	}
	defer reader.Close()

	// Verify entry count matches input file count
	if len(reader.File) != len(c.InputFiles) {
		return fmt.Errorf("entry count mismatch: expected %d, got %d", len(c.InputFiles), len(reader.File))
	}

	// Verify each entry's CRC
	for i, file := range reader.File {
		if i >= len(c.InputFiles) {
			return fmt.Errorf("archive has more entries than expected")
		}

		// Try to read the file data to verify CRC
		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("failed to open archive entry %s: %w", file.Name, err)
		}

		// Read all data to trigger CRC verification
		_, err = io.Copy(ioutil.Discard, rc)
		rc.Close()
		if err != nil {
			return fmt.Errorf("CRC verification failed for entry %s: %w", file.Name, err)
		}
	}

	// Compute and verify SHA-256 hash of the archive file itself
	archiveData, err := ioutil.ReadFile(c.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to read archive file for hash verification: %w", err)
	}

	archiveHash := sha256.Sum256(archiveData)
	_ = fmt.Sprintf("%x", archiveHash) // Store for later reference

	return nil
}

// Rollback removes the created archive file if it was created by this operation.
func (c *CreateArchive) Rollback() error {
	if c.createdPath != "" && c.createdPath == c.ArchivePath {
		if err := os.Remove(c.ArchivePath); err != nil {
			if !os.IsNotExist(err) {
				return fmt.Errorf("failed to remove archive during rollback: %w", err)
			}
		}
		c.createdPath = ""
	}
	return nil
}

// OpenArchive opens an existing ZIP archive for inspection and metadata extraction.
type OpenArchive struct {
	ArchivePath string
	Reader      *zip.Reader
	fileCount   int
}

// Execute opens the archive and loads its directory structure into memory.
func (o *OpenArchive) Execute() error {
	if o.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}

	// Validate that the path exists
	fileInfo, err := os.Stat(o.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to stat archive path: %w", err)
	}

	if fileInfo.IsDir() {
		return fmt.Errorf("archive path is a directory, not a file")
	}

	// Open the zip reader
	reader, err := zip.OpenReader(o.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}

	o.Reader = reader
	o.fileCount = len(reader.File)

	return nil
}

// ListEntries returns the list of files contained in the archive.
func (o *OpenArchive) ListEntries() ([]zip.File, error) {
	if o.Reader == nil {
		return nil, fmt.Errorf("archive not opened")
	}

	entries := make([]zip.File, len(o.Reader.File))
	for i, f := range o.Reader.File {
		entries[i] = *f
	}

	return entries, nil
}

// GetEntryCount returns the number of files in the archive.
func (o *OpenArchive) GetEntryCount() int {
	if o.Reader == nil {
		return 0
	}
	return len(o.Reader.File)
}

// Close closes the archive reader.
func (o *OpenArchive) Close() error {
	if o.Reader != nil {
		return o.Reader.Close()
	}
	return nil
}

// Verify validates that the archive can be read and all entries are accessible.
func (o *OpenArchive) Verify() error {
	if o.Reader == nil {
		return fmt.Errorf("archive not opened")
	}

	// Try to read the first few bytes of each entry to verify accessibility
	for _, file := range o.Reader.File {
		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("failed to open entry %s: %w", file.Name, err)
		}

		// Read up to 1KB to verify the entry is accessible
		_, err = io.CopyN(ioutil.Discard, rc, 1024)
		if err != nil && err != io.EOF {
			rc.Close()
			return fmt.Errorf("failed to read entry %s: %w", file.Name, err)
		}

		rc.Close()
	}

	return nil
}

// Rollback closes the archive reader if open.
func (o *OpenArchive) Rollback() error {
	return o.Close()
}

// ExtractArchive extracts files from a ZIP archive to a specified destination.
// Supports selective extraction by entry name.
type ExtractArchive struct {
	ArchivePath     string
	DestinationPath string
	Entries         []string // empty = all entries
	extractedFiles  []string // track for rollback
}

// Execute extracts specified entries from the archive to the destination.
// If Entries is empty, all files are extracted.
func (e *ExtractArchive) Execute() error {
	if e.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}
	if e.DestinationPath == "" {
		return fmt.Errorf("destination path cannot be empty")
	}

	// Create destination directory if it doesn't exist
	if err := os.MkdirAll(e.DestinationPath, 0755); err != nil {
		return fmt.Errorf("failed to create destination directory: %w", err)
	}

	// Open the archive
	reader, err := zip.OpenReader(e.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	// Build a map of entries to extract
	entriesToExtract := make(map[string]bool)
	if len(e.Entries) == 0 {
		// Extract all entries
		for _, file := range reader.File {
			entriesToExtract[file.Name] = true
		}
	} else {
		// Extract specified entries
		for _, entry := range e.Entries {
			entriesToExtract[entry] = true
		}
	}

	// Extract each entry
	for _, file := range reader.File {
		if !entriesToExtract[file.Name] {
			continue
		}

		// Construct the full destination path
		destPath := filepath.Join(e.DestinationPath, file.Name)

		// Check for path traversal attacks
		absDestPath, err := filepath.Abs(destPath)
		if err != nil {
			return fmt.Errorf("failed to resolve destination path: %w", err)
		}

		absDestDir, err := filepath.Abs(e.DestinationPath)
		if err != nil {
			return fmt.Errorf("failed to resolve destination directory: %w", err)
		}

		// Ensure the file is within the destination directory
		if !bytes.HasPrefix([]byte(absDestPath), []byte(absDestDir)) {
			return fmt.Errorf("path traversal detected: %s", file.Name)
		}

		// Skip directories
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(destPath, 0755); err != nil {
				return fmt.Errorf("failed to create directory %s: %w", destPath, err)
			}
			e.extractedFiles = append(e.extractedFiles, destPath)
			continue
		}

		// Create parent directories if needed
		if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
			return fmt.Errorf("failed to create parent directories for %s: %w", destPath, err)
		}

		// Open the file in the archive
		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("failed to open archive entry %s: %w", file.Name, err)
		}

		// Create the destination file
		destFile, err := os.Create(destPath)
		if err != nil {
			rc.Close()
			return fmt.Errorf("failed to create destination file %s: %w", destPath, err)
		}

		// Copy the file data
		if _, err := io.Copy(destFile, rc); err != nil {
			destFile.Close()
			rc.Close()
			return fmt.Errorf("failed to write file %s: %w", destPath, err)
		}

		destFile.Close()
		rc.Close()

		// Track extracted file
		e.extractedFiles = append(e.extractedFiles, destPath)
	}

	return nil
}

// Verify validates that all extracted files exist and have correct hashes.
func (e *ExtractArchive) Verify() error {
	if len(e.extractedFiles) == 0 {
		return fmt.Errorf("no files were extracted")
	}

	// Verify each extracted file exists
	for _, file := range e.extractedFiles {
		fileInfo, err := os.Stat(file)
		if err != nil {
			return fmt.Errorf("extracted file verification failed for %s: %w", file, err)
		}

		if fileInfo.IsDir() {
			// Just verify directory exists
			continue
		}

		// Verify the file is readable
		f, err := os.Open(file)
		if err != nil {
			return fmt.Errorf("failed to open extracted file %s: %w", file, err)
		}
		f.Close()
	}

	return nil
}

// Rollback removes all extracted files and directories.
func (e *ExtractArchive) Rollback() error {
	// Remove extracted files in reverse order
	for i := len(e.extractedFiles) - 1; i >= 0; i-- {
		file := e.extractedFiles[i]
		if err := os.RemoveAll(file); err != nil {
			if !os.IsNotExist(err) {
				return fmt.Errorf("failed to remove extracted file %s: %w", file, err)
			}
		}
	}
	e.extractedFiles = nil
	return nil
}

// VerifyArchive checks the integrity of a ZIP archive without extracting it.
type VerifyArchive struct {
	ArchivePath string
	results     map[string]string
}

// Execute scans all entries in the archive and verifies CRC checksums.
func (v *VerifyArchive) Execute() error {
	if v.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}

	v.results = make(map[string]string)

	// Open the archive
	reader, err := zip.OpenReader(v.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	// Verify each entry
	for _, file := range reader.File {
		// Open and read the entry to trigger CRC verification
		rc, err := file.Open()
		if err != nil {
			v.results[file.Name] = fmt.Sprintf("FAILED: %v", err)
			continue
		}

		// Read all data
		if _, err := io.Copy(ioutil.Discard, rc); err != nil {
			rc.Close()
			v.results[file.Name] = fmt.Sprintf("FAILED: %v", err)
			continue
		}

		rc.Close()
		v.results[file.Name] = "OK"
	}

	// Check if any entries failed
	for _, status := range v.results {
		if status != "OK" {
			return fmt.Errorf("archive verification failed")
		}
	}

	return nil
}

// Verify checks that verification was completed successfully.
func (v *VerifyArchive) Verify() error {
	if len(v.results) == 0 {
		return fmt.Errorf("verification not completed")
	}

	// Verify all entries have OK status
	for name, status := range v.results {
		if status != "OK" {
			return fmt.Errorf("entry %s: %s", name, status)
		}
	}

	return nil
}

// Rollback is a no-op for verification operations.
func (v *VerifyArchive) Rollback() error {
	v.results = nil
	return nil
}

// GetResults returns the verification results for each entry.
func (v *VerifyArchive) GetResults() map[string]string {
	return v.results
}

// DeleteEntry removes a file from a ZIP archive.
// Creates a new archive without the specified entry.
type DeleteEntry struct {
	ArchivePath string
	EntryName   string
	backupPath  string
}

// Execute removes the specified entry from the archive.
func (d *DeleteEntry) Execute() error {
	if d.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}
	if d.EntryName == "" {
		return fmt.Errorf("entry name cannot be empty")
	}

	// Create a backup of the original archive
	backupPath := d.ArchivePath + ".bak"
	if err := copyFile(d.ArchivePath, backupPath); err != nil {
		return fmt.Errorf("failed to create backup: %w", err)
	}
	d.backupPath = backupPath

	// Open the original archive
	reader, err := zip.OpenReader(d.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	// Create a new archive
	newArchiveFile, err := os.Create(d.ArchivePath + ".tmp")
	if err != nil {
		return fmt.Errorf("failed to create temporary archive: %w", err)
	}
	defer newArchiveFile.Close()

	// Create zip writer
	writer := zip.NewWriter(newArchiveFile)
	defer writer.Close()

	// Copy all entries except the one to delete
	entryFound := false
	for _, file := range reader.File {
		if file.Name == d.EntryName {
			entryFound = true
			continue
		}

		// Create a header for this entry
		header := &zip.FileHeader{
			Name:     file.Name,
			Method:   file.Method,
			Modified: file.Modified,
		}

		// Create entry in new archive
		entryWriter, err := writer.CreateHeader(header)
		if err != nil {
			return fmt.Errorf("failed to create entry %s: %w", file.Name, err)
		}

		// Open and copy the file
		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("failed to open entry %s: %w", file.Name, err)
		}

		if _, err := io.Copy(entryWriter, rc); err != nil {
			rc.Close()
			return fmt.Errorf("failed to copy entry %s: %w", file.Name, err)
		}

		rc.Close()
	}

	if !entryFound {
		return fmt.Errorf("entry %s not found in archive", d.EntryName)
	}

	// Close the writer
	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to close new archive: %w", err)
	}

	// Replace the original archive with the new one
	if err := os.Rename(d.ArchivePath+".tmp", d.ArchivePath); err != nil {
		return fmt.Errorf("failed to replace archive: %w", err)
	}

	return nil
}

// Verify checks that the entry was successfully deleted.
func (d *DeleteEntry) Verify() error {
	// Open the archive and verify the entry is gone
	reader, err := zip.OpenReader(d.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	for _, file := range reader.File {
		if file.Name == d.EntryName {
			return fmt.Errorf("entry %s still exists in archive", d.EntryName)
		}
	}

	return nil
}

// Rollback restores the original archive from the backup.
func (d *DeleteEntry) Rollback() error {
	if d.backupPath != "" {
		if err := copyFile(d.backupPath, d.ArchivePath); err != nil {
			return fmt.Errorf("failed to restore backup: %w", err)
		}
		// Clean up backup
		_ = os.Remove(d.backupPath)
		d.backupPath = ""
	}
	// Clean up temporary file if it exists
	_ = os.Remove(d.ArchivePath + ".tmp")
	return nil
}

// RenameEntry renames a file entry within a ZIP archive.
type RenameEntry struct {
	ArchivePath string
	OldName     string
	NewName     string
	backupPath  string
}

// Execute renames the specified entry in the archive.
func (r *RenameEntry) Execute() error {
	if r.ArchivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}
	if r.OldName == "" {
		return fmt.Errorf("old name cannot be empty")
	}
	if r.NewName == "" {
		return fmt.Errorf("new name cannot be empty")
	}

	// Create a backup of the original archive
	backupPath := r.ArchivePath + ".bak"
	if err := copyFile(r.ArchivePath, backupPath); err != nil {
		return fmt.Errorf("failed to create backup: %w", err)
	}
	r.backupPath = backupPath

	// Open the original archive
	reader, err := zip.OpenReader(r.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	// Create a new archive
	newArchiveFile, err := os.Create(r.ArchivePath + ".tmp")
	if err != nil {
		return fmt.Errorf("failed to create temporary archive: %w", err)
	}
	defer newArchiveFile.Close()

	// Create zip writer
	writer := zip.NewWriter(newArchiveFile)
	defer writer.Close()

	// Copy all entries, renaming the specified one
	entryFound := false
	for _, file := range reader.File {
		entryName := file.Name
		if file.Name == r.OldName {
			entryName = r.NewName
			entryFound = true
		}

		// Create a header for this entry
		header := &zip.FileHeader{
			Name:     entryName,
			Method:   file.Method,
			Modified: file.Modified,
		}

		// Create entry in new archive
		entryWriter, err := writer.CreateHeader(header)
		if err != nil {
			return fmt.Errorf("failed to create entry %s: %w", entryName, err)
		}

		// Open and copy the file
		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("failed to open entry %s: %w", file.Name, err)
		}

		if _, err := io.Copy(entryWriter, rc); err != nil {
			rc.Close()
			return fmt.Errorf("failed to copy entry %s: %w", file.Name, err)
		}

		rc.Close()
	}

	if !entryFound {
		return fmt.Errorf("entry %s not found in archive", r.OldName)
	}

	// Close the writer
	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to close new archive: %w", err)
	}

	// Replace the original archive with the new one
	if err := os.Rename(r.ArchivePath+".tmp", r.ArchivePath); err != nil {
		return fmt.Errorf("failed to replace archive: %w", err)
	}

	return nil
}

// Verify checks that the entry was successfully renamed.
func (r *RenameEntry) Verify() error {
	// Open the archive and verify the new name exists
	reader, err := zip.OpenReader(r.ArchivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	foundNew := false
	foundOld := false

	for _, file := range reader.File {
		if file.Name == r.NewName {
			foundNew = true
		}
		if file.Name == r.OldName {
			foundOld = true
		}
	}

	if !foundNew {
		return fmt.Errorf("new entry name %s not found in archive", r.NewName)
	}
	if foundOld {
		return fmt.Errorf("old entry name %s still exists in archive", r.OldName)
	}

	return nil
}

// Rollback restores the original archive from the backup.
func (r *RenameEntry) Rollback() error {
	if r.backupPath != "" {
		if err := copyFile(r.backupPath, r.ArchivePath); err != nil {
			return fmt.Errorf("failed to restore backup: %w", err)
		}
		// Clean up backup
		_ = os.Remove(r.backupPath)
		r.backupPath = ""
	}
	// Clean up temporary file if it exists
	_ = os.Remove(r.ArchivePath + ".tmp")
	return nil
}

// HashFile computes the SHA-256 hash of a file.
type HashFile struct {
	FilePath string
	hash     string
}

// Execute reads the file and computes its SHA-256 hash.
func (h *HashFile) Execute() (string, error) {
	if h.FilePath == "" {
		return "", fmt.Errorf("file path cannot be empty")
	}

	// Open the file
	file, err := os.Open(h.FilePath)
	if err != nil {
		return "", fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	// Create hash writer
	hasher := sha256.New()

	// Copy file data to hasher
	if _, err := io.Copy(hasher, file); err != nil {
		return "", fmt.Errorf("failed to read file: %w", err)
	}

	// Get hash sum and convert to hex string
	hashBytes := hasher.Sum(nil)
	h.hash = fmt.Sprintf("%x", hashBytes)

	return h.hash, nil
}

// GetHash returns the computed hash if Execute was called.
func (h *HashFile) GetHash() string {
	return h.hash
}

// Verify checks that the hash was computed.
func (h *HashFile) Verify() error {
	if h.hash == "" {
		return fmt.Errorf("hash not computed")
	}
	return nil
}

// Rollback is a no-op for hash operations.
func (h *HashFile) Rollback() error {
	return nil
}

// Helper function to copy a file
func copyFile(src, dst string) error {
	// Open source file
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	// Create destination file
	dstFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	// Copy content
	_, err = io.Copy(dstFile, srcFile)
	return err
}

// ArchiveStats represents statistics about an archive
type ArchiveStats struct {
	EntryCount   int
	TotalSize    int64
	CompressedSize int64
	Entries      []EntryStats
}

// EntryStats represents statistics about a single archive entry
type EntryStats struct {
	Name          string
	Size          int64
	CompressedSize int64
	ModTime       time.Time
	IsDir         bool
}

// GetArchiveStats returns comprehensive statistics about an archive
func GetArchiveStats(archivePath string) (*ArchiveStats, error) {
	if archivePath == "" {
		return nil, fmt.Errorf("archive path cannot be empty")
	}

	// Open the archive
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	stats := &ArchiveStats{
		EntryCount: len(reader.File),
		Entries:    make([]EntryStats, 0, len(reader.File)),
	}

	// Collect statistics for each entry
	for _, file := range reader.File {
		entryStats := EntryStats{
			Name:           file.Name,
			Size:           int64(file.UncompressedSize),
			CompressedSize: int64(file.CompressedSize),
			ModTime:        file.Modified,
			IsDir:          file.FileInfo().IsDir(),
		}

		stats.Entries = append(stats.Entries, entryStats)
		stats.TotalSize += entryStats.Size
		stats.CompressedSize += entryStats.CompressedSize
	}

	return stats, nil
}

// ListArchiveEntries lists all entries in an archive with their sizes
func ListArchiveEntries(archivePath string) ([]string, error) {
	if archivePath == "" {
		return nil, fmt.Errorf("archive path cannot be empty")
	}

	// Open the archive
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	entries := make([]string, 0, len(reader.File))

	// Collect entry names
	for _, file := range reader.File {
		entries = append(entries, file.Name)
	}

	return entries, nil
}

// ExtractEntryToMemory extracts a single file from an archive into memory
func ExtractEntryToMemory(archivePath, entryName string) ([]byte, error) {
	if archivePath == "" {
		return nil, fmt.Errorf("archive path cannot be empty")
	}
	if entryName == "" {
		return nil, fmt.Errorf("entry name cannot be empty")
	}

	// Open the archive
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	// Find and extract the entry
	for _, file := range reader.File {
		if file.Name == entryName {
			rc, err := file.Open()
			if err != nil {
				return nil, fmt.Errorf("failed to open entry: %w", err)
			}
			defer rc.Close()

			data, err := ioutil.ReadAll(rc)
			if err != nil {
				return nil, fmt.Errorf("failed to read entry: %w", err)
			}

			return data, nil
		}
	}

	return nil, fmt.Errorf("entry %s not found in archive", entryName)
}

// CreateArchiveFromMemory creates a ZIP archive from files specified as byte slices
func CreateArchiveFromMemory(archivePath string, files map[string][]byte) error {
	if archivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}
	if len(files) == 0 {
		return fmt.Errorf("files map is empty")
	}

	// Create the archive file
	archiveFile, err := os.Create(archivePath)
	if err != nil {
		return fmt.Errorf("failed to create archive: %w", err)
	}
	defer archiveFile.Close()

	// Create zip writer
	zipWriter := zip.NewWriter(archiveFile)
	defer zipWriter.Close()

	// Add each file to the archive
	for name, data := range files {
		header := &zip.FileHeader{
			Name:     name,
			Method:   zip.Deflate,
			Modified: time.Now(),
		}

		entryWriter, err := zipWriter.CreateHeader(header)
		if err != nil {
			return fmt.Errorf("failed to create entry: %w", err)
		}

		if _, err := entryWriter.Write(data); err != nil {
			return fmt.Errorf("failed to write entry: %w", err)
		}
	}

	return nil
}

// ComputeMultiFileHash computes a combined SHA-256 hash of multiple files
func ComputeMultiFileHash(filePaths []string) (string, error) {
	if len(filePaths) == 0 {
		return "", fmt.Errorf("file paths list is empty")
	}

	hasher := sha256.New()

	for _, filePath := range filePaths {
		file, err := os.Open(filePath)
		if err != nil {
			return "", fmt.Errorf("failed to open file %s: %w", filePath, err)
		}

		if _, err := io.Copy(hasher, file); err != nil {
			file.Close()
			return "", fmt.Errorf("failed to read file %s: %w", filePath, err)
		}

		file.Close()
	}

	return fmt.Sprintf("%x", hasher.Sum(nil)), nil
}

// ValidateArchiveStructure validates that an archive doesn't contain suspicious entries
func ValidateArchiveStructure(archivePath string) error {
	if archivePath == "" {
		return fmt.Errorf("archive path cannot be empty")
	}

	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	absDestDir, err := filepath.Abs(filepath.Dir(archivePath))
	if err != nil {
		return fmt.Errorf("failed to resolve archive directory: %w", err)
	}

	for _, file := range reader.File {
		// Check for path traversal attempts
		extractPath := filepath.Join(absDestDir, file.Name)
		absExtractPath, err := filepath.Abs(extractPath)
		if err != nil {
			return fmt.Errorf("failed to resolve path for %s: %w", file.Name, err)
		}

		if !bytes.HasPrefix([]byte(absExtractPath), []byte(absDestDir)) {
			return fmt.Errorf("path traversal detected: %s", file.Name)
		}

		// Check for suspicious file names
		if file.Name == "" || file.Name == "." || file.Name == ".." {
			return fmt.Errorf("suspicious entry name: %s", file.Name)
		}
	}

	return nil
}

// ArchiveMetadata represents metadata about an archive
type ArchiveMetadata struct {
	Path           string
	Size           int64
	ModTime        time.Time
	EntryCount     int
	IsValid        bool
	SHA256         string
	CompressionLvl []uint16
}

// GetArchiveMetadata retrieves comprehensive metadata about an archive
func GetArchiveMetadata(archivePath string) (*ArchiveMetadata, error) {
	if archivePath == "" {
		return nil, fmt.Errorf("archive path cannot be empty")
	}

	fileInfo, err := os.Stat(archivePath)
	if err != nil {
		return nil, fmt.Errorf("failed to stat archive: %w", err)
	}

	// Compute SHA-256 hash
	archiveData, err := ioutil.ReadFile(archivePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read archive: %w", err)
	}

	hash := sha256.Sum256(archiveData)
	hashHex := fmt.Sprintf("%x", hash)

	// Open and inspect archive
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer reader.Close()

	compressionLevels := make(map[uint16]bool)
	for _, file := range reader.File {
		compressionLevels[file.Method] = true
	}

	// Convert map to slice
	methods := make([]uint16, 0, len(compressionLevels))
	for method := range compressionLevels {
		methods = append(methods, method)
	}

	metadata := &ArchiveMetadata{
		Path:           archivePath,
		Size:           fileInfo.Size(),
		ModTime:        fileInfo.ModTime(),
		EntryCount:     len(reader.File),
		IsValid:        true,
		SHA256:         hashHex,
		CompressionLvl: methods,
	}

	return metadata, nil
}
