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
// TURING CFG & PTM
// Context-Free Grammars, Push-down Transition Machines, State Machines
// ============================================================

const (
	// Magic header for Turing CFG/PTM binary format
	MagicHeaderCFGPTM uint32 = 0x4346475F // "CFG_"
	VersionCFGPTM     uint16 = 0x0001
)

// CFGSymbolType enumerations
const (
	SymbolTypeTerminal uint16 = iota
	SymbolTypeNonTerminal
	SymbolTypeEpsilon
)

// CFGSymbol represents a grammar symbol (terminal or non-terminal).
type CFGSymbol struct {
	Type      uint16    `binary:"type,big-endian"`      // SymbolType
	ID        uint32    `binary:"id,big-endian"`        // Unique symbol ID
	NameLen   uint16    `binary:"name_len,big-endian"`  // Length of name
	NameHash  [32]byte  `binary:"name_hash,big-endian"` // SHA-256 of symbol name
}

// CFGProduction represents a grammar rule: LHS -> RHS.
type CFGProduction struct {
	LHS          uint32   `binary:"lhs,big-endian"`           // Non-terminal ID on left
	RHSLength    uint16   `binary:"rhs_length,big-endian"`    // Number of symbols on right
	RHSSymbols   []uint32 `binary:"rhs_symbols,rest"`         // Symbol IDs in production
	ProductionID uint32   `binary:"production_id,big-endian"` // Unique production ID
}

// CFGGrammar represents a complete context-free grammar.
type CFGGrammar struct {
	StartSymbol   uint32          `binary:"start_symbol,big-endian"`
	SymbolCount   uint32          `binary:"symbol_count,big-endian"`
	Symbols       []CFGSymbol     `binary:"symbols,rest"`
	ProductionCount uint32        `binary:"production_count,big-endian"`
	Productions   []CFGProduction `binary:"productions,rest"`
}

// PTMState represents a push-down automaton state.
type PTMState struct {
	StateID     uint32   `binary:"state_id,big-endian"`    // Unique state identifier
	IsAccepting bool     `binary:"is_accepting,byte"`      // Whether this is accepting state
	StackOp     uint16   `binary:"stack_op,big-endian"`    // Stack operation (push/pop/none)
	StackSymbol uint32   `binary:"stack_symbol,big-endian"` // Symbol to push/pop
}

// PTMTransitionType enumerations
const (
	TransitionTypeRead uint16 = iota
	TransitionTypeEpsilon
	TransitionTypePop
	TransitionTypePush
)

// PTMTransition represents a state transition in push-down machine.
type PTMTransition struct {
	FromState    uint32   `binary:"from_state,big-endian"`
	ToState      uint32   `binary:"to_state,big-endian"`
	InputSymbol  uint32   `binary:"input_symbol,big-endian"`
	StackTop     uint32   `binary:"stack_top,big-endian"`    // Symbol expected at stack top
	StackPush    uint32   `binary:"stack_push,big-endian"`   // Symbol to push (or 0 for none)
	TransitionID uint32   `binary:"transition_id,big-endian"`
}

// PTMMachine represents a complete push-down state machine.
type PTMMachine struct {
	StateCount       uint32           `binary:"state_count,big-endian"`
	States           []PTMState       `binary:"states,rest"`
	InitialState     uint32           `binary:"initial_state,big-endian"`
	TransitionCount  uint32           `binary:"transition_count,big-endian"`
	Transitions      []PTMTransition  `binary:"transitions,rest"`
	StackAlphabet    []uint32         `binary:"stack_alphabet,rest"`
	InputAlphabet    []uint32         `binary:"input_alphabet,rest"`
}

// ParseTreeNode represents a node in a concrete parse tree.
type ParseTreeNode struct {
	NodeID       uint32   `binary:"node_id,big-endian"`
	SymbolID     uint32   `binary:"symbol_id,big-endian"`
	IsLeaf       bool     `binary:"is_leaf,byte"`
	ChildCount   uint16   `binary:"child_count,big-endian"`
	Children     []uint32 `binary:"children,rest"`
	TokenOffset  uint32   `binary:"token_offset,big-endian"` // For leaf nodes
	TokenLength  uint16   `binary:"token_length,big-endian"` // For leaf nodes
}

// ParseTree represents a complete parse tree with all nodes.
type ParseTree struct {
	NodeCount  uint32          `binary:"node_count,big-endian"`
	Nodes      []ParseTreeNode `binary:"nodes,rest"`
	RootNodeID uint32          `binary:"root_node_id,big-endian"`
}

// ============================================================
// BUILDERS & CONSTRUCTORS
// ============================================================

// NewCFGSymbol creates a new CFG symbol with validation.
func NewCFGSymbol(symType uint16, id uint32, name string) *CFGSymbol {
	nameHash := sha256.Sum256([]byte(name))
	return &CFGSymbol{
		Type:     symType,
		ID:       id,
		NameLen:  uint16(len(name)),
		NameHash: nameHash,
	}
}

// NewCFGProduction creates a new production rule.
func NewCFGProduction(lhs uint32, rhs []uint32, prodID uint32) *CFGProduction {
	return &CFGProduction{
		LHS:          lhs,
		RHSLength:    uint16(len(rhs)),
		RHSSymbols:   rhs,
		ProductionID: prodID,
	}
}

// NewPTMState creates a new PTM state.
func NewPTMState(id uint32, accepting bool) *PTMState {
	return &PTMState{
		StateID:     id,
		IsAccepting: accepting,
		StackOp:     0, // No operation by default
		StackSymbol: 0,
	}
}

// NewPTMTransition creates a new PTM transition.
func NewPTMTransition(from, to, inSym, stackTop, stackPush, transID uint32) *PTMTransition {
	return &PTMTransition{
		FromState:    from,
		ToState:      to,
		InputSymbol:  inSym,
		StackTop:     stackTop,
		StackPush:    stackPush,
		TransitionID: transID,
	}
}

// NewParseTreeNode creates a new parse tree node.
func NewParseTreeNode(nodeID, symbolID uint32, isLeaf bool) *ParseTreeNode {
	return &ParseTreeNode{
		NodeID:      nodeID,
		SymbolID:    symbolID,
		IsLeaf:      isLeaf,
		ChildCount:  0,
		Children:    []uint32{},
		TokenOffset: 0,
		TokenLength: 0,
	}
}

// AddChild adds a child node to a parse tree node.
func (n *ParseTreeNode) AddChild(childID uint32) error {
	if n.IsLeaf {
		return fmt.Errorf("cannot add child to leaf node")
	}
	n.Children = append(n.Children, childID)
	n.ChildCount = uint16(len(n.Children))
	return nil
}

// ============================================================
// BINARY MARSHALING (encoding/binary.Read/Write)
// ============================================================

// MarshalBinary encodes CFGSymbol to big-endian bytes.
func (s *CFGSymbol) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, s.Type); err != nil {
		return nil, fmt.Errorf("marshal type: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, s.ID); err != nil {
		return nil, fmt.Errorf("marshal id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, s.NameLen); err != nil {
		return nil, fmt.Errorf("marshal name_len: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, s.NameHash[:]); err != nil {
		return nil, fmt.Errorf("marshal name_hash: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes CFGSymbol from big-endian bytes.
func (s *CFGSymbol) UnmarshalBinary(data []byte) error {
	if len(data) < 2+4+2+32 {
		return fmt.Errorf("symbol too short: %d < 40", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &s.Type); err != nil {
		return fmt.Errorf("unmarshal type: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &s.ID); err != nil {
		return fmt.Errorf("unmarshal id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &s.NameLen); err != nil {
		return fmt.Errorf("unmarshal name_len: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &s.NameHash); err != nil {
		return fmt.Errorf("unmarshal name_hash: %w", err)
	}
	return nil
}

// MarshalBinary encodes CFGProduction to big-endian bytes.
func (p *CFGProduction) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, p.LHS); err != nil {
		return nil, fmt.Errorf("marshal lhs: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, p.RHSLength); err != nil {
		return nil, fmt.Errorf("marshal rhs_length: %w", err)
	}
	for _, sym := range p.RHSSymbols {
		if err := binary.Write(buf, binary.BigEndian, sym); err != nil {
			return nil, fmt.Errorf("marshal rhs_symbol: %w", err)
		}
	}
	if err := binary.Write(buf, binary.BigEndian, p.ProductionID); err != nil {
		return nil, fmt.Errorf("marshal production_id: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes CFGProduction from big-endian bytes.
func (p *CFGProduction) UnmarshalBinary(data []byte) error {
	if len(data) < 4+2 {
		return fmt.Errorf("production too short: %d < 6", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &p.LHS); err != nil {
		return fmt.Errorf("unmarshal lhs: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &p.RHSLength); err != nil {
		return fmt.Errorf("unmarshal rhs_length: %w", err)
	}
	p.RHSSymbols = make([]uint32, p.RHSLength)
	for i := 0; i < int(p.RHSLength); i++ {
		if err := binary.Read(buf, binary.BigEndian, &p.RHSSymbols[i]); err != nil {
			return fmt.Errorf("unmarshal rhs_symbol[%d]: %w", i, err)
		}
	}
	if err := binary.Read(buf, binary.BigEndian, &p.ProductionID); err != nil {
		return fmt.Errorf("unmarshal production_id: %w", err)
	}
	return nil
}

// MarshalBinary encodes PTMState to big-endian bytes.
func (s *PTMState) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, s.StateID); err != nil {
		return nil, fmt.Errorf("marshal state_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, s.IsAccepting); err != nil {
		return nil, fmt.Errorf("marshal is_accepting: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, s.StackOp); err != nil {
		return nil, fmt.Errorf("marshal stack_op: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, s.StackSymbol); err != nil {
		return nil, fmt.Errorf("marshal stack_symbol: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes PTMState from big-endian bytes.
func (s *PTMState) UnmarshalBinary(data []byte) error {
	if len(data) < 4+1+2+4 {
		return fmt.Errorf("state too short: %d < 11", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &s.StateID); err != nil {
		return fmt.Errorf("unmarshal state_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &s.IsAccepting); err != nil {
		return fmt.Errorf("unmarshal is_accepting: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &s.StackOp); err != nil {
		return fmt.Errorf("unmarshal stack_op: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &s.StackSymbol); err != nil {
		return fmt.Errorf("unmarshal stack_symbol: %w", err)
	}
	return nil
}

// MarshalBinary encodes PTMTransition to big-endian bytes.
func (t *PTMTransition) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	fields := []interface{}{
		t.FromState, t.ToState, t.InputSymbol, t.StackTop, t.StackPush, t.TransitionID,
	}
	for _, f := range fields {
		if err := binary.Write(buf, binary.BigEndian, f); err != nil {
			return nil, fmt.Errorf("marshal transition field: %w", err)
		}
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes PTMTransition from big-endian bytes.
func (t *PTMTransition) UnmarshalBinary(data []byte) error {
	if len(data) < 6*4 {
		return fmt.Errorf("transition too short: %d < 24", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &t.FromState); err != nil {
		return fmt.Errorf("unmarshal from_state: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.ToState); err != nil {
		return fmt.Errorf("unmarshal to_state: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.InputSymbol); err != nil {
		return fmt.Errorf("unmarshal input_symbol: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.StackTop); err != nil {
		return fmt.Errorf("unmarshal stack_top: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.StackPush); err != nil {
		return fmt.Errorf("unmarshal stack_push: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &t.TransitionID); err != nil {
		return fmt.Errorf("unmarshal transition_id: %w", err)
	}
	return nil
}

// MarshalBinary encodes ParseTreeNode to big-endian bytes.
func (n *ParseTreeNode) MarshalBinary() ([]byte, error) {
	buf := new(bytes.Buffer)
	if err := binary.Write(buf, binary.BigEndian, n.NodeID); err != nil {
		return nil, fmt.Errorf("marshal node_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, n.SymbolID); err != nil {
		return nil, fmt.Errorf("marshal symbol_id: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, n.IsLeaf); err != nil {
		return nil, fmt.Errorf("marshal is_leaf: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, n.ChildCount); err != nil {
		return nil, fmt.Errorf("marshal child_count: %w", err)
	}
	for _, child := range n.Children {
		if err := binary.Write(buf, binary.BigEndian, child); err != nil {
			return nil, fmt.Errorf("marshal child: %w", err)
		}
	}
	if err := binary.Write(buf, binary.BigEndian, n.TokenOffset); err != nil {
		return nil, fmt.Errorf("marshal token_offset: %w", err)
	}
	if err := binary.Write(buf, binary.BigEndian, n.TokenLength); err != nil {
		return nil, fmt.Errorf("marshal token_length: %w", err)
	}
	return buf.Bytes(), nil
}

// UnmarshalBinary decodes ParseTreeNode from big-endian bytes.
func (n *ParseTreeNode) UnmarshalBinary(data []byte) error {
	if len(data) < 4+4+1+2 {
		return fmt.Errorf("node too short: %d < 11", len(data))
	}
	buf := bytes.NewReader(data)
	if err := binary.Read(buf, binary.BigEndian, &n.NodeID); err != nil {
		return fmt.Errorf("unmarshal node_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &n.SymbolID); err != nil {
		return fmt.Errorf("unmarshal symbol_id: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &n.IsLeaf); err != nil {
		return fmt.Errorf("unmarshal is_leaf: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &n.ChildCount); err != nil {
		return fmt.Errorf("unmarshal child_count: %w", err)
	}
	n.Children = make([]uint32, n.ChildCount)
	for i := 0; i < int(n.ChildCount); i++ {
		if err := binary.Read(buf, binary.BigEndian, &n.Children[i]); err != nil {
			return fmt.Errorf("unmarshal child[%d]: %w", i, err)
		}
	}
	if err := binary.Read(buf, binary.BigEndian, &n.TokenOffset); err != nil {
		return fmt.Errorf("unmarshal token_offset: %w", err)
	}
	if err := binary.Read(buf, binary.BigEndian, &n.TokenLength); err != nil {
		return fmt.Errorf("unmarshal token_length: %w", err)
	}
	return nil
}

// ============================================================
// VALIDATION & AST CONSTRAINTS
// ============================================================

// Validate checks CFGSymbol for AST constraints.
func (s *CFGSymbol) Validate() error {
	if s.Type > SymbolTypeEpsilon {
		return fmt.Errorf("invalid symbol type: %d", s.Type)
	}
	if s.NameLen == 0 {
		return fmt.Errorf("symbol name length must be > 0")
	}
	return nil
}

// Validate checks CFGProduction for AST constraints.
func (p *CFGProduction) Validate() error {
	if p.LHS == 0 {
		return fmt.Errorf("LHS (left-hand side) cannot be 0")
	}
	if len(p.RHSSymbols) != int(p.RHSLength) {
		return fmt.Errorf("RHS length mismatch: declared %d, have %d", p.RHSLength, len(p.RHSSymbols))
	}
	return nil
}

// Validate checks PTMState for AST constraints.
func (s *PTMState) Validate() error {
	if s.StateID == 0 {
		return fmt.Errorf("state ID cannot be 0")
	}
	return nil
}

// Validate checks PTMTransition for AST constraints.
func (t *PTMTransition) Validate() error {
	if t.FromState == 0 || t.ToState == 0 {
		return fmt.Errorf("from_state and to_state cannot be 0")
	}
	return nil
}

// Validate checks ParseTreeNode for AST constraints.
func (n *ParseTreeNode) Validate() error {
	if n.NodeID == 0 {
		return fmt.Errorf("node ID cannot be 0")
	}
	if !n.IsLeaf && n.ChildCount == 0 {
		return fmt.Errorf("non-leaf node must have children")
	}
	if n.IsLeaf && n.ChildCount > 0 {
		return fmt.Errorf("leaf node cannot have children")
	}
	return nil
}

// ============================================================
// HASH COMPUTATION
// ============================================================

// ComputeGrammarHash computes hash of CFG grammar.
func ComputeGrammarHash(grammar *CFGGrammar) ([32]byte, uint32, uint64) {
	// Serialize grammar
	buf := new(bytes.Buffer)
	binary.Write(buf, binary.BigEndian, grammar.StartSymbol)
	binary.Write(buf, binary.BigEndian, grammar.SymbolCount)
	binary.Write(buf, binary.BigEndian, grammar.ProductionCount)

	data := buf.Bytes()
	sha := sha256.Sum256(data)
	crc := crc32.ChecksumIEEE(data)
	fnv := fnv.New64a()
	fnv.Write(data)

	return sha, crc, fnv.Sum64()
}

// ComputePTMHash computes hash of PTM machine.
func ComputePTMHash(machine *PTMMachine) ([32]byte, uint32, uint64) {
	buf := new(bytes.Buffer)
	binary.Write(buf, binary.BigEndian, machine.StateCount)
	binary.Write(buf, binary.BigEndian, machine.InitialState)
	binary.Write(buf, binary.BigEndian, machine.TransitionCount)

	data := buf.Bytes()
	sha := sha256.Sum256(data)
	crc := crc32.ChecksumIEEE(data)
	fnv := fnv.New64a()
	fnv.Write(data)

	return sha, crc, fnv.Sum64()
}

// ComputeParseTreeHash computes hash of parse tree.
func ComputeParseTreeHash(tree *ParseTree) ([32]byte, uint32, uint64) {
	buf := new(bytes.Buffer)
	binary.Write(buf, binary.BigEndian, tree.NodeCount)
	binary.Write(buf, binary.BigEndian, tree.RootNodeID)

	data := buf.Bytes()
	sha := sha256.Sum256(data)
	crc := crc32.ChecksumIEEE(data)
	fnv := fnv.New64a()
	fnv.Write(data)

	return sha, crc, fnv.Sum64()
}
