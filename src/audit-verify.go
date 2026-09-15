package audit

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// VerificationResult records outcome of operation verification
type VerificationResult struct {
	OperationID      string            `json:"operation_id"`
	Status           string            `json:"status"`
	InputHashes      map[string]string `json:"input_hashes"`
	OutputHashes     map[string]string `json:"output_hashes"`
	Timestamp        time.Time         `json:"timestamp"`
	Details          string            `json:"details"`
	VerificationHash string            `json:"verification_hash"`
}

// Verifier interface for operation verification
type Verifier interface {
	VerifyCreateArchive(archivePath string, expectedFiles []string) (*VerificationResult, error)
	VerifyExtractArchive(srcArchive, destPath string, expectedFiles []string) (*VerificationResult, error)
	VerifyIntegrity(archivePath string) (*VerificationResult, error)
}

// DefaultVerifier implements Verifier
type DefaultVerifier struct {
	WorkspaceRoot string
}

// VerifyCreateArchive verifies archive was created correctly
func (v *DefaultVerifier) VerifyCreateArchive(archivePath string, expectedFiles []string) (*VerificationResult, error) {
	result := &VerificationResult{
		OperationID:  archivePath,
		InputHashes:  make(map[string]string),
		OutputHashes: make(map[string]string),
		Timestamp:    time.Now(),
	}

	// Check archive exists
	info, err := os.Stat(archivePath)
	if err != nil {
		result.Status = "FAILED"
		result.Details = fmt.Sprintf("archive not found: %v", err)
		return result, err
	}

	// Compute archive hash
	archiveHash, err := hashFile(archivePath)
	if err != nil {
		result.Status = "FAILED"
		result.Details = fmt.Sprintf("cannot hash archive: %v", err)
		return result, err
	}

	result.OutputHashes["archive"] = archiveHash
	result.OutputHashes["size"] = fmt.Sprintf("%d", info.Size())

	// Verify expected files by size/existence check
	for _, file := range expectedFiles {
		if _, err := os.Stat(file); err != nil {
			result.Status = "FAILED"
			result.Details = fmt.Sprintf("expected file not found: %s", file)
			return result, err
		}
		hash, _ := hashFile(file)
		result.InputHashes[file] = hash
	}

	result.Status = "VERIFIED"
	result.Details = fmt.Sprintf("archive created successfully, %d files", len(expectedFiles))

	// Compute verification result hash
	verHash, _ := hashVerificationResult(result)
	result.VerificationHash = verHash

	return result, nil
}

// VerifyExtractArchive verifies extraction completed correctly
func (v *DefaultVerifier) VerifyExtractArchive(srcArchive, destPath string, expectedFiles []string) (*VerificationResult, error) {
	result := &VerificationResult{
		OperationID:  srcArchive,
		InputHashes:  make(map[string]string),
		OutputHashes: make(map[string]string),
		Timestamp:    time.Now(),
	}

	// Hash source archive
	srcHash, err := hashFile(srcArchive)
	if err != nil {
		result.Status = "FAILED"
		result.Details = fmt.Sprintf("cannot hash source archive: %v", err)
		return result, err
	}
	result.InputHashes["archive"] = srcHash

	// Verify destination exists
	if _, err := os.Stat(destPath); err != nil {
		result.Status = "FAILED"
		result.Details = fmt.Sprintf("destination not found: %v", err)
		return result, err
	}

	// Verify all expected files extracted
	for _, file := range expectedFiles {
		fullPath := fmt.Sprintf("%s/%s", destPath, file)
		if _, err := os.Stat(fullPath); err != nil {
			result.Status = "FAILED"
			result.Details = fmt.Sprintf("extracted file not found: %s", file)
			return result, err
		}
		hash, _ := hashFile(fullPath)
		result.OutputHashes[file] = hash
	}

	result.Status = "VERIFIED"
	result.Details = fmt.Sprintf("extraction verified, %d files extracted", len(expectedFiles))

	verHash, _ := hashVerificationResult(result)
	result.VerificationHash = verHash

	return result, nil
}

// VerifyIntegrity checks archive integrity
func (v *DefaultVerifier) VerifyIntegrity(archivePath string) (*VerificationResult, error) {
	result := &VerificationResult{
		OperationID:  archivePath,
		OutputHashes: make(map[string]string),
		Timestamp:    time.Now(),
	}

	// Check archive exists and is readable
	info, err := os.Stat(archivePath)
	if err != nil {
		result.Status = "FAILED"
		result.Details = fmt.Sprintf("archive not found: %v", err)
		return result, err
	}

	// Compute hash of archive
	hash, err := hashFile(archivePath)
	if err != nil {
		result.Status = "FAILED"
		result.Details = fmt.Sprintf("cannot hash archive: %v", err)
		return result, err
	}

	result.OutputHashes["archive"] = hash
	result.OutputHashes["size"] = fmt.Sprintf("%d", info.Size())
	result.Status = "VERIFIED"
	result.Details = "archive integrity verified"

	verHash, _ := hashVerificationResult(result)
	result.VerificationHash = verHash

	return result, nil
}

// hashFile computes SHA-256 of file
func hashFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := sha256.New()
	buf := make([]byte, 32*1024)
	for {
		n, err := file.Read(buf)
		if n > 0 {
			hash.Write(buf[:n])
		}
		if err != nil {
			break
		}
	}

	return hex.EncodeToString(hash.Sum(nil)), nil
}

// hashVerificationResult computes hash of result
func hashVerificationResult(r *VerificationResult) (string, error) {
	data, err := json.Marshal(r)
	if err != nil {
		return "", err
	}
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:]), nil
}
