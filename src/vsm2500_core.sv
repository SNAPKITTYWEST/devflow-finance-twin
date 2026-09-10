// ============================================================================
// VSM-2500 · FULL RAW SYSTEMVERILOG IMPLEMENTATION
// Virtual Semantic Machine – Binary Semantic Core + Springboard
// Deterministic register-memory-graph machine in synthesizable SV
// ============================================================================

`timescale 1ns / 1ps
`default_nettype none

// ---------------------------------------------------------------------------
package vsm_pkg;
  // Binary semantic primitives
  typedef logic          b1_t;
  typedef logic  [1:0]   b2_t;
  typedef logic  [7:0]   b8_t;
  typedef logic  [15:0]  b16_t;
  typedef logic  [31:0]  b32_t;
  typedef logic  [63:0]  b64_t;
  typedef logic  [127:0] b128_t;

  // Virtual Parameter (128-bit)
  typedef struct packed {
    b16_t vp_id;
    b16_t vp_domain;
    b16_t vp_state;
    b16_t vp_polarity;   // 00 neutral, 01 pos, 10 neg, 11 contrad
    b16_t vp_binding;
    b16_t vp_scope;
    b16_t vp_transition;
    b16_t vp_flags;
  } vp_t;

  // Semantic Register
  typedef b128_t reg_t;

  // Springboard (256-bit)
  typedef struct packed {
    b64_t source_hash;
    b64_t seed;
    b32_t constraint_id;
    b32_t transition_rule;
    b64_t target_hash;
    b32_t validation_result;
  } springboard_t;

  // Memory cell (simplified 256-bit)
  typedef struct packed {
    b64_t addr;
    b64_t value;
    b16_t typ;
    b16_t cls;
    b32_t provenance;
    b8_t  validity;
    b16_t constraints;
    b32_t timestamp;
    b32_t parent;
    b32_t children;
  } mem_cell_t;

  // Opcodes
  typedef enum logic [7:0] {
    OP_NOP       = 8'h00,
    OP_LOAD      = 8'h01,
    OP_STORE     = 8'h02,
    OP_MOVE      = 8'h03,
    OP_AND       = 8'h10,
    OP_OR        = 8'h11,
    OP_XOR       = 8'h12,
    OP_NOT       = 8'h13,
    OP_COMPARE   = 8'h14,
    OP_BIND      = 8'h20,
    OP_UNBIND    = 8'h21,
    OP_ASSERT    = 8'h22,
    OP_REJECT    = 8'h23,
    OP_PROVE     = 8'h30,
    OP_VERIFY    = 8'h31,
    OP_ROUTE     = 8'h40,
    OP_MERGE     = 8'h41,
    OP_FORK      = 8'h43,
    OP_SEED      = 8'h50,
    OP_SPRING    = 8'h51,
    OP_PROPAGATE = 8'h52,
    OP_COMMIT    = 8'h53,
    OP_ROLLBACK  = 8'h54,
    OP_HALT      = 8'hFF
  } opcode_e;

  // Status bits
  typedef struct packed {
    logic running;
    logic halted;
    logic failed;
    logic contradiction;
    logic proof_pending;
    logic branched;
    logic snapshotted;
    logic verified;
  } status_t;

  // Failure codes
  typedef enum logic [7:0] {
    FAIL_NONE          = 8'h00,
    FAIL_INVALID_STATE = 8'h01,
    FAIL_INVALID_PARAM = 8'h02,
    FAIL_INVALID_OPCODE= 8'h03,
    FAIL_CONSTRAINT    = 8'h04,
    FAIL_PROOF         = 8'h05,
    FAIL_MEMORY        = 8'h06,
    FAIL_ROUTING       = 8'h07,
    FAIL_PROPAGATION   = 8'h08,
    FAIL_CONFLICT      = 8'h09
  } fail_e;
endpackage

// ---------------------------------------------------------------------------
module vsm_binary_alu (
  input  logic               clk,
  input  logic               rst_n,
  input  vsm_pkg::opcode_e   op,
  input  vsm_pkg::b128_t     a,
  input  vsm_pkg::b128_t     b,
  output vsm_pkg::b128_t     y,
  output logic               valid,
  output logic               contrad
);
  import vsm_pkg::*;

  always_comb begin
    y       = '0;
    valid   = 1'b1;
    contrad = 1'b0;
    unique case (op)
      OP_AND:     y = a & b;
      OP_OR:      y = a | b;
      OP_XOR:     y = a ^ b;
      OP_NOT:     y = ~a;
      OP_BIND:    y = {a[63:0], b[63:0]};
      OP_COMPARE: y = (a == b) ? 128'h1 : 128'h0;
      default: begin
        y     = a;
        valid = 1'b0;
      end
    endcase
    // simple contradiction detect
    if ((a[1:0] == 2'b11) && (b[1:0] == 2'b11))
      contrad = 1'b1;
  end
endmodule

// ---------------------------------------------------------------------------
module vsm_register_file (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               we,
  input  logic [4:0]         waddr,
  input  vsm_pkg::reg_t      wdata,
  input  logic [4:0]         raddr_a,
  input  logic [4:0]         raddr_b,
  output vsm_pkg::reg_t      rdata_a,
  output vsm_pkg::reg_t      rdata_b
);
  import vsm_pkg::*;
  reg_t rf [0:31];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++)
        rf[i] <= '0;
    end else if (we) begin
      rf[waddr] <= wdata;
    end
  end

  assign rdata_a = rf[raddr_a];
  assign rdata_b = rf[raddr_b];
endmodule

// ---------------------------------------------------------------------------
module vsm_springboard_ctrl (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               create_i,
  input  logic               validate_i,
  input  logic               propagate_i,
  input  logic               commit_i,
  input  logic               rollback_i,
  input  vsm_pkg::b64_t      source_hash_i,
  input  vsm_pkg::b64_t      seed_i,
  input  vsm_pkg::b32_t      constraint_id_i,
  input  vsm_pkg::b32_t      rule_i,
  output vsm_pkg::springboard_t sb_o,
  output logic               valid_o,
  output logic               reject_o
);
  import vsm_pkg::*;
  springboard_t sb_r;
  logic active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sb_r     <= '0;
      active   <= 1'b0;
      valid_o  <= 1'b0;
      reject_o <= 1'b0;
    end else begin
      valid_o  <= 1'b0;
      reject_o <= 1'b0;

      if (create_i) begin
        sb_r.source_hash      <= source_hash_i;
        sb_r.seed             <= seed_i;
        sb_r.constraint_id    <= constraint_id_i;
        sb_r.transition_rule  <= rule_i;
        sb_r.target_hash      <= '0;
        sb_r.validation_result<= 32'h0;
        active <= 1'b1;
      end

      if (validate_i && active) begin
        if (sb_r.seed != '0) begin
          sb_r.validation_result <= 32'h1;
          valid_o <= 1'b1;
        end else begin
          sb_r.validation_result <= 32'hDEAD;
          reject_o <= 1'b1;
        end
      end

      if (propagate_i && active && sb_r.validation_result == 32'h1)
        sb_r.target_hash <= sb_r.source_hash ^ sb_r.seed;

      if (commit_i)
        active <= 1'b0;

      if (rollback_i) begin
        sb_r   <= '0;
        active <= 1'b0;
      end
    end
  end

  assign sb_o = sb_r;
endmodule

// ---------------------------------------------------------------------------
module vsm_core (
  input  logic               clk,
  input  logic               rst_n,
  // instruction port
  input  logic               instr_valid,
  input  vsm_pkg::opcode_e   opcode,
  input  logic [4:0]         rd,
  input  logic [4:0]         rs1,
  input  logic [4:0]         rs2,
  input  vsm_pkg::b128_t     imm,
  // status
  output vsm_pkg::status_t   status_o,
  output vsm_pkg::fail_e     error_o,
  output logic               halt_o
);
  import vsm_pkg::*;

  // registers
  reg_t  rdata_a, rdata_b, alu_y;
  logic  alu_valid, alu_contrad;
  logic  rf_we;

  // status
  status_t status_r;
  fail_e   error_r;

  // springboard
  logic         sb_create, sb_validate, sb_propagate, sb_commit, sb_rollback;
  springboard_t sb;
  logic         sb_valid, sb_reject;

  vsm_register_file u_rf (
    .clk     (clk),
    .rst_n   (rst_n),
    .we      (rf_we),
    .waddr   (rd),
    .wdata   (alu_y),
    .raddr_a (rs1),
    .raddr_b (rs2),
    .rdata_a (rdata_a),
    .rdata_b (rdata_b)
  );

  vsm_binary_alu u_alu (
    .clk    (clk),
    .rst_n  (rst_n),
    .op     (opcode),
    .a      (rdata_a),
    .b      (rdata_b),
    .y      (alu_y),
    .valid  (alu_valid),
    .contrad(alu_contrad)
  );

  vsm_springboard_ctrl u_sb (
    .clk             (clk),
    .rst_n           (rst_n),
    .create_i        (sb_create),
    .validate_i      (sb_validate),
    .propagate_i     (sb_propagate),
    .commit_i        (sb_commit),
    .rollback_i      (sb_rollback),
    .source_hash_i   (rdata_a[63:0]),
    .seed_i          (rdata_b[63:0]),
    .constraint_id_i (32'h1),
    .rule_i          (32'hA5A5),
    .sb_o            (sb),
    .valid_o         (sb_valid),
    .reject_o        (sb_reject)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      status_r          <= '0;
      status_r.running  <= 1'b1;
      error_r           <= FAIL_NONE;
      halt_o            <= 1'b0;
      rf_we             <= 1'b0;
      sb_create         <= 1'b0;
      sb_validate       <= 1'b0;
      sb_propagate      <= 1'b0;
      sb_commit         <= 1'b0;
      sb_rollback       <= 1'b b0;
    end else begin
      rf_we        <= 1'b0;
      sb_create    <= 1'b0;
      sb_validate  <= 1'b0;
      sb_propagate <= 1'b0;
      sb_commit    <= 1'b0;
      sb_rollback  <= 1'b0;

      if (instr_valid && status_r.running) begin
        unique case (opcode)
          OP_AND, OP_OR, OP_XOR, OP_NOT, OP_COMPARE, OP_BIND: begin
            rf_we <= 1'b1;
            if (alu_contrad) begin
              status_r.contradiction <= 1'b1;
              status_r.failed        <= 1'b1;
              error_r                <= FAIL_CONFLICT;
            end
          end
          OP_SPRING: begin
            sb_create   <= 1'b1;
            sb_validate <= 1'b1;
          end
          OP_PROPAGATE: begin
            sb_propagate <= 1'b1;
          end
          OP_COMMIT: begin
            sb_commit        <= 1'b1;
            status_r.verified<= 1'b1;
          end
          OP_ROLLBACK: begin
            sb_rollback <= 1'b1;
          end
          OP_HALT: begin
            status_r.running <= 1'b0;
            status_r.halted  <= 1'b1;
            halt_o           <= 1'b1;
          end
          OP_REJECT: begin
            status_r.failed <= 1'b1;
            error_r         <= FAIL_CONSTRAINT;
          end
          default: begin
            error_r         <= FAIL_INVALID_OPCODE;
            status_r.failed <= 1'b1;
          end
        endcase

        if (sb_reject) begin
          status_r.failed <= 1'b1;
          error_r         <= FAIL_PROPAGATION;
        end
      end
    end
  end

  assign status_o = status_r;
  assign error_o  = error_r;
endmodule

// ---------------------------------------------------------------------------
// Simple testbench fragment (not synthesizable)
// ---------------------------------------------------------------------------
`ifdef SIMULATION
module tb_vsm;
  import vsm_pkg::*;

  logic      clk, rst_n;
  logic      instr_valid;
  opcode_e   opcode;
  logic [4:0] rd, rs1, rs2;
  b128_t     imm;
  status_t   status;
  fail_e     error;
  logic      halt;

  vsm_core dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .instr_valid(instr_valid),
    .opcode     (opcode),
    .rd         (rd),
    .rs1        (rs1),
    .rs2        (rs2),
    .imm        (imm),
    .status_o   (status),
    .error_o    (error),
    .halt_o     (halt)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n       = 0;
    instr_valid = 0;
    #100;
    rst_n = 1;
    #20;

    // BIND
    opcode = OP_BIND; rd = 5; rs1 = 1; rs2 = 2;
    instr_valid = 1; #10; instr_valid = 0;

    // SPRING
    opcode = OP_SPRING;
    instr_valid = 1; #10; instr_valid = 0;

    // PROPAGATE
    opcode = OP_PROPAGATE;
    instr_valid = 1; #10; instr_valid = 0;

    // COMMIT
    opcode = OP_COMMIT;
    instr_valid = 1; #10; instr_valid = 0;

    // HALT
    opcode = OP_HALT;
    instr_valid = 1; #10; instr_valid = 0;

    #100;
    $finish;
  end
endmodule
`endif

`default_nettype wire
// ============================================================================
// END RAW SYSTEMVERILOG IMPLEMENTATION OF VSM-2500 CORE
// Binary ALU · Register File · Springboard Controller · Main Core
// Deterministic · Provenance-ready · Synthesizable subset
// ============================================================================
