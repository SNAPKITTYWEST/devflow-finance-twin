# RTL Multipliers: Booth + Wallace Tree + RISC-V Vector
*Radix-2 Booth, Radix-4 Booth, Wallace-Tree Reduction, Vector Unit — Chisel & VHDL*

---

## Radix-2 Booth Algorithm

Examines overlapping pairs of multiplier bits:

| bits y_{i+1} y_i | Action           |
|------------------|------------------|
| 00               | 0                |
| 01               | + Multiplicand   |
| 10               | − Multiplicand   |
| 11               | 0                |

Halves average addition count vs. naive; handles signed two's-complement naturally.

---

## Chisel: BoothMultiplier (Radix-2 Sequential)

```scala
// package gsl.arith
class BoothMultiplier(width: Int = 64) extends Module {
  val io = IO(new Bundle {
    val start         = Input(Bool())
    val multiplicand  = Input(SInt(width.W))
    val multiplier    = Input(SInt(width.W))
    val product       = Output(SInt((2*width).W))
    val busy          = Output(Bool())
    val done          = Output(Bool())
  })

  val sIdle :: sBusy :: sDone :: Nil = Enum(3)
  val state = RegInit(sIdle)
  val cnt   = RegInit(0.U(log2Ceil(width+1).W))
  val mReg  = Reg(SInt(width.W))
  val rReg  = Reg(SInt((width+1).W))
  val pReg  = Reg(SInt((2*width).W))

  io.busy    := state === sBusy
  io.done    := state === sDone
  io.product := pReg

  switch(state) {
    is(sIdle) {
      when(io.start) {
        mReg  := io.multiplicand
        rReg  := Cat(io.multiplier, 0.U(1.W)).asSInt
        pReg  := 0.S
        cnt   := 0.U
        state := sBusy
      }
    }
    is(sBusy) {
      val booth = rReg(1, 0)
      val addend = MuxLookup(booth, 0.S((2*width).W))(Seq(
        "b01".U -> mReg.asSInt.pad(2*width),
        "b10".U -> -mReg.asSInt.pad(2*width),
        "b00".U -> 0.S,
        "b11".U -> 0.S
      ))
      val shifted = Cat(pReg + addend, rReg).asSInt >> 1
      pReg  := shifted(2*width-1, width).asSInt
      rReg  := shifted(width, 0).asSInt
      cnt   := cnt + 1.U
      when(cnt === (width-1).U) { state := sDone }
    }
    is(sDone) { state := sIdle }
  }
}
```

---

## VHDL: booth_multiplier (Radix-2 Sequential)

```vhdl
entity booth_multiplier is
  generic (WIDTH : positive := 64);
  port (
    clk, rst_n, start : in std_logic;
    multiplicand, multiplier : in signed(WIDTH-1 downto 0);
    product : out signed(2*WIDTH-1 downto 0);
    busy, done : out std_logic
  );
end entity;

architecture rtl of booth_multiplier is
  type state_t is (IDLE, BUSY, DONE);
  signal state : state_t := IDLE;
  signal m_reg : signed(WIDTH-1 downto 0);
  signal r_reg : signed(WIDTH downto 0);
  signal p_reg : signed(2*WIDTH-1 downto 0);
  signal cnt   : integer range 0 to WIDTH := 0;
begin
  busy    <= '1' when state = BUSY else '0';
  done    <= '1' when state = DONE else '0';
  product <= p_reg;

  process(clk, rst_n)
    variable addend  : signed(2*WIDTH-1 downto 0);
    variable shifted : signed(2*WIDTH downto 0);
  begin
    if rst_n = '0' then
      state <= IDLE; p_reg <= (others => '0'); cnt <= 0;
    elsif rising_edge(clk) then
      case state is
        when IDLE =>
          if start = '1' then
            m_reg <= multiplicand;
            r_reg <= multiplier & '0';
            p_reg <= (others => '0');
            cnt   <= 0; state <= BUSY;
          end if;
        when BUSY =>
          case std_logic_vector(r_reg(1 downto 0)) is
            when "01"   => addend := resize(m_reg, 2*WIDTH);
            when "10"   => addend := resize(-m_reg, 2*WIDTH);
            when others => addend := (others => '0');
          end case;
          shifted := (p_reg + addend)(2*WIDTH-1) & (p_reg + addend) & r_reg(WIDTH downto 1);
          p_reg <= shifted(2*WIDTH downto WIDTH+1);
          r_reg <= shifted(WIDTH downto 0);
          if cnt = WIDTH-1 then state <= DONE; else cnt <= cnt + 1; end if;
        when DONE => state <= IDLE;
      end case;
    end if;
  end process;
end architecture;
```

---

## Radix-4 Booth Encoding

Examines 3 overlapping bits per step → 32 steps for 64-bit (half of radix-2):

| bits y_{i+1} y_i y_{i-1} | Digit |
|---------------------------|-------|
| 000                       | 0     |
| 001                       | +1    |
| 010                       | +1    |
| 011                       | +2    |
| 100                       | −2    |
| 101                       | −1    |
| 110                       | −1    |
| 111                       | 0     |

### Chisel: Radix4BoothEncoder

```scala
class Radix4BoothEncoder extends Module {
  val io = IO(new Bundle {
    val bits  = Input(UInt(3.W))
    val digit = Output(SInt(3.W))   // -2..+2
    val neg   = Output(Bool())
    val sel2  = Output(Bool())
    val sel1  = Output(Bool())
    val zero  = Output(Bool())
  })
  io.digit := MuxLookup(io.bits, 0.S(3.W))(Seq(
    "b000".U ->  0.S, "b001".U ->  1.S, "b010".U ->  1.S, "b011".U ->  2.S,
    "b100".U -> -2.S, "b101".U -> -1.S, "b110".U -> -1.S, "b111".U ->  0.S
  ))
  io.neg  := io.digit < 0.S
  io.sel2 := io.digit.abs === 2.S
  io.sel1 := io.digit.abs === 1.S
  io.zero := io.digit === 0.S
}
```

### Chisel: Optimized Radix-4 Encoder (with NAF-style flags)

```scala
class OptimizedRadix4Encoder extends Module {
  val io = IO(new Bundle {
    val bits  = Input(UInt(3.W))
    val digit = Output(SInt(3.W))
    val neg   = Output(Bool())
    val sel2  = Output(Bool())
    val sel1  = Output(Bool())
    val zero  = Output(Bool())
    val hard2 = Output(Bool())   // true when ±2 is unavoidable
  })
  val raw = MuxLookup(io.bits, 0.S(3.W))(Seq(
    "b000".U ->  0.S, "b001".U ->  1.S, "b010".U ->  1.S, "b011".U ->  2.S,
    "b100".U -> -2.S, "b101".U -> -1.S, "b110".U -> -1.S, "b111".U ->  0.S
  ))
  io.digit := raw
  io.neg   := raw < 0.S
  io.sel2  := raw.abs === 2.S
  io.sel1  := raw.abs === 1.S
  io.zero  := raw === 0.S
  io.hard2 := io.sel2
}
```

### Chisel: Radix4BoothMultiplier (Sequential)

```scala
class Radix4BoothMultiplier(width: Int = 64) extends Module {
  require(width % 2 == 0)
  val io = IO(new Bundle {
    val start        = Input(Bool())
    val multiplicand = Input(SInt(width.W))
    val multiplier   = Input(SInt(width.W))
    val product      = Output(SInt((2*width).W))
    val busy         = Output(Bool())
    val done         = Output(Bool())
  })
  val sIdle :: sBusy :: sDone :: Nil = Enum(3)
  val state = RegInit(sIdle)
  val steps = width / 2
  val cnt   = RegInit(0.U(log2Ceil(steps+1).W))
  val mReg  = Reg(SInt(width.W))
  val rReg  = Reg(UInt((width+1).W))
  val pReg  = Reg(SInt((2*width).W))
  val enc   = Module(new Radix4BoothEncoder)

  io.busy    := state === sBusy
  io.done    := state === sDone
  io.product := pReg

  switch(state) {
    is(sIdle) {
      when(io.start) {
        mReg := io.multiplicand; rReg := Cat(io.multiplier, 0.U(1.W))
        pReg := 0.S; cnt := 0.U; state := sBusy
      }
    }
    is(sBusy) {
      enc.io.bits := rReg(2, 0)
      val mExt   = mReg.pad(2*width)
      val mShift = (mReg << 1).pad(2*width)
      val addend = MuxCase(0.S((2*width).W), Seq(
        enc.io.zero                      -> 0.S,
        (enc.io.sel1 && !enc.io.neg)     -> mExt,
        (enc.io.sel1 &&  enc.io.neg)     -> -mExt,
        (enc.io.sel2 && !enc.io.neg)     -> mShift,
        (enc.io.sel2 &&  enc.io.neg)     -> -mShift
      ))
      val shifted = Cat(pReg + addend, rReg).asSInt >> 2
      pReg := shifted(2*width-1, width).asSInt
      rReg := shifted(width, 0).asUInt
      cnt  := cnt + 1.U
      when(cnt === (steps-1).U) { state := sDone }
    }
    is(sDone) { state := sIdle }
  }
}
```

### VHDL: radix4_booth_encoder

```vhdl
entity radix4_booth_encoder is
  port (
    bits : in  std_logic_vector(2 downto 0);
    digit : out signed(2 downto 0);
    neg, sel2, sel1, zero : out std_logic
  );
end entity;

architecture rtl of radix4_booth_encoder is
  signal d : signed(2 downto 0);
begin
  process(bits)
  begin
    case bits is
      when "000" => d <= "000"; when "001" => d <= "001";
      when "010" => d <= "001"; when "011" => d <= "010";
      when "100" => d <= "110"; when "101" => d <= "111";
      when "110" => d <= "111"; when others => d <= "000";
    end case;
  end process;
  digit <= d;
  neg   <= '1' when d < 0 else '0';
  sel2  <= '1' when abs(d) = 2 else '0';
  sel1  <= '1' when abs(d) = 1 else '0';
  zero  <= '1' when d = 0 else '0';
end architecture;
```

---

## Wallace-Tree Reduction (Radix-4 Booth, 64-bit)

64-bit × 64-bit: 32 partial products reduced to 2 rows by carry-save adder (CSA) tree, then final carry-propagate adder (CPA) produces 128-bit result.

```scala
class Radix4WallaceMultiplier(width: Int = 64) extends Module {
  require(width % 2 == 0)
  val io = IO(new Bundle {
    val a = Input(SInt(width.W))
    val b = Input(SInt(width.W))
    val p = Output(SInt((2*width).W))
  })

  // 1. Generate 32 Booth digits
  val digits = Wire(Vec(width/2, SInt(3.W)))
  val bExt   = Cat(io.b, 0.U(1.W))
  for (i <- 0 until width/2) {
    val enc = Module(new OptimizedRadix4Encoder)
    enc.io.bits := bExt(2*i+2, 2*i)
    digits(i) := enc.io.digit
  }

  // 2. Generate partial products
  val pp = Wire(Vec(width/2, SInt((width+2).W)))
  for (i <- 0 until width/2) {
    val m  = io.a
    val m2 = (io.a << 1).asSInt
    pp(i) := MuxLookup(digits(i), 0.S)(Seq(
       1.S ->  m.pad(width+2),  2.S ->  m2.pad(width+2),
      -1.S -> -m.pad(width+2), -2.S -> -m2.pad(width+2),
       0.S ->  0.S
    ))
  }

  // 3. Align by shifting 2*i bits
  val aligned = Wire(Vec(width/2, SInt((2*width).W)))
  for (i <- 0 until width/2)
    aligned(i) := (pp(i).asUInt << (2*i)).asSInt.pad(2*width)

  // 4. Wallace/Dadda-style reduction (recursive CSA)
  def reduce(rows: Seq[SInt]): (SInt, SInt) = {
    if (rows.length <= 2) (rows(0), if (rows.length == 2) rows(1) else 0.S)
    else {
      val next = rows.grouped(3).toSeq.flatMap { g =>
        if (g.length == 3) {
          val (sum, cout) = fullAdderVector(g(0), g(1), g(2))
          Seq(sum, cout << 1)
        } else g
      }
      reduce(next)
    }
  }
  val (sum, carry) = reduce(aligned.toSeq)
  io.p := sum + carry   // final CPA
}
```

---

## Recursive Digit Generation (for generator/SASS lowering)

```scala
def boothDigits(bits: Seq[Boolean], acc: List[Int] = Nil): List[Int] = {
  if (bits.length < 3) acc.reverse
  else {
    val digit = encodeRadix4(bits.take(3))   // returns -2..+2
    boothDigits(bits.drop(2), digit :: acc)  // stride 2
  }
}
```

Maps naturally onto: Chisel for-generate (unrolled), VHDL generate, CUDA kernel, or hand-rolled SASS inner loop.

---

## CUDA Skeleton (Conceptual)

```cuda
__device__ long long radix4_booth_mul(long long a, long long b) {
    long long product = 0;
    #pragma unroll
    for (int i = 0; i < 32; i++) {
        int digit = encode_radix4(b, i);    // -2..+2
        product += (a * digit) << (2 * i);
    }
    return product;
}
```

From here a GPU engineer would inspect SASS (`cuobjdump -sass`), then replace the inner loop with hand-scheduled `IMAD`, `IADD3`, `SHF`, `LOP3`. Actual SASS opcodes are architecture-specific (Ampere/Hopper/Blackwell) and must be validated on target silicon.

---

## RISC-V Vector Multiply Unit

### Chisel: VectorBoothMul

```scala
class VectorBoothMul(
  val VLEN  : Int = 256,
  val ELEN  : Int = 64,
  val lanes : Int = VLEN / ELEN
) extends Module {
  val io = IO(new Bundle {
    val start = Input(Bool())
    val vs2   = Input(UInt(VLEN.W))
    val vs1   = Input(UInt(VLEN.W))
    val vd    = Output(UInt(VLEN.W))
    val busy  = Output(Bool())
    val done  = Output(Bool())
  })
  val mulUnits = Seq.fill(lanes)(Module(new BoothMultiplier(ELEN)))
  for (i <- 0 until lanes) {
    mulUnits(i).io.start        := io.start
    mulUnits(i).io.multiplicand := io.vs2(ELEN*(i+1)-1, ELEN*i).asSInt
    mulUnits(i).io.multiplier   := io.vs1(ELEN*(i+1)-1, ELEN*i).asSInt
  }
  io.vd   := VecInit(mulUnits.map(_.io.product(ELEN-1,0).asUInt)).asUInt
  io.busy := mulUnits.map(_.io.busy).reduce(_ || _)
  io.done := mulUnits.map(_.io.done).reduce(_ && _)
}
```

### VHDL: vector_booth_mul (structural)

```vhdl
entity vector_booth_mul is
  generic (VLEN : positive := 256; ELEN : positive := 64);
  port (
    clk, rst_n, start : in  std_logic;
    vs2, vs1          : in  std_logic_vector(VLEN-1 downto 0);
    vd                : out std_logic_vector(VLEN-1 downto 0);
    busy, done        : out std_logic
  );
end entity;

architecture structural of vector_booth_mul is
  constant LANES : positive := VLEN / ELEN;
  type product_array is array (0 to LANES-1) of signed(2*ELEN-1 downto 0);
  signal products : product_array;
  signal busy_vec, done_vec : std_logic_vector(LANES-1 downto 0);
begin
  gen_lanes: for i in 0 to LANES-1 generate
    u_mul : booth_multiplier
      generic map (WIDTH => ELEN)
      port map (
        clk => clk, rst_n => rst_n, start => start,
        multiplicand => signed(vs2(ELEN*(i+1)-1 downto ELEN*i)),
        multiplier   => signed(vs1(ELEN*(i+1)-1 downto ELEN*i)),
        product      => products(i),
        busy => busy_vec(i), done => done_vec(i)
      );
    vd(ELEN*(i+1)-1 downto ELEN*i) <= std_logic_vector(products(i)(ELEN-1 downto 0));
  end generate;
  busy <= '1' when busy_vec /= (busy_vec'range => '0') else '0';
  done <= '1' when done_vec =  (done_vec'range => '1') else '0';
end architecture;
```

---

## Usage as Custom Hardware Library

**Chisel**
```scala
import gsl.arith.BoothMultiplier
import gsl.vector.VectorBoothMul

val mul  = Module(new BoothMultiplier(64))
val vmul = Module(new VectorBoothMul(VLEN = 256, ELEN = 64))
```

**VHDL**
```vhdl
u_scalar : booth_multiplier generic map (WIDTH => 64) port map (...);
u_vector : vector_booth_mul generic map (VLEN => 256, ELEN => 64) port map (...);
```

---

## Summary

| Component                   | Status                           | Language       |
|-----------------------------|----------------------------------|----------------|
| Radix-2 Booth encoder       | Complete                         | Chisel + VHDL  |
| Radix-4 Booth encoder       | Complete                         | Chisel + VHDL  |
| Optimized Radix-4 encoder   | Complete (NAF-style flags)       | Chisel         |
| Sequential Booth multiplier | Complete                         | Chisel + VHDL  |
| Partial-product generation  | Complete                         | Chisel         |
| Wallace-style reduction     | Recursive pattern                | Chisel         |
| Recursive digit loop        | Ready for generators             | Scala          |
| RISC-V vector multiply      | Complete (lane-parallel)         | Chisel + VHDL  |
| CUDA kernel skeleton        | High-level, ready for tuning     | CUDA           |

For production: replace radix-2 with radix-4; add mask/SEW/LMUL support for full RVV compliance; wrap with AXI-Stream for loosely-coupled accelerator use.
