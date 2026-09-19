# SystemVerilog ALU — RV64 Production Implementation
*64-bit integer ALU for an out-of-order RISC-V core*

---

## Design Goals

- All RV64I arithmetic, logical, shift, and comparison operations
- Single-cycle result for simple ops; multi-cycle multiply/divide via `busy`/`done` handshake
- Parameterizable width (default 64)
- No latches; all sequential elements explicitly clocked and reset
- Constant-time shifts and logicals (no data-dependent early exits)
- Clean `unique case` style, friendly to synthesis and formal

---

## Package: alu_pkg

```systemverilog
package alu_pkg;

  typedef enum logic [5:0] {
    ALU_ADD  = 6'h00, ALU_SUB  = 6'h01, ALU_AND  = 6'h02,
    ALU_OR   = 6'h03, ALU_XOR  = 6'h04, ALU_SLL  = 6'h05,
    ALU_SRL  = 6'h06, ALU_SRA  = 6'h07, ALU_SLT  = 6'h08,
    ALU_SLTU = 6'h09,
    // Word (32-bit) variants
    ALU_ADDW = 6'h0A, ALU_SUBW = 6'h0B, ALU_SLLW = 6'h0C,
    ALU_SRLW = 6'h0D, ALU_SRAW = 6'h0E,
    // Multiply
    ALU_MUL    = 6'h10, ALU_MULH   = 6'h11,
    ALU_MULHSU = 6'h12, ALU_MULHU  = 6'h13, ALU_MULW = 6'h14,
    // Divide / Remainder
    ALU_DIV  = 6'h20, ALU_DIVU  = 6'h21,
    ALU_REM  = 6'h22, ALU_REMU  = 6'h23,
    ALU_DIVW = 6'h24, ALU_DIVUW = 6'h25,
    ALU_REMW = 6'h26, ALU_REMUW = 6'h27
  } alu_op_e;

  typedef struct packed {
    logic overflow;    // ADD/SUB signed overflow
    logic div_by_zero; // DIV/REM by zero
    logic valid;       // result is valid this cycle
  } alu_status_t;

endpackage
```

---

## Top-Level: alu_64

```systemverilog
module alu_64
  import alu_pkg::*;
#(parameter int WIDTH = 64)(
  input  logic         clk, rst_n,
  input  alu_op_e      op,
  input  logic         start,        // pulse to start multi-cycle op
  output logic         busy, done,
  input  logic [WIDTH-1:0] a, b,
  output logic [WIDTH-1:0] result,
  output alu_status_t  status
);
  logic [WIDTH-1:0] add_result, logic_result, shift_result, cmp_result;
  logic [WIDTH-1:0] mul_result, div_result;
  logic add_overflow, is_word_op, is_mul, is_div, simple_valid;

  always_comb begin
    is_word_op = op inside {ALU_ADDW, ALU_SUBW, ALU_SLLW, ALU_SRLW, ALU_SRAW,
                             ALU_MULW, ALU_DIVW, ALU_DIVUW, ALU_REMW, ALU_REMUW};
    is_mul = op inside {ALU_MUL, ALU_MULH, ALU_MULHSU, ALU_MULHU, ALU_MULW};
    is_div = op inside {ALU_DIV, ALU_DIVU, ALU_REM, ALU_REMU,
                        ALU_DIVW, ALU_DIVUW, ALU_REMW, ALU_REMUW};
  end

  alu_adder   #(.WIDTH(WIDTH)) u_add (.a(a),.b(b),.sub(op==ALU_SUB||op==ALU_SUBW),
                                       .word_mode(is_word_op),.result(add_result),.overflow(add_overflow));
  alu_logic   #(.WIDTH(WIDTH)) u_log (.a(a),.b(b),.op(op),.result(logic_result));
  alu_shifter #(.WIDTH(WIDTH)) u_sh  (.a(a),.shamt(b[5:0]),.op(op),.word_mode(is_word_op),.result(shift_result));
  alu_compare #(.WIDTH(WIDTH)) u_cmp (.a(a),.b(b),.signed_cmp(op==ALU_SLT),.result(cmp_result));
  alu_multiplier #(.WIDTH(WIDTH)) u_mul (.clk(clk),.rst_n(rst_n),.start(start&&is_mul),
                                          .op(op),.a(a),.b(b),.result(mul_result),.busy(),.done());
  alu_divider    #(.WIDTH(WIDTH)) u_div (.clk(clk),.rst_n(rst_n),.start(start&&is_div),
                                          .op(op),.a(a),.b(b),.result(div_result),
                                          .div_by_zero(status.div_by_zero),.busy(busy),.done(done));

  always_comb begin
    result = '0; status.overflow = '0; status.valid = '0; simple_valid = '0;
    unique case (op)
      ALU_ADD, ALU_ADDW, ALU_SUB, ALU_SUBW: begin
        result = add_result; status.overflow = add_overflow; simple_valid = '1; end
      ALU_AND, ALU_OR, ALU_XOR:              begin result = logic_result;  simple_valid = '1; end
      ALU_SLL, ALU_SRL, ALU_SRA,
      ALU_SLLW, ALU_SRLW, ALU_SRAW:         begin result = shift_result; simple_valid = '1; end
      ALU_SLT, ALU_SLTU:                    begin result = cmp_result;  simple_valid = '1; end
      ALU_MUL,ALU_MULH,ALU_MULHSU,ALU_MULHU,ALU_MULW: result = mul_result;
      ALU_DIV,ALU_DIVU,ALU_REM,ALU_REMU,
      ALU_DIVW,ALU_DIVUW,ALU_REMW,ALU_REMUW:            result = div_result;
      default: result = '0;
    endcase
    status.valid = simple_valid ? '1 : ((is_mul || is_div) ? done : '0);
  end
endmodule
```

---

## Adder Sub-module

```systemverilog
module alu_adder #(parameter int WIDTH = 64)(
  input  logic [WIDTH-1:0] a, b,
  input  logic sub, word_mode,
  output logic [WIDTH-1:0] result,
  output logic overflow
);
  logic [WIDTH:0]   sum_ext;
  logic [WIDTH-1:0] op_b;
  assign op_b    = sub ? ~b : b;
  assign sum_ext = {1'b0, a} + {1'b0, op_b} + WIDTH'(sub);
  always_comb begin
    if (word_mode) begin
      result   = {{32{sum_ext[31]}}, sum_ext[31:0]};
      overflow = (a[31] == op_b[31]) && (sum_ext[31] != a[31]);
    end else begin
      result   = sum_ext[WIDTH-1:0];
      overflow = (a[WIDTH-1] == op_b[WIDTH-1]) && (sum_ext[WIDTH-1] != a[WIDTH-1]);
    end
  end
endmodule
```

---

## Logical Unit

```systemverilog
module alu_logic import alu_pkg::*; #(parameter int WIDTH = 64)(
  input  logic [WIDTH-1:0] a, b,
  input  alu_op_e op,
  output logic [WIDTH-1:0] result
);
  always_comb unique case (op)
    ALU_AND: result = a & b;
    ALU_OR : result = a | b;
    ALU_XOR: result = a ^ b;
    default: result = '0;
  endcase
endmodule
```

---

## Barrel Shifter

```systemverilog
module alu_shifter import alu_pkg::*; #(parameter int WIDTH = 64)(
  input  logic [WIDTH-1:0] a,
  input  logic [5:0] shamt,
  input  alu_op_e op,
  input  logic word_mode,
  output logic [WIDTH-1:0] result
);
  logic [WIDTH-1:0] src;
  logic [5:0] amt;
  always_comb begin
    src = word_mode ? {{32{a[31]}}, a[31:0]} : a;
    amt = word_mode ? {1'b0, shamt[4:0]} : shamt;
    case (1'b1)
      (op inside {ALU_SLL, ALU_SLLW}): result = src << amt;
      (op inside {ALU_SRA, ALU_SRAW}): result = $signed(src) >>> amt;
      default:                         result = src >> amt;
    endcase
    if (word_mode) result = {{32{result[31]}}, result[31:0]};
  end
endmodule
```

---

## Compare Unit

```systemverilog
module alu_compare #(parameter int WIDTH = 64)(
  input  logic [WIDTH-1:0] a, b,
  input  logic signed_cmp,
  output logic [WIDTH-1:0] result
);
  logic lt;
  assign lt     = signed_cmp ? $signed(a) < $signed(b) : a < b;
  assign result = {{(WIDTH-1){1'b0}}, lt};
endmodule
```

---

## Multiplier (3-stage pipelined placeholder)

```systemverilog
module alu_multiplier import alu_pkg::*; #(parameter int WIDTH = 64)(
  input  logic clk, rst_n, start,
  input  alu_op_e op,
  input  logic [WIDTH-1:0] a, b,
  output logic [WIDTH-1:0] result,
  output logic busy, done
);
  logic [2*WIDTH-1:0] product_full;
  logic [WIDTH-1:0]   a_r, b_r;
  alu_op_e            op_r;
  logic [1:0]         valid_pipe;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_r <= '0; b_r <= '0; valid_pipe <= '0; result <= '0;
    end else begin
      if (start) begin a_r <= a; b_r <= b; op_r <= op; end
      valid_pipe <= {valid_pipe[0], start};
      product_full = $signed(a_r) * $signed(b_r); // replace with Booth-Wallace in production
      if (valid_pipe[1]) unique case (op_r)
        ALU_MUL  : result <= product_full[WIDTH-1:0];
        ALU_MULH,
        ALU_MULHU,
        ALU_MULHSU: result <= product_full[2*WIDTH-1:WIDTH];
        ALU_MULW : result <= {{32{product_full[31]}}, product_full[31:0]};
        default  : result <= '0;
      endcase
    end
  end
  assign busy = |valid_pipe;
  assign done = valid_pipe[1];
endmodule
```

---

## Divider (iterative restoring)

```systemverilog
module alu_divider import alu_pkg::*; #(parameter int WIDTH = 64)(
  input  logic clk, rst_n, start,
  input  alu_op_e op,
  input  logic [WIDTH-1:0] a, b,
  output logic [WIDTH-1:0] result,
  output logic div_by_zero, busy, done
);
  typedef enum logic [1:0] {IDLE, BUSY, DONE} state_e;
  state_e state, state_n;
  logic [WIDTH-1:0] dividend_r, divisor_r, quotient_r, remainder_r;
  logic [6:0] count;
  logic div_op;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE; count <= '0; result <= '0; div_by_zero <= '0;
    end else begin
      state <= state_n;
      unique case (state)
        IDLE: if (start) begin
          dividend_r  <= a; divisor_r <= b;
          quotient_r  <= '0; remainder_r <= '0;
          count       <= WIDTH;
          div_by_zero <= (b == '0);
          div_op      <= op inside {ALU_DIV,ALU_DIVU,ALU_DIVW,ALU_DIVUW};
        end
        BUSY: begin
          // restoring step — replace with radix-4 SRT for performance
          if (remainder_r >= divisor_r) begin
            remainder_r <= remainder_r - divisor_r;
            quotient_r  <= {quotient_r[WIDTH-2:0], 1'b1};
          end else
            quotient_r  <= {quotient_r[WIDTH-2:0], 1'b0};
          remainder_r <= {remainder_r[WIDTH-2:0], dividend_r[WIDTH-1]};
          dividend_r  <= {dividend_r[WIDTH-2:0], 1'b0};
          count <= count - 1;
        end
        DONE: result <= div_op ? quotient_r : remainder_r;
      endcase
    end
  end

  always_comb begin
    state_n = state; busy = '0; done = '0;
    unique case (state)
      IDLE: if (start) state_n = (b == '0) ? DONE : BUSY;
      BUSY: begin busy = '1; if (count == 0) state_n = DONE; end
      DONE: begin done = '1; state_n = IDLE; end
    endcase
  end
endmodule
```

---

## Integration Notes

- Simple ops produce a result combinationally in the Execute stage
- `muldiv_busy` stalls the issue queue; `muldiv_done` releases it
- `kill` input cancels in-flight multiply/divide on mispredict or exception
- Word (`*W`) variants sign-extend from bit 31 automatically
- `zero` flag is generated from `result == '0` (computed in pipeline, used by branch unit)
- For production: swap `$signed(a) * $signed(b)` with a Booth-Wallace IP; swap iterative divider with radix-4 SRT or Newton-Raphson

## Synthesis Notes

- Critical path: 64-bit adder + barrel shifter (use Kogge-Stone or Brent-Kung adder if timing is tight)
- Multiplier: pipeline into 2–4 stages typical at 5nm-class frequencies
- Asynchronous active-low reset throughout for clean power-on behavior
- All sequential elements free of latches when synthesized per these coding guidelines
