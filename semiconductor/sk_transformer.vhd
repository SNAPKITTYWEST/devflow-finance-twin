-- =====================================================================
-- sk_transformer.vhd
-- SK Transformer compiler demonstrator.
-- Config: D=8, LAYERS=2, HEADS=1, FFN=16, SEQ_LEN=4, VOCAB=16.
-- Fixed-point: fx_t = Q4.12 signed(15 downto 0). Acc = Q16.16.
-- ASIC boundary entities are technology-independent stubs.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- =====================================================================
-- 1. sk_types_pkg : Q-format types, array types, saturating ops.
-- =====================================================================
package sk_types_pkg is

    constant D_W     : integer := 8;
    constant LAYERS_W: integer := 2;
    constant HEADS_W : integer := 1;
    constant FFN_W   : integer := 16;
    constant SEQ_W   : integer := 4;
    constant VOCAB_W : integer := 16;
    constant QQ_W    : integer := 4;
    constant QP_W    : integer := 1;
    constant WEYL_N  : integer := 2 * QQ_W;

    subtype fx_t     is signed(15 downto 0);   -- Q4.12
    subtype fx_acc_t is signed(31 downto 0);   -- Q16.16

    constant FX_FRAC : integer := 12;
    constant FX_ONE  : fx_t   := to_signed(4096, 16);
    constant FX_EPS  : fx_t   := to_signed(64, 16);    -- 1/64

    type fx_vec_d    is array (0 to D_W-1)    of fx_t;
    type fx_vec_ffn  is array (0 to FFN_W-1)  of fx_t;
    type fx_vec_voc  is array (0 to VOCAB_W-1)of fx_t;
    type fx_vec_wq   is array (0 to WEYL_N-1) of fx_t;
    type fx_mat_dd   is array (0 to D_W-1,   0 to D_W-1)   of fx_t;
    type fx_mat_dffn is array (0 to FFN_W-1, 0 to D_W-1)   of fx_t;
    type fx_mat_ffnd is array (0 to D_W-1,   0 to FFN_W-1) of fx_t;
    type fx_mat_vocd is array (0 to VOCAB_W-1,0 to D_W-1)  of fx_t;
    type fx_mat_wq   is array (0 to WEYL_N-1, 0 to WEYL_N-1)of fx_t;
    type fx_seq_vec  is array (0 to SEQ_W-1)  of fx_vec_d;

    function sat_fx(x : fx_acc_t) return fx_t;
    function fx_mul(a, b : fx_t)  return fx_t;
    function fx_add(a, b : fx_t)  return fx_t;
    function fx_sub(a, b : fx_t)  return fx_t;

end package;

package body sk_types_pkg is

    function sat_fx(x : fx_acc_t) return fx_t is
        variable s : fx_acc_t;
    begin
        s := shift_right(x, FX_FRAC);
        if    s > 32767  then return to_signed( 32767, 16);
        elsif s < -32768 then return to_signed(-32768, 16);
        else                  return s(15 downto 0);
        end if;
    end function;

    function fx_mul(a, b : fx_t) return fx_t is
        variable p : signed(31 downto 0);
    begin
        p := a * b;
        return sat_fx(shift_right(p, FX_FRAC));
    end function;

    function fx_add(a, b : fx_t) return fx_t is
        variable s : signed(16 downto 0);
    begin
        s := resize(a, 17) + resize(b, 17);
        if    s > 32767  then return to_signed( 32767, 16);
        elsif s < -32768 then return to_signed(-32768, 16);
        else                  return s(15 downto 0);
        end if;
    end function;

    function fx_sub(a, b : fx_t) return fx_t is
    begin
        return fx_add(a, -b);
    end function;

end package body;

-- =====================================================================
-- 2. ASIC boundary stubs (technology-independent)
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_asic_inv   is port(a:in std_logic;y:out std_logic); end entity;
architecture rtl of sk_asic_inv   is begin y <= not a; end architecture;

entity sk_asic_nand2 is port(a,b:in std_logic;y:out std_logic); end entity;
architecture rtl of sk_asic_nand2 is begin y <= a nand b; end architecture;

entity sk_asic_nor2  is port(a,b:in std_logic;y:out std_logic); end entity;
architecture rtl of sk_asic_nor2  is begin y <= a nor b; end architecture;

entity sk_asic_mux2  is port(a,b,s:in std_logic;y:out std_logic); end entity;
architecture rtl of sk_asic_mux2  is
begin y <= (a and not s) or (b and s); end architecture;

entity sk_asic_dff is
    port(clk,rst_n,d:in std_logic; q:out std_logic);
end entity;
architecture rtl of sk_asic_dff is
begin
    process(clk,rst_n) begin
        if rst_n='0' then q<='0';
        elsif rising_edge(clk) then q<=d;
        end if;
    end process;
end architecture;

-- =====================================================================
-- 3. sk_math_pkg : LUTs for rsqrt and exp (elaboration-time init)
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all; use ieee.numeric_std.all; use ieee.math_real.all;
use work.sk_types_pkg.all;

package sk_math_pkg is

    type rsqrt_lut_t is array (0 to 255) of fx_t;
    type exp_lut_t   is array (0 to 255) of fx_t;

    function rsqrt_init return rsqrt_lut_t;
    function exp_init   return exp_lut_t;
    function rsqrt_lut(x : fx_t) return fx_t;
    function exp_lut(x   : fx_t) return fx_t;

    constant RSQRT_TAB : rsqrt_lut_t := rsqrt_init;
    constant EXP_TAB   : exp_lut_t   := exp_init;

end package;

package body sk_math_pkg is

    function rsqrt_init return rsqrt_lut_t is
        variable t : rsqrt_lut_t; variable x : real; variable v : integer;
    begin
        for i in 0 to 255 loop
            x := (real(i) + 0.5) / 16.0;
            if x < 0.0625 then x := 0.0625; end if;
            v := integer(4096.0 / sqrt(x));
            if v > 32767 then v := 32767; end if;
            t(i) := to_signed(v, 16);
        end loop;
        return t;
    end function;

    function exp_init return exp_lut_t is
        variable t : exp_lut_t; variable x : real; variable v : integer;
    begin
        for i in 0 to 255 loop
            x := -real(i) / 32.0;
            v := integer(4096.0 * exp(x));
            if v > 32767 then v := 32767; end if;
            if v < 0     then v := 0;     end if;
            t(i) := to_signed(v, 16);
        end loop;
        return t;
    end function;

    function rsqrt_lut(x : fx_t) return fx_t is
        variable ux  : unsigned(15 downto 0);
        variable idx : integer;
    begin
        if x <= 0 then return to_signed(32767, 16); end if;
        ux  := unsigned(x);
        idx := to_integer(ux(15 downto 8));
        if idx > 255 then idx := 255; end if;
        return RSQRT_TAB(idx);
    end function;

    function exp_lut(x : fx_t) return fx_t is
        variable n   : integer;
        variable idx : integer;
    begin
        if x >= 0 then return FX_ONE; end if;
        n   := -to_integer(x);
        idx := n / 128;
        if idx > 255 then idx := 255; end if;
        return EXP_TAB(idx);
    end function;

end package body;

-- =====================================================================
-- 4. sk_rmsnorm : y_i = x_i * g_i * rsqrt(mean(x^2) + eps)
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all; use work.sk_math_pkg.all;

entity sk_rmsnorm is
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;
        start : in  std_logic;
        x     : in  fx_vec_d;
        g     : in  fx_vec_d;
        y     : out fx_vec_d;
        done  : out std_logic
    );
end entity;

architecture rtl of sk_rmsnorm is
    type state_t is (IDLE, SQ, APPLY, FIN);
    signal st      : state_t  := IDLE;
    signal sum_sq  : fx_acc_t := (others => '0');
    signal inv_rms : fx_t     := (others => '0');
begin
    process(clk, rst_n)
        variable acc  : fx_acc_t;
        variable prod : fx_acc_t;
        variable m    : fx_t;
    begin
        if rst_n = '0' then
            st <= IDLE; sum_sq <= (others=>'0'); inv_rms <= (others=>'0');
            done <= '0';
            for i in 0 to D_W-1 loop y(i) <= (others=>'0'); end loop;
        elsif rising_edge(clk) then
            done <= '0';
            case st is
                when IDLE =>
                    if start = '1' then
                        acc := (others => '0');
                        for i in 0 to D_W-1 loop
                            prod := resize(x(i)*x(i), 32);
                            acc  := acc + prod;
                        end loop;
                        sum_sq <= acc; st <= SQ;
                    end if;
                when SQ =>
                    acc    := shift_right(sum_sq, 3);  -- /D (D=8=2^3)
                    m      := sat_fx(acc);
                    m      := fx_add(m, FX_EPS);
                    inv_rms <= rsqrt_lut(m); st <= APPLY;
                when APPLY =>
                    for i in 0 to D_W-1 loop
                        y(i) <= fx_mul(fx_mul(x(i), g(i)), inv_rms);
                    end loop;
                    st <= FIN;
                when FIN =>
                    done <= '1'; st <= IDLE;
            end case;
        end if;
    end process;
end architecture;

-- =====================================================================
-- 5. sk_matvec variants : y = W*x (combinational)
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;

entity sk_matvec_dd is
    port (W : in fx_mat_dd; x : in fx_vec_d; y : out fx_vec_d);
end entity;
architecture comb of sk_matvec_dd is
begin
    gen_i : for i in 0 to D_W-1 generate
        process(W,x) variable acc:fx_acc_t; variable p:signed(31 downto 0);
        begin acc:=(others=>'0');
            for j in 0 to D_W-1 loop p:=W(i,j)*x(j); acc:=acc+resize(p,32); end loop;
            y(i) <= sat_fx(acc);
        end process;
    end generate;
end architecture;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity sk_matvec_dffn is
    port (W : in fx_mat_dffn; x : in fx_vec_d; y : out fx_vec_ffn);
end entity;
architecture comb of sk_matvec_dffn is
begin
    gen_i : for i in 0 to FFN_W-1 generate
        process(W,x) variable acc:fx_acc_t; variable p:signed(31 downto 0);
        begin acc:=(others=>'0');
            for j in 0 to D_W-1 loop p:=W(i,j)*x(j); acc:=acc+resize(p,32); end loop;
            y(i) <= sat_fx(acc);
        end process;
    end generate;
end architecture;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity sk_matvec_ffnd is
    port (W : in fx_mat_ffnd; x : in fx_vec_ffn; y : out fx_vec_d);
end entity;
architecture comb of sk_matvec_ffnd is
begin
    gen_i : for i in 0 to D_W-1 generate
        process(W,x) variable acc:fx_acc_t; variable p:signed(31 downto 0);
        begin acc:=(others=>'0');
            for j in 0 to FFN_W-1 loop p:=W(i,j)*x(j); acc:=acc+resize(p,32); end loop;
            y(i) <= sat_fx(acc);
        end process;
    end generate;
end architecture;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity sk_matvec_vocd is
    port (W : in fx_mat_vocd; x : in fx_vec_d; y : out fx_vec_voc);
end entity;
architecture comb of sk_matvec_vocd is
begin
    gen_i : for i in 0 to VOCAB_W-1 generate
        process(W,x) variable acc:fx_acc_t; variable p:signed(31 downto 0);
        begin acc:=(others=>'0');
            for j in 0 to D_W-1 loop p:=W(i,j)*x(j); acc:=acc+resize(p,32); end loop;
            y(i) <= sat_fx(acc);
        end process;
    end generate;
end architecture;

-- =====================================================================
-- 6. sk_weyl : real-form D_theta on 2q-dim vector
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity sk_weyl is
    port (Cmat : in fx_mat_wq; x : in fx_vec_wq; y : out fx_vec_wq);
end entity;
architecture comb of sk_weyl is
begin
    gen_i : for i in 0 to WEYL_N-1 generate
        process(Cmat,x) variable acc:fx_acc_t; variable p:signed(31 downto 0);
        begin acc:=(others=>'0');
            for j in 0 to WEYL_N-1 loop p:=Cmat(i,j)*x(j); acc:=acc+resize(p,32); end loop;
            y(i) <= sat_fx(acc);
        end process;
    end generate;
end architecture;

-- =====================================================================
-- 7. sk_swiglu : silu(g) * u
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all; use work.sk_math_pkg.all;
entity sk_swiglu is
    port (g : in fx_vec_ffn; u : in fx_vec_ffn; y : out fx_vec_ffn);
end entity;
architecture comb of sk_swiglu is
begin
    gen_i : for i in 0 to FFN_W-1 generate
        process(g,u)
            variable eg, denom, silu : fx_t;
        begin
            eg    := exp_lut(-g(i));
            denom := fx_add(FX_ONE, eg);
            -- 1-step Newton for 1/denom, starting from (2 - denom)
            silu  := fx_mul(g(i), fx_sub(fx_add(FX_ONE, FX_ONE), denom));
            silu  := fx_mul(silu, fx_sub(fx_add(FX_ONE, FX_ONE),
                                         fx_mul(denom, silu)));
            y(i) <= fx_mul(silu, u(i));
        end process;
    end generate;
end architecture;

-- =====================================================================
-- 8. sk_attention : single head, SEQ_W positions, head_dim = D_W
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all; use work.sk_math_pkg.all;
entity sk_attention is
    port (
        q      : in  fx_vec_d;
        Kcache : in  fx_seq_vec;
        Vcache : in  fx_seq_vec;
        ctx    : out fx_vec_d
    );
end entity;
architecture comb of sk_attention is
begin
    process(q, Kcache, Vcache)
        type score_arr is array (0 to SEQ_W-1) of fx_t;
        variable s    : score_arr;
        variable smax : fx_t;
        variable dot  : fx_acc_t;
        variable exs  : fx_acc_t;
        variable ctxa : fx_acc_t;
        variable ex   : fx_t;
        variable rcp  : fx_t;
        variable p    : signed(31 downto 0);
    begin
        for j in 0 to SEQ_W-1 loop
            dot := (others=>'0');
            for k in 0 to D_W-1 loop
                p := q(k)*Kcache(j)(k); dot := dot+resize(p,32);
            end loop;
            s(j) := sat_fx(dot);
        end loop;

        smax := s(0);
        for j in 1 to SEQ_W-1 loop
            if s(j) > smax then smax := s(j); end if;
        end loop;

        exs := (others=>'0');
        for j in 0 to SEQ_W-1 loop
            ex := exp_lut(fx_sub(s(j), smax));
            s(j) := ex;
            exs  := exs + resize(ex, 32);
        end loop;

        rcp := rsqrt_lut(fx_mul(sat_fx(exs), sat_fx(exs)));
        rcp := fx_mul(rcp, rcp);

        for k in 0 to D_W-1 loop
            ctxa := (others=>'0');
            for j in 0 to SEQ_W-1 loop
                p := s(j)*Vcache(j)(k); ctxa := ctxa+resize(p,32);
            end loop;
            ctx(k) <= fx_mul(sat_fx(ctxa), rcp);
        end loop;
    end process;
end architecture;

-- =====================================================================
-- 9. sk_transformer_block
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all; use work.sk_math_pkg.all;
entity sk_transformer_block is
    port (
        clk    : in  std_logic;
        rst_n  : in  std_logic;
        start  : in  std_logic;
        x_in   : in  fx_vec_d;
        W_g    : in  fx_vec_d;
        W_q    : in  fx_mat_dd;
        W_k    : in  fx_mat_dd;
        W_v    : in  fx_mat_dd;
        W_o    : in  fx_mat_dd;
        W_gate : in  fx_mat_dffn;
        W_down : in  fx_mat_ffnd;
        W_g2   : in  fx_vec_d;
        Kcache : in  fx_seq_vec;
        Vcache : in  fx_seq_vec;
        x_out  : out fx_vec_d;
        done   : out std_logic
    );
end entity;
architecture rtl of sk_transformer_block is
    type state_t is (IDLE, R1, R2, FIN);
    signal st  : state_t := IDLE;
    signal xn1 : fx_vec_d; signal xn1_d : std_logic;
    signal qv, kv, vv, ctx, mlp : fx_vec_d;
    signal x1, xn2 : fx_vec_d; signal xn2_d : std_logic;
    signal gate, up, sw : fx_vec_ffn;
    signal x2 : fx_vec_d;
begin
    n1 : entity work.sk_rmsnorm   port map(clk,rst_n,'1',x_in,W_g,xn1,xn1_d);
    mq : entity work.sk_matvec_dd port map(W_q,xn1,qv);
    mk : entity work.sk_matvec_dd port map(W_k,xn1,kv);
    mv : entity work.sk_matvec_dd port map(W_v,xn1,vv);
    at : entity work.sk_attention  port map(qv,Kcache,Vcache,ctx);
    mo : entity work.sk_matvec_dd  port map(W_o,ctx,mlp);
    n2 : entity work.sk_rmsnorm    port map(clk,rst_n,'1',x1,W_g2,xn2,xn2_d);
    mg : entity work.sk_matvec_dffn port map(W_gate,xn2,gate);
    mu : entity work.sk_matvec_dffn port map(W_gate,xn2,up);
    sw1: entity work.sk_swiglu      port map(gate,up,sw);
    md : entity work.sk_matvec_ffnd port map(W_down,sw,mlp);
    process(clk,rst_n) begin
        if rst_n='0' then
            st<=IDLE; done<='0';
            x1<=(others=>(others=>'0')); x2<=(others=>(others=>'0'));
            x_out<=(others=>(others=>'0'));
        elsif rising_edge(clk) then
            done<='0';
            case st is
                when IDLE => if start='1' then st<=R1; end if;
                when R1   =>
                    for i in 0 to D_W-1 loop x1(i)<=fx_add(x_in(i),mlp(i)); end loop;
                    st<=R2;
                when R2   =>
                    for i in 0 to D_W-1 loop x2(i)<=fx_add(x1(i),mlp(i)); end loop;
                    x_out<=x2; st<=FIN;
                when FIN  => done<='1'; st<=IDLE;
                when others => st<=IDLE;
            end case;
        end if;
    end process;
end architecture;

-- =====================================================================
-- 10. sk_transformer : LAYERS_W-layer stack
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity sk_transformer is
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        start    : in  std_logic;
        tok_emb  : in  fx_vec_d;
        W_g      : in  fx_vec_d;
        W_q,W_k,W_v,W_o : in fx_mat_dd;
        W_gate   : in  fx_mat_dffn;
        W_down   : in  fx_mat_ffnd;
        W_g2     : in  fx_vec_d;
        Kcache   : in  fx_seq_vec;
        Vcache   : in  fx_seq_vec;
        W_head   : in  fx_mat_vocd;
        logits   : out fx_vec_voc;
        done     : out std_logic
    );
end entity;
architecture rtl of sk_transformer is
    type layer_vec is array (0 to LAYERS_W-1) of fx_vec_d;
    signal x_lay    : layer_vec;
    signal done_lay : std_logic_vector(LAYERS_W-1 downto 0);
    signal st_vec   : std_logic_vector(LAYERS_W-1 downto 0);
    signal head_in  : fx_vec_d;
begin
    x_lay(0) <= tok_emb;
    st_vec(0) <= start;
    gen_chain: for L in 0 to LAYERS_W-2 generate
        st_vec(L+1) <= done_lay(L);
        x_lay(L+1)  <= x_lay(L);
    end generate;
    gen_blocks: for L in 0 to LAYERS_W-1 generate
        blk: entity work.sk_transformer_block
            port map(clk,rst_n,st_vec(L),x_lay(L),W_g,W_q,W_k,W_v,W_o,
                     W_gate,W_down,W_g2,Kcache,Vcache,open,done_lay(L));
    end generate;
    head_in <= x_lay(LAYERS_W-1);
    head: entity work.sk_matvec_vocd port map(W_head, head_in, logits);
    done <= done_lay(LAYERS_W-1);
end architecture;

-- =====================================================================
-- 11. tb_sk_transformer : cycle-accurate sanity test
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use work.sk_types_pkg.all;
entity tb_sk_transformer is end entity;
architecture sim of tb_sk_transformer is
    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal start : std_logic := '0';
    signal tok_emb       : fx_vec_d  := (others=>(others=>'0'));
    signal W_g, W_g2     : fx_vec_d  := (others=>to_signed(4096,16));
    signal W_q,W_k,W_v,W_o : fx_mat_dd :=
        (others=>(others=>to_signed(0,16)));
    signal W_gate  : fx_mat_dffn := (others=>(others=>to_signed(0,16)));
    signal W_down  : fx_mat_ffnd := (others=>(others=>to_signed(0,16)));
    signal Kcache,Vcache : fx_seq_vec :=
        (others=>(others=>(others=>to_signed(0,16))));
    signal W_head  : fx_mat_vocd := (others=>(others=>to_signed(0,16)));
    signal logits  : fx_vec_voc;
    signal done    : std_logic;
begin
    uut: entity work.sk_transformer
        port map(clk,rst_n,start,tok_emb,W_g,W_q,W_k,W_v,W_o,
                 W_gate,W_down,W_g2,Kcache,Vcache,W_head,logits,done);

    clk_p: process begin
        loop clk<='0'; wait for 5 ns; clk<='1'; wait for 5 ns; end loop;
    end process;

    stim: process begin
        rst_n<='0'; wait for 20 ns;
        rst_n<='1'; wait until rising_edge(clk);
        for i in 0 to D_W-1 loop
            W_q(i,i) <= to_signed(4096,16);
            W_k(i,i) <= to_signed(4096,16);
            W_v(i,i) <= to_signed(4096,16);
            W_o(i,i) <= to_signed(4096,16);
            W_head(i, i mod VOCAB_W) <= to_signed(4096,16);
        end loop;
        tok_emb(0) <= to_signed(1024,16);
        tok_emb(1) <= to_signed(2048,16);
        start<='1'; wait until rising_edge(clk);
        start<='0';
        wait until done='1';
        wait for 100 ns;
        assert false report "simulation finished" severity note;
        wait;
    end process;
end architecture;
