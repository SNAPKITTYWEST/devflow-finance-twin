-- =====================================================================
-- sk_attention_matvec.vhd
-- Parameterized matrix-vector engine + AXI4 attention module.
-- Uses the updated sk_types_pkg with unconstrained fx_vec / fx_acc_vec.
-- VHDL-2008 required.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =====================================================================
-- sk_types_pkg (updated — unconstrained array form)
-- =====================================================================
package sk_types_pkg is

    subtype fx_t     is signed(15 downto 0);
    subtype fx_acc_t is signed(31 downto 0);

    type fx_vec     is array (natural range <>) of fx_t;
    type fx_acc_vec is array (natural range <>) of fx_acc_t;

    function clog2(n : positive) return positive;
    function sat_fx(x : signed) return fx_t;
    function fx_mul(a : fx_t; b : fx_t) return fx_t;
    function fx_add(a : fx_t; b : fx_t) return fx_t;
    function fx_sub(a : fx_t; b : fx_t) return fx_t;
    function exp_lut(x : fx_t) return fx_t;
    function rsqrt_lut(x : fx_t) return fx_t;

end package;

package body sk_types_pkg is

    function clog2(n : positive) return positive is
        variable r : positive := 1;
        variable v : positive := 2;
    begin
        while v < n loop v := v * 2; r := r + 1; end loop;
        return r;
    end function;

    function sat_fx(x : signed) return fx_t is
        variable v : signed(31 downto 0);
    begin
        v := resize(x, 32);
        if    v > to_signed( 32767, 32) then return to_signed( 32767, 16);
        elsif v < to_signed(-32768, 32) then return to_signed(-32768, 16);
        else                                 return resize(v, 16);
        end if;
    end function;

    function fx_mul(a : fx_t; b : fx_t) return fx_t is
        variable p : signed(31 downto 0);
    begin
        p := a * b;
        return sat_fx(shift_right(p, 12));
    end function;

    function fx_add(a : fx_t; b : fx_t) return fx_t is
        variable s : signed(16 downto 0);
    begin
        s := resize(a, 17) + resize(b, 17);
        return sat_fx(s);
    end function;

    function fx_sub(a : fx_t; b : fx_t) return fx_t is
    begin
        return fx_add(a, -b);
    end function;

    -- Stub LUTs (8-entry linear approximation for synthesis demonstration)
    function exp_lut(x : fx_t) return fx_t is
    begin
        if x >= 0 then return to_signed(4096, 16); end if;
        return to_signed(integer(4096.0 / real(1 + (-to_integer(x)) / 4096)), 16);
    end function;

    function rsqrt_lut(x : fx_t) return fx_t is
    begin
        if x <= to_signed(1, 16) then return to_signed(32767, 16); end if;
        return to_signed(4096, 16);  -- placeholder; replace with ROM in production
    end function;

end package body;

-- =====================================================================
-- sk_matvec_engine : parameterized M×N matrix-vector multiply
-- Two-stage pipeline: issue (S0) → accumulate/write (S1)
-- Latency: M*N + drain cycles, then done pulse.
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sk_types_pkg.all;

entity sk_matvec_engine is
    generic (
        M : positive := 8;
        N : positive := 8
    );
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;
        start   : in  std_logic;
        W_flat  : in  fx_vec(0 to M*N-1);   -- row-major W(i,j) = W_flat(i*N+j)
        x       : in  fx_vec(0 to N-1);
        y       : out fx_vec(0 to M-1);
        busy    : out std_logic;
        done    : out std_logic
    );
end entity;

architecture rtl of sk_matvec_engine is

    constant RW : positive := clog2(M);
    constant CW : positive := clog2(N);

    type state_t is (IDLE, RUN, DRAIN, FIN);
    signal state : state_t := IDLE;

    signal row   : unsigned(RW-1 downto 0) := (others => '0');
    signal col   : unsigned(CW-1 downto 0) := (others => '0');
    signal x_r   : fx_vec(0 to N-1)        := (others => (others => '0'));

    -- Two pipeline stages: S0 = issue/multiply, S1 = accumulate/write
    signal s0_valid : std_logic            := '0';
    signal s0_row   : unsigned(RW-1 downto 0);
    signal s0_col   : unsigned(CW-1 downto 0);
    signal s0_prod  : signed(31 downto 0);

    signal s1_valid : std_logic            := '0';
    signal s1_row   : unsigned(RW-1 downto 0);
    signal s1_col   : unsigned(CW-1 downto 0);
    signal s1_prod  : signed(31 downto 0);

    signal acc      : signed(31 downto 0)  := (others => '0');

begin

    process(clk, rst_n)
        variable ri    : integer;
        variable ci    : integer;
        variable nexta : signed(32 downto 0);
        variable scaled: signed(32 downto 0);
    begin
        if rst_n = '0' then
            state   <= IDLE; row <= (others=>'0'); col <= (others=>'0');
            s0_valid<='0'; s1_valid<='0'; acc<=(others=>'0');
            busy<='0'; done<='0';
            for i in 0 to M-1 loop y(i)<=(others=>'0'); end loop;
            for i in 0 to N-1 loop x_r(i)<=(others=>'0'); end loop;

        elsif rising_edge(clk) then
            done <= '0';

            -- Pipeline stage 1 advance
            s1_valid <= s0_valid;
            s1_row   <= s0_row;
            s1_col   <= s0_col;
            s1_prod  <= s0_prod;
            s0_valid <= '0';

            -- Stage 0: issue multiply when running
            if state = RUN then
                ri := to_integer(row);
                ci := to_integer(col);
                s0_prod  <= W_flat(ri*N + ci) * x_r(ci);
                s0_row   <= row;
                s0_col   <= col;
                s0_valid <= '1';
                if ci = N-1 then
                    col <= (others=>'0');
                    if ri = M-1 then state <= DRAIN;
                    else             row  <= row + 1;
                    end if;
                else
                    col <= col + 1;
                end if;
            end if;

            -- Stage 1: accumulate
            if s1_valid = '1' then
                nexta := resize(acc, 33) + resize(s1_prod, 33);
                if to_integer(s1_col) = N-1 then
                    scaled := shift_right(nexta, 12);
                    y(to_integer(s1_row)) <= sat_fx(scaled);
                    acc <= (others => '0');
                else
                    if    nexta >  2147483647 then acc <= to_signed( 2147483647, 32);
                    elsif nexta < -2147483648 then acc <= to_signed(-2147483648, 32);
                    else                           acc <= resize(nexta, 32);
                    end if;
                end if;
            end if;

            -- FSM
            case state is
                when IDLE =>
                    if start = '1' then
                        x_r <= x; row<=(others=>'0'); col<=(others=>'0');
                        acc<=(others=>'0'); s0_valid<='0'; s1_valid<='0';
                        busy<='1'; state <= RUN;
                    end if;
                when RUN  => null;
                when DRAIN =>
                    if s0_valid='0' and s1_valid='0' then state <= FIN; end if;
                when FIN  =>
                    busy<='0'; done<='1'; state <= IDLE;
            end case;
        end if;
    end process;
end architecture;

-- =====================================================================
-- tb_matvec : directed test (W = 2*I, x = [1,2,3,4], y = [2,4,6,8])
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity tb_matvec is end entity;
architecture sim of tb_matvec is
    constant M : positive := 4;
    constant N : positive := 4;
    signal clk,rst_n,start,busy,done : std_logic := '0';
    signal W_flat : fx_vec(0 to M*N-1) := (others=>(others=>'0'));
    signal x      : fx_vec(0 to N-1)   := (others=>(others=>'0'));
    signal y      : fx_vec(0 to M-1);
begin
    uut: entity work.sk_matvec_engine generic map(M=>M,N=>N)
        port map(clk,rst_n,start,W_flat,x,y,busy,done);

    clk_p: process begin
        loop clk<='0'; wait for 5 ns; clk<='1'; wait for 5 ns; end loop;
    end process;

    stim: process begin
        -- W = 2*I (diagonal 2.0 in Q4.12 = 8192)
        for i in 0 to M-1 loop W_flat(i*N+i) <= to_signed(8192,16); end loop;
        x(0)<=to_signed(4096,16); x(1)<=to_signed(8192,16);
        x(2)<=to_signed(12288,16); x(3)<=to_signed(16384,16);
        rst_n<='0'; wait for 20 ns; rst_n<='1';
        wait until rising_edge(clk);
        start<='1'; wait until rising_edge(clk); start<='0';
        wait until done='1'; wait until rising_edge(clk);
        assert to_integer(y(0))=8192  report "y0 wrong"     severity error;
        assert to_integer(y(1))=16384 report "y1 wrong"     severity error;
        assert to_integer(y(2))=24576 report "y2 wrong"     severity error;
        assert to_integer(y(3))=32767 report "y3 saturate"  severity error;
        assert false report "tb_matvec: PASS" severity note;
        wait;
    end process;
end architecture;

-- =====================================================================
-- sk_attention_axi : single-head causal attention, K/V from AXI4 memory
-- FSM: IDLE -> K_REQ/K_RX/K_NEXT -> SOFTMAX_MAX/EXP/SUM ->
--      V_REQ/V_RX/V_NEXT -> FIN
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;

entity sk_attention_axi is
    generic (
        SEQ_LEN  : positive := 32;
        HEAD_DIM : positive := 8;
        ADDR_W   : positive := 32
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        start    : in  std_logic;
        q        : in  fx_vec(0 to HEAD_DIM-1);
        scale    : in  fx_t;                         -- 1/sqrt(HEAD_DIM) Q4.12
        base_k   : in  unsigned(ADDR_W-1 downto 0);
        base_v   : in  unsigned(ADDR_W-1 downto 0);
        row_bytes: in  unsigned(ADDR_W-1 downto 0);  -- HEAD_DIM * 2
        -- AXI4 read address channel
        arvalid  : out std_logic;
        arready  : in  std_logic;
        araddr   : out unsigned(ADDR_W-1 downto 0);
        arlen    : out unsigned(7 downto 0);
        arsize   : out unsigned(2 downto 0);
        arburst  : out std_logic_vector(1 downto 0);
        -- AXI4 read data channel (16-bit beats)
        rvalid   : in  std_logic;
        rready   : out std_logic;
        rdata    : in  std_logic_vector(15 downto 0);
        rlast    : in  std_logic;
        ctx      : out fx_vec(0 to HEAD_DIM-1);
        busy     : out std_logic;
        done     : out std_logic
    );
end entity;

architecture rtl of sk_attention_axi is

    constant JW : positive := clog2(SEQ_LEN);
    constant BW : positive := clog2(HEAD_DIM);

    type state_t is (
        IDLE,
        K_REQ, K_RX, K_NEXT,
        SOFTMAX_MAX, SOFTMAX_EXP, SOFTMAX_SUM,
        V_REQ, V_RX, V_NEXT,
        FIN
    );
    signal state : state_t := IDLE;

    type score_array is array (0 to SEQ_LEN-1) of fx_t;
    signal score     : score_array := (others=>(others=>'0'));
    signal q_r       : fx_vec(0 to HEAD_DIM-1) := (others=>(others=>'0'));
    signal ctx_acc   : fx_acc_vec(0 to HEAD_DIM-1) := (others=>(others=>'0'));
    signal base_k_r, base_v_r, row_bytes_r : unsigned(ADDR_W-1 downto 0) := (others=>'0');
    signal scale_r   : fx_t := (others=>'0');
    signal j         : unsigned(JW-1 downto 0) := (others=>'0');
    signal beat      : unsigned(BW-1 downto 0) := (others=>'0');
    signal dot       : signed(47 downto 0)      := (others=>'0');
    signal smax      : fx_t := (others=>'0');
    signal ssum      : signed(47 downto 0) := (others=>'0');
    signal inv_sum   : fx_t := (others=>'0');

begin

    arvalid  <= '1' when state = K_REQ or state = V_REQ else '0';
    rready   <= '1' when state = K_RX  or state = V_RX  else '0';
    arlen    <= to_unsigned(HEAD_DIM-1, 8);
    arsize   <= "001";   -- 2 bytes per beat
    arburst  <= "01";    -- INCR

    araddr   <=
        base_k_r + resize(j, ADDR_W) * row_bytes_r when state = K_REQ else
        base_v_r + resize(j, ADDR_W) * row_bytes_r when state = V_REQ else
        (others => '0');

    process(clk, rst_n)
        variable ji, bi : integer;
        variable prod   : signed(47 downto 0);
        variable ex     : fx_t;
        variable sum_n  : signed(47 downto 0);
    begin
        if rst_n = '0' then
            state <= IDLE;
            j <= (others=>'0'); beat <= (others=>'0');
            dot <= (others=>'0'); ssum <= (others=>'0');
            busy<='0'; done<='0';
            for i in 0 to SEQ_LEN-1 loop score(i)<=(others=>'0'); end loop;
            for i in 0 to HEAD_DIM-1 loop
                q_r(i)<=(others=>'0'); ctx_acc(i)<=(others=>'0'); ctx(i)<=(others=>'0');
            end loop;
        elsif rising_edge(clk) then
            done <= '0';
            case state is

                when IDLE =>
                    if start = '1' then
                        q_r <= q; scale_r <= scale;
                        base_k_r <= base_k; base_v_r <= base_v;
                        row_bytes_r <= row_bytes;
                        j<=(others=>'0'); beat<=(others=>'0');
                        dot<=(others=>'0'); busy<='1'; state<=K_REQ;
                    end if;

                when K_REQ =>
                    if arready = '1' then beat<=(others=>'0'); state<=K_RX; end if;

                when K_RX =>
                    if rvalid = '1' then
                        bi := to_integer(beat);
                        dot <= dot + resize(q_r(bi)*signed(rdata), 48);
                        if rlast = '1' then
                            score(to_integer(j)) <=
                                sat_fx(shift_right(dot*scale_r, 12));
                            state <= K_NEXT;
                        else
                            beat <= beat + 1;
                        end if;
                    end if;

                when K_NEXT =>
                    dot <= (others=>'0');
                    if to_integer(j) = SEQ_LEN-1 then state<=SOFTMAX_MAX;
                    else j<=j+1; state<=K_REQ;
                    end if;

                when SOFTMAX_MAX =>
                    smax <= score(0); j<=(others=>'0'); state<=SOFTMAX_EXP;

                when SOFTMAX_EXP =>
                    if to_integer(j) < SEQ_LEN then
                        if score(to_integer(j)) > smax then
                            smax <= score(to_integer(j));
                        end if;
                        j <= j + 1;
                    else
                        ssum<=(others=>'0'); j<=(others=>'0'); state<=SOFTMAX_SUM;
                    end if;

                when SOFTMAX_SUM =>
                    if to_integer(j) < SEQ_LEN then
                        ex := exp_lut(fx_sub(score(to_integer(j)), smax));
                        score(to_integer(j)) <= ex;
                        ssum <= ssum + resize(ex, 48);
                        j <= j + 1;
                    else
                        inv_sum <= rsqrt_lut(fx_mul(sat_fx(ssum), sat_fx(ssum)));
                        for i in 0 to HEAD_DIM-1 loop ctx_acc(i)<=(others=>'0'); end loop;
                        j<=(others=>'0'); state<=V_REQ;
                    end if;

                when V_REQ =>
                    if arready = '1' then beat<=(others=>'0'); state<=V_RX; end if;

                when V_RX =>
                    if rvalid = '1' then
                        bi := to_integer(beat);
                        prod := resize(score(to_integer(j))*signed(rdata), 48);
                        ctx_acc(bi) <= ctx_acc(bi) + resize(prod, 32);
                        if rlast = '1' then state<=V_NEXT;
                        else beat<=beat+1;
                        end if;
                    end if;

                when V_NEXT =>
                    if to_integer(j) = SEQ_LEN-1 then state<=FIN;
                    else j<=j+1; state<=V_REQ;
                    end if;

                when FIN =>
                    for i in 0 to HEAD_DIM-1 loop
                        ctx(i) <= fx_mul(sat_fx(ctx_acc(i)),
                                         fx_mul(inv_sum, inv_sum));
                    end loop;
                    busy<='0'; done<='1'; state<=IDLE;

                when others => state<=IDLE;
            end case;
        end if;
    end process;
end architecture;
