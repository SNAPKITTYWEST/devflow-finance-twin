package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"hash/crc32"
	"hash/fnv"
)

// ============================================================
// TURING QUIPPER & JCL
// Quipper Circuit Gates, Wire Declarations, Manifests
// ============================================================

const (
	// Magic header for Turing Quipper/JCL binary format
	MagicHeaderQuipper uint32 = 0x5149505F // "QIP_"
	VersionQuipper     uint16 = 0x0001
)

// GateType enumerations for quantum gates
const (
	GateTypeHadamard uint16 = iota
	GateTypePauliX
	GateTypePauliY
	GateTypePauliZ
	GateTypeS
	GateTypeT
	GateTypeSGate
	GateTypeTGate
	GateTypeRx
	GateTypeRy
	GateTypeRz
	GateTypeCNOT
	GateTypeCZ
	GateTypeSWAP
	GateTypeToffoli
	GateTypeMeasure
	GateTypeControlledU
	GateTypeControlledRz
	GateTypeQFT
	GateTypeQFTInverse
)

// WireType enumerations
const (
	WireTypeQubit uint16 = iota
	WireTypeClassical
	WireTypeMixed
)

// QuipperGate represents a quantum gate operation.
type QuipperGate struct {
	GateID        uint32    `binary:"gate_id,big-endian"`
	Type          uint16    `binary:"type,big-endian"`          // GateType
	ControlQubits []uint32  `binary:"control_qubits,rest"`      // For controlled gates
	TargetQubits  []uint32  `binary:"target_qubits,rest"`       // Target qubit indices
	ControlCount  uint16    `binary:"control_count,big-endian"`
	TargetCount   uint16    `binary:"target_count,big-endian"`
	Parameter     float64   `binary:"parameter,big-endian"`     // For parameterized gates (Rx, Ry, Rz)
	HasParameter  bool      `binary:"has_parameter,byte"`
}

// WireDeclaration represents a qubit or classical wire in circuit.
type WireDeclaration struct {
	WireID    uint32   `binary:"wire_id,big-endian"`
	Type      uint16   `binary:"type,big-endian"`         // WireType
	BitWidth  uint16   `binary:"bit_width,big-endian"`    // 1 for qubit, >1 for classical
	NameLen   uint16   `binary:"name_len,big-endian"`
	NameHash  [32]byte `binary:"name_hash,big-endian"`    // SHA-256 of wire name
	IsInput   bool     `binary:"is_input,byte"`
	IsOutput  bool     `binary:"is_output,byte"`
}

// QuipperCircuit represents a complete quantum circuit.
type QuipperCircuit struct {
	CircuitID          uint32              `binary:"circuit_id,big-endian"`
	GateCount          uint32              `binary:"gate_count,big-endian"`
	Gates              []QuipperGate       `binary:"gates,rest"`
	WireCount          uint32              `binary:"wire_count,big-endian"`
	Wires              []WireDeclaration   `binary:"wires,rest"`
	Depth              uint32              `binary:"depth,big-endian"`        // Circuit depth (layers)
	QubitCount         uint32              `binary:"qubit_count,big-endian"`
	ClassicalBitCount  uint32              `binary:"classical_bit_count,big-endian"`
}

// JCLInstruction represents a JCL (Turing Job Control Language) instruction.
type JCLInstruction struct {
	InstructionID uint32   `binary:"instruction_id,big-endian"`
	OpCode        uint16   `binary:"opcode,big-endian"`         // Operation type
	ArgumentCount uint16   `binary:"argument_count,big-endian"`
	Arguments     []uint32 `binary:"arguments,rest"`            // Argument IDs
	ControlFlags  uint32   `binary:"control_flags,big-endian"`
}

// JCLInstructionOpcodes
const (
	JCLOpcodeSubmit uint16 = iota
	JCLOpcodeAwait
	JCLOpcodeCancel
	JCLOpcodeRetry
	JCLOpcodeRoute
	JCLOpcodeBatch
	JCLOpcodeParallel
	JCLOpcodeSequence
	JCLOpcodeConditional
	JCLOpcodeLoop
)

// JCLManifest represents a JCL job manifest.
type JCLManifest struct {
	ManifestID        uint32              `binary:"manifest_id,big-endian"`
	JobID             uint32              `binary:"job_id,big-endian"`
	CircuitID         uint32              `binary:"circuit_id,big-endian"`
	InstructionCount  uint32              `binary:"instruction_count,big-endian"`
	Instructions      []JCLInstruction    `binary:"instructions,rest"`
	Priority          uint16              `binary:"priority,big-endian"`
	Deadline          uint64              `binary:"deadline,big-endian"`           // Unix timestamp
	RetryPolicy       uint16              `binary:"retry_policy,big-endian"`
	MaxRetries        uint16              `binary:"max_retries,big-endian"`
	TimeoutMS         uint32              `binary:"timeout_ms,big-endian"`
	ResourceRequest   uint32              `binary:"resource_request,big-endian"`   // Memory/CPU bitmask
}

// CircuitExecutionTrace represents execution trace of circuit.
type CircuitExecutionTrace struct {
	TraceID          uint32     `binary:"trace_id,big-endian"`
	CircuitID        uint32     `binary:"circuit_id,big-endian"`
	ExecutionTimeNS  uint64     `binary:"execution_time_ns,big-endian"`
	SuccessCount     uint32     `binary:"success_count,big-endian"`
	TotalShots       uint32     `binary:"total_shots,big-endian"`
	FidelityEstimate float64    `binary:"fidelity_estimate,big-endian"`
	MeasurementCount uint32     `binary:"measurement_count,big-endian"`
	Measurements     []uint64   `binary:"measurements,rest"`
}

// ============================================================
// BUILDERS & CONSTRUCTORS
// ============================================================

// NewQuipperGate creates a quantum gate.
func NewQuipperGate(gateID uint32, gateType uint16, targets []uint32) *QuipperGate {
	return &QuipperGate{
		GateID:        gateID,
		Type:          gateType,
		ControlQubits: []uint32{},
		TargetQubits:  targets,
		ControlCount:  0,
		TargetCount:   uint16(len(targets)),
		Parameter:     0.0,
		HasParameter:  false,
	}
}

// NewParameterizedGate creates a parameterized quantum gate.
func NewParameterizedGate(gateID uint32, gateType uint16, targets []uint32, param float64) *QuipperGate {
	gate := NewQuipperGate(gateID, gateType, targets)
	gate.Parameter = param
	gate.HasParameter = true
	return gate
}

// AddControl adds a control qubit to a gate.
func (g *QuipperGate) AddControl(controlQubit uint32) error {
	g.ControlQubits = append(g.ControlQubits, controlQubit)
	g.ControlCount = uint16(len(g.ControlQubits))
	return nil
}

// NewWireDeclaration creates a wire declaration.
func NewWireDeclaration(wireID uint32, wireType uint16, bitWidth uint16, name string, isInput, isOutput bool) *WireDeclaration {
	nameHash := sha256.Sum256([]byte(name))
	return &WireDeclaration{
		WireID:   wireID,
		Type:     wireType,
		BitWidth: bitWidth,
		NameLen:  uint16(len(name)),
		NameHash: nameHash,
		IsInput:  isInput,
		IsOutput: isOutput,
	}
}

// NewQubit creates a qubit wire declaration.
func NewQubit(wireID uint32, index uint32) *WireDeclaration {
	name := fmt.Sprintf("q%d", index)
	return NewWireDeclaration(wireID, WireTypeQubit, 1, name, false, false)
}

// NewClassicalBit creates a classical bit wire declaration.
func NewClassicalBit(wireID uint32, index uint32) *WireDeclaration {
	name := fmt.Sprintf("c%d", index)
	return NewWireDeclaration(wireID, WireTypeClassical, 1, name, false, false)
}

// NewJCLInstruction creates a JCL instruction.
func NewJCLInstruction(instructionID uint32, opCode uint16) *JCLInstruction {
	return &JCLInstruction{
		InstructionID: instructionID,
		OpCode:        opCode,
		ArgumentCount: 0,
		Arguments:     []uint32{},
		ControlFlags:  0,
	}
}

// AddArgument adds an argument to JCL instruction.
func (j *JCLInstruction) AddArgument(argID uint32) error {
	j.Arguments = append(j.Arguments, argID)
	j.ArgumentCount = uint16(len(j.Arguments))
	return nil
}

// NewJCLManifest creates a new JCL manifest.
func NewJCLManifest(manifestID, jobID, circuitID uint32) *JCLManifest {
	return &JCLManifest{
		ManifestID:       manifestID,
		JobID:            jobID,
		CircuitID:        circuitID,
		InstructionCount: 0,
		Instructions:     []JCLInstruction{},
		Priority:         5,
		MaxRetries:       3,
		TimeoutMS:        30000,
	}
}

// AddInstruction adds an instruction to JCL manifest.
func (m *JCLManifest) AddInstruction(instr JCLInstruction) error {
	m.Instructions = append(m.Instructions, instr)
	m.InstructionCount = uint32(len(m.Instructions))
	return nil
}

// ============================================================
// BINARY MARSHALING (encoding/binary.Read/Write)
// ============================================================

// MarshalBinary encodes QuipperGate to big-endian bytes.
func (g *QuipperGate) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, g.GateID); err != nil {
		return nil, fmt.Errorf("marshal gate_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, g.Type); err != nil {
		return nil, fmt.Errorf("marshal type: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, g.ControlCount); err != nil {
		return nil, fmt.Errorf("marshal control_count: %w", err)
	}
	for _, cq := range g.ControlQubits {
		if err := binary.Write(buf, binary.BigEndian, cq); err != nil {
			return nil, fmt.Errorf("marshal control_qubit: %w", err)
		}
	}
	if err := binary.Write(buf, binary.BigEndian, g.TargetCount); err != nil {
		return nil, fmt.Errorf("marshal target_count: %w", err)
	}
	for _, tq := range g.TargetQubits {
		if err := binary.Write(buf, binary.BigEndian, tq); err != nil {
			return nil, fmt.Errorf("marshal target_qubit: %w", err)
		}
	}
	if err := binary.Write(buf, binary.BigEndian, g.HasParameter); err != nil {
		return nil, fmt.Errorf("marshal has_parameter: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, g.Parameter); err != nil {
		return nil, fmt.Errorf("marshal parameter: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes QuipperGate from big-endian bytes.
func (g *QuipperGate) UnmarshalBinary(data []byte) error {
	if len(data) < 4+2+2+2+1+8 {
		return fmt.Errorf("gate too short")
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &g.GateID); err != nil {
		return fmt.Errorf("unmarshal gate_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &g.Type); err != nil {
		return fmt.Errorf("unmarshal type: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &g.ControlCount); err != nil {
		return fmt.Errorf("unmarshal control_count: %w", err)
	}
	g.ControlQubits = make([]uint32, g.ControlCount)
	for i := 0; i < int(g.ControlCount); i++ {
		if err := binary.Read(buf, binary.BigEndian, &g.ControlQubits[i]); err != nil {
			return fmt.Errorf("unmarshal control_qubit[%d]: %w", i, err)
		}
	}
	if err := binary.Read(buf, binary.BigEndian, &g.TargetCount); err != nil {
		return fmt.Errorf("unmarshal target_count: %w", err)
	}
	g.TargetQubits = make([]uint32, g.TargetCount)
	for i := 0; i < int(g.TargetCount); i++ {
		if err := binary.Read(buf, binary.BigEndian, &g.TargetQubits[i]); err != nil {
			return fmt.Errorf("unmarshal target_qubit[%d]: %w", i, err)
		}
	}
	if err := binary.Read(buf, binary.BigEndian, &g.HasParameter); err != nil {
		return fmt.Errorf("unmarshal has_parameter: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &g.Parameter); err != nil {
		return fmt.Errorf("unmarshal parameter: %w", err)
	}
	return nil
}

// MarshalBinary encodes WireDeclaration to big-endian bytes.
func (w *WireDeclaration) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	fields := []interface{}{
		w.WireID, w.Type, w.BitWidth, w.NameLen,
		w.NameHash[:], w.IsInput, w.IsOutput,
	}
	for _, f := range fields {
		if err := binary.Write(buf, binary.BigEndian, f); err != nil {
			return nil, fmt.Errorf("marshal wire field: %w", err)
		}
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes WireDeclaration from big-endian bytes.
func (w *WireDeclaration) UnmarshalBinary(data []byte) error {
	if len(data) < 4+2+2+2+32+1+1 {
		return fmt.Errorf("wire too short: %d < 44", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &w.WireID); err != nil {
		return fmt.Errorf("unmarshal wire_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &w.Type); err != nil {
		return fmt.Errorf("unmarshal type: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &w.BitWidth); err != nil {
		return fmt.Errorf("unmarshal bit_width: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &w.NameLen); err != nil {
		return fmt.Errorf("unmarshal name_len: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &w.NameHash); err != nil {
		return fmt.Errorf("unmarshal name_hash: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &w.IsInput); err != nil {
		return fmt.Errorf("unmarshal is_input: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &w.IsOutput); err != nil {
		return fmt.Errorf("unmarshal is_output: %w", err)
	}
	return nil
}

// MarshalBinary encodes QuipperCircuit to big-endian bytes.
func (c *QuipperCircuit) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	fields := []interface{}{
		c.CircuitID, c.GateCount, c.WireCount, c.Depth,
		c.QubitCount, c.ClassicalBitCount,
	}
	for _, f := range fields {
		if err := binary.Write(buf, binary.BigEndian, f); err != nil {
			return nil, fmt.Errorf("marshal circuit field: %w", err)
		}
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes QuipperCircuit from big-endian bytes.
func (c *QuipperCircuit) UnmarshalBinary(data []byte) error {
	if len(data) < 4+4+4+4+4+4 {
		return fmt.Errorf("circuit too short: %d < 24", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &c.CircuitID); err != nil {
		return fmt.Errorf("unmarshal circuit_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &c.GateCount); err != nil {
		return fmt.Errorf("unmarshal gate_count: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &c.WireCount); err != nil {
		return fmt.Errorf("unmarshal wire_count: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &c.Depth); err != nil {
		return fmt.Errorf("unmarshal depth: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &c.QubitCount); err != nil {
		return fmt.Errorf("unmarshal qubit_count: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &c.ClassicalBitCount); err != nil {
		return fmt.Errorf("unmarshal classical_bit_count: %w", err)
	}
	return nil
}

// MarshalBinary encodes JCLInstruction to big-endian bytes.
func (j *JCLInstruction) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, j.InstructionID); err != nil {
		return nil, fmt.Errorf("marshal instruction_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, j.OpCode); err != nil {
		return nil, fmt.Errorf("marshal opcode: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, j.ArgumentCount); err != nil {
		return nil, fmt.Errorf("marshal argument_count: %w", err)
	}
	for _, arg := range j.Arguments {
		if err := binary.Write(buf, binary.BigEndian, arg); err != nil {
			return nil, fmt.Errorf("marshal argument: %w", err)
		}
	}
	if err := binary.Write(buf, binary.BigEndian, j.ControlFlags); err != nil {
		return nil, fmt.Errorf("marshal control_flags: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes JCLInstruction from big-endian bytes.
func (j *JCLInstruction) UnmarshalBinary(data []byte) error {
	if len(data) < 4+2+2+4 {
		return fmt.Errorf("instruction too short: %d < 12", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &j.InstructionID); err != nil {
		return fmt.Errorf("unmarshal instruction_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &j.OpCode); err != nil {
		return fmt.Errorf("unmarshal opcode: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &j.ArgumentCount); err != nil {
		return fmt.Errorf("unmarshal argument_count: %w", err)
	}
	j.Arguments = make([]uint32, j.ArgumentCount)
	for i := 0; i < int(j.ArgumentCount); i++ {
		if err := binary.Read(buf, binary.BigEndian, &j.Arguments[i]); err != nil {
			return fmt.Errorf("unmarshal argument[%d]: %w", i, err)
		}
	}
	if err := binary.Read(buf, binary.BigEndian, &j.ControlFlags); err != nil {
		return fmt.Errorf("unmarshal control_flags: %w", err)
	}
	return nil
}

// MarshalBinary encodes JCLManifest to big-endian bytes.
func (m *JCLManifest) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	fields := []interface{}{
		m.ManifestID, m.JobID, m.CircuitID, m.InstructionCount,
		m.Priority, m.Deadline, m.RetryPolicy, m.MaxRetries,
		m.TimeoutMS, m.ResourceRequest,
	}
	for _, f := range fields {
		if err := binary.Write(buf, binary.BigEndian, f); err != nil {
			return nil, fmt.Errorf("marshal manifest field: %w", err)
		}
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes JCLManifest from big-endian bytes.
func (m *JCLManifest) UnmarshalBinary(data []byte) error {
	if len(data) < 4+4+4+4+2+8+2+2+4+4 {
		return fmt.Errorf("manifest too short")
	}
	buf := bytes.NewReader(data)
	fields := []interface{}{
		&m.ManifestID, &m.JobID, &m.CircuitID, &m.InstructionCount,
		&m.Priority, &m.Deadline, &m.RetryPolicy, &m.MaxRetries,
		&m.TimeoutMS, &m.ResourceRequest,
	}
	for _, f := range fields {
		if err := binary.Read(buf, binary.BigEndian, f); err != nil {
			return fmt.Errorf("unmarshal manifest field: %w", err)
		}
	}
	return nil
}

// MarshalBinary encodes CircuitExecutionTrace to big-endian bytes.
func (t *CircuitExecutionTrace) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, t.TraceID); err != nil {
		return nil, fmt.Errorf("marshal trace_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.CircuitID); err != nil {
		return nil, fmt.Errorf("marshal circuit_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.ExecutionTimeNS); err != nil {
		return nil, fmt.Errorf("marshal execution_time: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.SuccessCount); err != nil {
		return nil, fmt.Errorf("marshal success_count: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.TotalShots); err != nil {
		return nil, fmt.Errorf("marshal total_shots: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.FidelityEstimate); err != nil {
		return nil, fmt.Errorf("marshal fidelity: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, t.MeasurementCount); err != nil {
		return nil, fmt.Errorf("marshal measurement_count: %w", err)
	}
	for _, m := range t.Measurements {
		if err := binary.Write(buf, binary.BigEndian, m); err != nil {
			return nil, fmt.Errorf("marshal measurement: %w", err)
		}
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes CircuitExecutionTrace from big-endian bytes.
func (t *CircuitExecutionTrace) UnmarshalBinary(data []byte) error {
	if len(data) < 4+4+8+4+4+8+4 {
		return fmt.Errorf("trace too short")
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &t.TraceID); err != nil {
		return fmt.Errorf("unmarshal trace_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.CircuitID); err != nil {
		return fmt.Errorf("unmarshal circuit_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.ExecutionTimeNS); err != nil {
		return fmt.Errorf("unmarshal execution_time: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.SuccessCount); err != nil {
		return fmt.Errorf("unmarshal success_count: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.TotalShots); err != nil {
		return fmt.Errorf("unmarshal total_shots: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.FidelityEstimate); err != nil {
		return fmt.Errorf("unmarshal fidelity: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.MeasurementCount); err != nil {
		return fmt.Errorf("unmarshal measurement_count: %w", err)
	}
	t.Measurements = make([]uint64, t.MeasurementCount)
	for i := 0; i < int(t.MeasurementCount); i++ {
		if err := binary.Read(buf, binary.BigEndian, &t.Measurements[i]); err != nil {
			return fmt.Errorf("unmarshal measurement[%d]: %w", i, err)
		}
	}
	return nil
}

// ============================================================
// VALIDATION & AST CONSTRAINTS
// ============================================================

// Validate checks QuipperGate for AST constraints.
func (g *QuipperGate) Validate() error {
	if g.GateID == 0 {
		return fmt.Errorf("gate ID cannot be 0")
	}
	if g.Type > GateTypeQFTInverse {
		return fmt.Errorf("invalid gate type: %d", g.Type)
	}
	if g.TargetCount == 0 {
		return fmt.Errorf("gate must have at least one target qubit")
	}
	if g.HasParameter && (g.Type < GateTypeRx || g.Type > GateTypeRz) {
		// Only parameterized gates allowed
		if g.Type != GateTypeControlledRz && g.Type != GateTypeControlledU {
			// Except for controlled variants
			return fmt.Errorf("gate type %d does not accept parameters", g.Type)
		}
	}
	return nil
}

// Validate checks WireDeclaration for AST constraints.
func (w *WireDeclaration) Validate() error {
	if w.WireID == 0 {
		return fmt.Errorf("wire ID cannot be 0")
	}
	if w.Type > WireTypeMixed {
		return fmt.Errorf("invalid wire type: %d", w.Type)
	}
	if w.BitWidth == 0 {
		return fmt.Errorf("bit width must be > 0")
	}
	if w.Type == WireTypeQubit && w.BitWidth != 1 {
		return fmt.Errorf("qubit wire must have bit width 1")
	}
	return nil
}

// Validate checks QuipperCircuit for AST constraints.
func (c *QuipperCircuit) Validate() error {
	if c.CircuitID == 0 {
		return fmt.Errorf("circuit ID cannot be 0")
	}
	if c.QubitCount == 0 {
		return fmt.Errorf("circuit must have at least one qubit")
	}
	if c.Depth == 0 && c.GateCount > 0 {
		return fmt.Errorf("circuit depth cannot be 0 if gates present")
	}
	return nil
}

// Validate checks JCLInstruction for AST constraints.
func (j *JCLInstruction) Validate() error {
	if j.InstructionID == 0 {
		return fmt.Errorf("instruction ID cannot be 0")
	}
	if j.OpCode > JCLOpcodeLoop {
		return fmt.Errorf("invalid opcode: %d", j.OpCode)
	}
	return nil
}

// Validate checks JCLManifest for AST constraints.
func (m *JCLManifest) Validate() error {
	if m.ManifestID == 0 {
		return fmt.Errorf("manifest ID cannot be 0")
	}
	if m.JobID == 0 {
		return fmt.Errorf("job ID cannot be 0")
	}
	if m.CircuitID == 0 {
		return fmt.Errorf("circuit ID cannot be 0")
	}
	if m.MaxRetries > 100 {
		return fmt.Errorf("max retries cannot exceed 100")
	}
	return nil
}

// Validate checks CircuitExecutionTrace for AST constraints.
func (t *CircuitExecutionTrace) Validate() error {
	if t.TraceID == 0 {
		return fmt.Errorf("trace ID cannot be 0")
	}
	if t.CircuitID == 0 {
		return fmt.Errorf("circuit ID cannot be 0")
	}
	if t.TotalShots == 0 {
		return fmt.Errorf("total shots must be > 0")
	}
	if t.SuccessCount > t.TotalShots {
		return fmt.Errorf("success count cannot exceed total shots")
	}
	return nil
}

// ============================================================
// HASH COMPUTATION
// ============================================================

// ComputeCircuitHash computes hash of quantum circuit.
func ComputeCircuitHash(circuit *QuipperCircuit) ([32]byte, uint32, uint64) {
	buf := new(bytes.Buffer)
	binary.Write(buf, binary.BigEndian, circuit.CircuitID)
	binary.Write(buf, binary.BigEndian, circuit.GateCount)
	binary.Write(buf, binary.BigEndian, circuit.QubitCount)
	binary.Write(buf, binary.BigEndian, circuit.Depth)

	data := buf.Bytes()
	sha := sha256.Sum256(data)
	crc := crc32.ChecksumIEEE(data)
	fnv := fnv.New64a()
	fnv.Write(data)

	return sha, crc, fnv.Sum64()
}

// ComputeManifestHash computes hash of JCL manifest.
func ComputeManifestHash(manifest *JCLManifest) ([32]byte, uint32, uint64) {
	buf := new(bytes.Buffer)
	binary.Write(buf, binary.BigEndian, manifest.ManifestID)
	binary.Write(buf, binary.BigEndian, manifest.JobID)
	binary.Write(buf, binary.BigEndian, manifest.CircuitID)
	binary.Write(buf, binary.BigEndian, manifest.InstructionCount)

	data := buf.Bytes()
	sha := sha256.Sum256(data)
	crc := crc32.ChecksumIEEE(data)
	fnv := fnv.New64a()
	fnv.Write(data)

	return sha, crc, fnv.Sum64()
}

// ComputeTraceHash computes hash of execution trace.
func ComputeTraceHash(trace *CircuitExecutionTrace) ([32]byte, uint32, uint64) {
	buf := new(bytes.Buffer)
	binary.Write(buf, binary.BigEndian, trace.TraceID)
	binary.Write(buf, binary.BigEndian, trace.CircuitID)
	binary.Write(buf, binary.BigEndian, trace.TotalShots)
	binary.Write(buf, binary.BigEndian, trace.SuccessCount)

	data := buf.Bytes()
	sha := sha256.Sum256(data)
	crc := crc32.ChecksumIEEE(data)
	fnv := fnv.New64a()
	fnv.Write(data)

	return sha, crc, fnv.Sum64()
}
