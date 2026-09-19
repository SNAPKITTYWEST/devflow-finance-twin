package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"hash"
	"hash/crc32"
	"hash/fnv"
)

// ============================================================
// TURING BINARY FOUNDATION
// Bytes, Words, Magic Headers, Lexical Tokens
// ============================================================

const (
	// Magic header for Turing Foundation binary format
	MagicHeaderFoundation uint32 = 0x5455524E // "TURN"

	// Version for this binary format
	VersionFoundation uint16 = 0x0001

	// Word size in bytes
	WordSize = 2
)

// TuringHeader is the magic header + version for all Turing binaries.
type TuringHeader struct {
	Magic   uint32 `binary:"magic,big-endian"`
	Version uint16 `binary:"version,big-endian"`
	Reserved uint16 `binary:"reserved,big-endian"` // For future use
}

// LexicalToken represents a lexical token from the Turing tokenizer.
type LexicalToken struct {
	Type       uint16    `binary:"type,big-endian"`        // TokenType enum
	Offset     uint32    `binary:"offset,big-endian"`      // Byte offset in source
	Length     uint16    `binary:"length,big-endian"`      // Token length in bytes
	LineNumber uint32    `binary:"line_number,big-endian"` // Source line
	ColumnNumber uint32  `binary:"column_number,big-endian"` // Source column
	ValueHash  [32]byte `binary:"value_hash,big-endian"`   // SHA-256 of token text
}

// TokenType enumerations
const (
	TokenTypeEOF     uint16 = 0x0000
	TokenTypeAtom    uint16 = 0x0001
	TokenTypeVariable uint16 = 0x0002
	TokenTypeInteger uint16 = 0x0003
	TokenTypeFloat   uint16 = 0x0004
	TokenTypeString  uint16 = 0x0005
	TokenTypeLParen  uint16 = 0x0006
	TokenTypeRParen  uint16 = 0x0007
	TokenTypeComma   uint16 = 0x0008
	TokenTypeDot     uint16 = 0x0009
	TokenTypePipe    uint16 = 0x000A
	TokenTypeNAND    uint16 = 0x000B
	TokenTypeHalt    uint16 = 0x000C
	TokenTypeLoad    uint16 = 0x000D
	TokenTypeStore   uint16 = 0x000E
	TokenTypeLDI     uint16 = 0x000F
	TokenTypeJMP     uint16 = 0x0010
	TokenTypeJZ      uint16 = 0x0011
)

// WordBinary represents a 16-bit word in big-endian encoding.
type WordBinary struct {
	Value uint16 `binary:"value,big-endian"`
}

// ByteSequence represents a sequence of bytes with length prefix.
type ByteSequence struct {
	Length uint32    `binary:"length,big-endian"`
	Data   []byte    `binary:"data,rest"`
}

// LexicalTokenStream contains multiple tokens with count prefix.
type LexicalTokenStream struct {
	Count  uint32           `binary:"count,big-endian"`
	Tokens []LexicalToken   `binary:"tokens,rest"`
}

// NANDInstruction represents a NAND instruction (16-bit word format).
//   bits [15:12] = OP
//   bits [11: 8] = DST
//   bits [ 7: 4] = A
//   bits [ 3: 0] = B
type NANDInstruction struct {
	Raw uint16 `binary:"raw,big-endian"`
}

// InstructionType enumerations
const (
	OpNAND   uint16 = 0x0
	OpHalt   uint16 = 0x1
	OpLoad   uint16 = 0x2
	OpStore  uint16 = 0x3
	OpLDI    uint16 = 0x4
	OpJMP    uint16 = 0x5
	OpJZ     uint16 = 0x6
)

// ============================================================
// BUILDERS & CONSTRUCTORS
// ============================================================

// NewTuringHeader creates a properly initialized Turing header.
func NewTuringHeader() *TuringHeader {
	return &TuringHeader{
		Magic:    MagicHeaderFoundation,
		Version:  VersionFoundation,
		Reserved: 0,
	}
}

// NewLexicalToken creates and validates a LexicalToken.
func NewLexicalToken(tokenType uint16, offset, length uint32, line, column uint32, valueText []byte) *LexicalToken {
	hash := sha256.Sum256(valueText)
	return &LexicalToken{
		Type:         tokenType,
		Offset:       offset,
		Length:       length,
		LineNumber:   line,
		ColumnNumber: column,
		ValueHash:    hash,
	}
}

// NewNANDInstruction encodes a NAND instruction.
func NewNANDInstruction(op, dst, a, b uint16) *NANDInstruction {
	raw := ((op & 0xF) << 12) | ((dst & 0xF) << 8) | ((a & 0xF) << 4) | (b & 0xF)
	return &NANDInstruction{Raw: raw}
}

// NewNANDLoad encodes a LOAD instruction.
func NewNANDLoad(dst, a, imm4 uint16) *NANDInstruction {
	return NewNANDInstruction(OpLoad, dst, a, imm4&0xF)
}

// NewNANDStore encodes a STORE instruction.
func NewNANDStore(dst, a, imm4 uint16) *NANDInstruction {
	return NewNANDInstruction(OpStore, dst, a, imm4&0xF)
}

// NewNANDLDI encodes a LDI (Load Immediate) instruction.
func NewNANDLDI(dst, imm8 uint16) *NANDInstruction {
	a := (imm8 >> 4) & 0xF
	b := imm8 & 0xF
	return NewNANDInstruction(OpLDI, dst, a, b)
}

// NewNANDJMP encodes a JMP instruction.
func NewNANDJMP(addr uint16) *NANDInstruction {
	return NewNANDInstruction(OpJMP, 0, addr&0xF, 0)
}

// NewNANDJZ encodes a JZ (Jump if Zero) instruction.
func NewNANDJZ(dst, addr uint16) *NANDInstruction {
	return NewNANDInstruction(OpJZ, dst, addr&0xF, 0)
}

// NewNANDHalt encodes a HALT instruction.
func NewNANDHalt() *NANDInstruction {
	return NewNANDInstruction(OpHalt, 0, 0, 0)
}

// ============================================================
// BINARY MARSHALING (encoding/binary.Read/Write)
// ============================================================

// MarshalBinary encodes TuringHeader to big-endian bytes.
func (h *TuringHeader) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, h.Magic); err != nil {
		return nil, fmt.Errorf("marshal magic: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, h.Version); err != nil {
		return nil, fmt.Errorf("marshal version: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, h.Reserved); err != nil {
		return nil, fmt.Errorf("marshal reserved: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes TuringHeader from big-endian bytes.
func (h *TuringHeader) UnmarshalBinary(data []byte) error {
	if len(data) < 8 {
		return fmt.Errorf("header too short: %d < 8", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &h.Magic); err != nil {
		return fmt.Errorf("unmarshal magic: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &h.Version); err != nil {
		return fmt.Errorf("unmarshal version: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &h.Reserved); err != nil {
		return fmt.Errorf("unmarshal reserved: %w", err)
	}
	return nil
}

// MarshalBinary encodes LexicalToken to big-endian bytes.
func (t *LexicalToken) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, t.Type); err != nil {
		return nil, fmt.Errorf("marshal type: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.Offset); err != nil {
		return nil, fmt.Errorf("marshal offset: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.Length); err != nil {
		return nil, fmt.Errorf("marshal length: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.LineNumber); err != nil {
		return nil, fmt.Errorf("marshal line: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.ColumnNumber); err != nil {
		return nil, fmt.Errorf("marshal column: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.ValueHash[:]); err != nil {
		return nil, fmt.Errorf("marshal hash: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes LexicalToken from big-endian bytes.
func (t *LexicalToken) UnmarshalBinary(data []byte) error {
	if len(data) < 46 { // 2+4+2+4+4+32
		return fmt.Errorf("token too short: %d < 46", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &t.Type); err != nil {
		return fmt.Errorf("unmarshal type: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.Offset); err != nil {
		return fmt.Errorf("unmarshal offset: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.Length); err != nil {
		return fmt.Errorf("unmarshal length: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.LineNumber); err != nil {
		return fmt.Errorf("unmarshal line: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.ColumnNumber); err != nil {
		return fmt.Errorf("unmarshal column: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.ValueHash); err != nil {
		return fmt.Errorf("unmarshal hash: %w", err)
	}
	return nil
}

// MarshalBinary encodes NANDInstruction to big-endian bytes.
func (ni *NANDInstruction) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, ni.Raw); err != nil {
		return nil, fmt.Errorf("marshal instruction: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes NANDInstruction from big-endian bytes.
func (ni *NANDInstruction) UnmarshalBinary(data []byte) error {
	if len(data) < 2 {
		return fmt.Errorf("instruction too short: %d < 2", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &ni.Raw); err != nil {
		return fmt.Errorf("unmarshal instruction: %w", err)
	}
	return nil
}

// MarshalBinary encodes WordBinary to big-endian bytes.
func (w *WordBinary) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, w.Value); err != nil {
		return nil, fmt.Errorf("marshal word: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes WordBinary from big-endian bytes.
func (w *WordBinary) UnmarshalBinary(data []byte) error {
	if len(data) < 2 {
		return fmt.Errorf("word too short: %d < 2", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &w.Value); err != nil {
		return fmt.Errorf("unmarshal word: %w", err)
	}
	return nil
}

// ============================================================
// VALIDATION & AST CONSTRAINTS
// ============================================================

// Validate checks TuringHeader for AST constraints.
func (h *TuringHeader) Validate() error {
	if h.Magic != MagicHeaderFoundation {
		return fmt.Errorf("invalid magic: got 0x%08X, want 0x%08X", h.Magic, MagicHeaderFoundation)
	}
	if h.Version != VersionFoundation {
		return fmt.Errorf("unsupported version: got 0x%04X, want 0x%04X", h.Version, VersionFoundation)
	}
	return nil
}

// Validate checks LexicalToken for AST constraints.
func (t *LexicalToken) Validate() error {
	if t.Type > 0x0011 {
		return fmt.Errorf("invalid token type: 0x%04X", t.Type)
	}
	if t.Length == 0 {
		return fmt.Errorf("token length must be > 0")
	}
	if t.LineNumber == 0 {
		return fmt.Errorf("line number must be > 0")
	}
	return nil
}

// Validate checks NANDInstruction for AST constraints.
func (ni *NANDInstruction) Validate() error {
	op := (ni.Raw >> 12) & 0xF
	if op > OpJZ {
		return fmt.Errorf("invalid opcode: 0x%X", op)
	}
	return nil
}

// ValidateTokenStream validates all tokens in a stream.
func ValidateTokenStream(tokens []LexicalToken) error {
	for i, t := range tokens {
		if err := t.Validate(); err != nil {
			return fmt.Errorf("token %d: %w", i, err)
		}
	}
	return nil
}

// ============================================================
// HASH COMPUTATION (SHA-256, CRC-32, FNV-1a)
// ============================================================

// ComputeSHA256 computes SHA-256 hash of marshaled binary.
func ComputeSHA256(data []byte) [32]byte {
	return sha256.Sum256(data)
}

// ComputeCRC32 computes CRC-32 (IEEE) hash of marshaled binary.
func ComputeCRC32(data []byte) uint32 {
	table := crc32.MakeTable(crc32.IEEE)
	return crc32.Checksum(data, table)
}

// ComputeFNV1a computes FNV-1a hash of marshaled binary.
func ComputeFNV1a(data []byte) uint64 {
	h := fnv.New64a()
	h.Write(data)
	return h.Sum64()
}

// HashableBinary wraps binary data with hash fields.
type HashableBinary struct {
	Data   []byte
	SHA256 [32]byte
	CRC32  uint32
	FNV1a  uint64
}

// ComputeHashes computes all three hashes for binary data.
func (hb *HashableBinary) ComputeHashes() {
	hb.SHA256 = ComputeSHA256(hb.Data)
	hb.CRC32 = ComputeCRC32(hb.Data)
	hb.FNV1a = ComputeFNV1a(hb.Data)
}

// VerifyHashes verifies all computed hashes.
func (hb *HashableBinary) VerifyHashes() error {
	expectedSHA256 := ComputeSHA256(hb.Data)
	if expectedSHA256 != hb.SHA256 {
		return fmt.Errorf("SHA256 mismatch")
	}

	expectedCRC32 := ComputeCRC32(hb.Data)
	if expectedCRC32 != hb.CRC32 {
		return fmt.Errorf("CRC32 mismatch")
	}

	expectedFNV1a := ComputeFNV1a(hb.Data)
	if expectedFNV1a != hb.FNV1a {
		return fmt.Errorf("FNV1a mismatch")
	}

	return nil
}

// HeaderWithHashes extends TuringHeader with hash fields.
type HeaderWithHashes struct {
	Header  TuringHeader
	SHA256  [32]byte
	CRC32   uint32
	FNV1a   uint64
}

// MarshalBinary encodes HeaderWithHashes to big-endian bytes.
func (h *HeaderWithHashes) MarshalBinary() ([]byte, error) {
	headerData, err := h.Header.MarshalBinary()
	if err != nil {
		return nil, err
	}

	buf := new(bytes.Buffer)
	buf.Write(headerData)
	if err := binary.Write(buf, binary.BigEndian, h.SHA256[:]); err != nil {
		return nil, fmt.Errorf("marshal SHA256: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, h.CRC32); err != nil {
		return nil, fmt.Errorf("marshal CRC32: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, h.FNV1a); err != nil {
		return nil, fmt.Errorf("marshal FNV1a: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes HeaderWithHashes from big-endian bytes.
func (h *HeaderWithHashes) UnmarshalBinary(data []byte) error {
	if len(data) < 8+32+4+8 {
		return fmt.Errorf("data too short for header with hashes")
	}
	if err := h.Header.UnmarshalBinary(data[:8]); err != nil {
		return err
	}
	buf := bytes.NewReader(data[8:])
	if err := binary.Read(buf, binary.BigEndian, &h.SHA256); err != nil {
		return fmt.Errorf("unmarshal SHA256: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &h.CRC32); err != nil {
		return fmt.Errorf("unmarshal CRC32: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &h.FNV1a); err != nil {
		return fmt.Errorf("unmarshal FNV1a: %w", err)
	}
	return nil
}

// Validate checks HeaderWithHashes for AST constraints.
func (h *HeaderWithHashes) Validate() error {
	if err := h.Header.Validate(); err != nil {
		return err
	}
	return nil
}
