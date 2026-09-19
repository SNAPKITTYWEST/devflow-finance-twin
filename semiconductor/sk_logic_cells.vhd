-- =====================================================================
-- sk_logic_cells.vhd
-- SNAPKITTY SOVEREIGN HARDWARE
-- Recursive Logic -> VHDL -> ASIC Binding
-- IEEE 1076 / IEEE 1076-2008
-- No behavioral AI runtime. No assembler dependency.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =====================================================================
-- sk_logic_pkg : Boolean IR types and gate primitives
-- =====================================================================
package sk_logic_pkg is

    subtype bit1 is std_logic;

    type node_kind is (
        NK_CONST,
        NK_INPUT,
        NK_OUTPUT,
        NK_NOT,
        NK_NAND,
        NK_NOR,
        NK_AND,
        NK_OR,
        NK_XOR,
        NK_XNOR,
        NK_MUX,
        NK_DFF
    );

    type logic_node is record
        kind : node_kind;
        a    : natural;
        b    : natural;
        c    : natural;
        v    : bit1;
    end record;

    constant NODE_ZERO : logic_node :=
        (kind=>NK_CONST, a=>0, b=>0, c=>0, v=>'0');
    constant NODE_ONE  : logic_node :=
        (kind=>NK_CONST, a=>0, b=>0, c=>0, v=>'1');

    function sk_not (a    : bit1)             return bit1;
    function sk_nand(a, b : bit1)             return bit1;
    function sk_nor (a, b : bit1)             return bit1;
    function sk_and (a, b : bit1)             return bit1;
    function sk_or  (a, b : bit1)             return bit1;
    function sk_xor (a, b : bit1)             return bit1;
    function sk_xnor(a, b : bit1)             return bit1;
    function sk_mux (s, a, b : bit1)          return bit1;

end package;

package body sk_logic_pkg is
    function sk_not (a    : bit1)    return bit1 is begin return not a; end;
    function sk_nand(a, b : bit1)    return bit1 is begin return not(a and b); end;
    function sk_nor (a, b : bit1)    return bit1 is begin return not(a or b); end;
    function sk_and (a, b : bit1)    return bit1 is begin return a and b; end;
    function sk_or  (a, b : bit1)    return bit1 is begin return a or b; end;
    function sk_xor (a, b : bit1)    return bit1 is begin return a xor b; end;
    function sk_xnor(a, b : bit1)    return bit1 is begin return a xnor b; end;
    function sk_mux (s,a,b : bit1)   return bit1 is
    begin if s='0' then return a; else return b; end if; end;
end package body;

-- =====================================================================
-- Primitive cells — structural implementations (NAND/INV basis)
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;

entity sk_inv is port(A:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_inv is begin Y <= not A; end architecture;

entity sk_nand2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_nand2 is begin Y <= not(A and B); end architecture;

entity sk_nor2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_nor2 is begin Y <= not(A or B); end architecture;

entity sk_nand3 is port(A,B,C:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_nand3 is begin Y <= not(A and B and C); end architecture;

entity sk_nand4 is port(A,B,C,D:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_nand4 is begin Y <= not(A and B and C and D); end architecture;

-- =====================================================================
-- sk_and2 : NAND + INV
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_and2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_and2 is
    signal N0 : std_logic;
begin
    U0: entity work.sk_nand2 port map(A,B,N0);
    U1: entity work.sk_inv   port map(N0,Y);
end architecture;

-- =====================================================================
-- sk_or2 : De Morgan — NOT(NOT A NAND NOT B)
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_or2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_or2 is
    signal NA,NB : std_logic;
begin
    U0: entity work.sk_inv   port map(A,NA);
    U1: entity work.sk_inv   port map(B,NB);
    U2: entity work.sk_nand2 port map(NA,NB,Y);
end architecture;

-- =====================================================================
-- sk_xor2 : 4-NAND topology
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_xor2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_xor2 is
    signal N0,N1,N2 : std_logic;
begin
    N0 <= not(A and B);
    N1 <= not(A and N0);
    N2 <= not(B and N0);
    Y  <= not(N1 and N2);
end architecture;

-- =====================================================================
-- sk_xnor2
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_xnor2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_xnor2 is
    signal X : std_logic;
begin
    U0: entity work.sk_xor2 port map(A,B,X);
    U1: entity work.sk_inv  port map(X,Y);
end architecture;

-- =====================================================================
-- sk_mux2 : (A & NS) OR (B & S)
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_mux2 is port(S,A,B:in std_logic; Y:out std_logic); end entity;
architecture structural of sk_mux2 is
    signal NS,X0,X1 : std_logic;
begin
    U0: entity work.sk_inv  port map(S,NS);
    U1: entity work.sk_and2 port map(NS,A,X0);
    U2: entity work.sk_and2 port map(S,B,X1);
    U3: entity work.sk_or2  port map(X0,X1,Y);
end architecture;

-- =====================================================================
-- sk_dff : rising-edge D flip-flop (no reset)
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_dff is port(CLK,D:in std_logic; Q:out std_logic); end entity;
architecture sequential of sk_dff is
begin
    process(CLK) begin
        if rising_edge(CLK) then Q <= D; end if;
    end process;
end architecture;

-- =====================================================================
-- sk_recursive_nand : NAND chain of depth DEPTH
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_nand_recursive is
    generic(DEPTH : positive := 1);
    port(A,B:in std_logic; Y:out std_logic);
end entity;
architecture recursive of sk_nand_recursive is
    signal N0 : std_logic;
begin
    BASE: if DEPTH = 1 generate
        U: entity work.sk_nand2 port map(A,B,Y);
    end generate;
    STEP: if DEPTH > 1 generate
        CHILD: entity work.sk_nand_recursive
            generic map(DEPTH => DEPTH-1) port map(A,B,N0);
        U: entity work.sk_nand2 port map(N0,B,Y);
    end generate;
end architecture;

-- =====================================================================
-- sk_recursive_xor : recursive 4-NAND XOR of depth DEPTH
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_recursive_xor is
    generic(DEPTH : positive := 1);
    port(A,B:in std_logic; Y:out std_logic);
end entity;
architecture recursive of sk_recursive_xor is
    signal N0,N1,N2,CHILD_Y : std_logic;
begin
    BASE: if DEPTH = 1 generate
        N0 <= not(A and B);
        N1 <= not(A and N0);
        N2 <= not(B and N0);
        Y  <= not(N1 and N2);
    end generate;
    STEP: if DEPTH > 1 generate
        CX: entity work.sk_recursive_xor
            generic map(DEPTH => DEPTH-1) port map(A,B,CHILD_Y);
        N0 <= not(CHILD_Y and B);
        N1 <= not(A and CHILD_Y);
        Y  <= not(N0 and N1);
    end generate;
end architecture;

-- =====================================================================
-- sk_logic_cell : universal 1-bit cell, KIND selects function
-- KIND: 0=NOT  1=NAND  2=NOR  3=AND  4=OR  5=XOR  6=XNOR  7=MUX
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_logic_cell is
    generic(KIND : natural := 0);
    port(A,B,C:in std_logic; Y:out std_logic);
end entity;
architecture structural of sk_logic_cell is
begin
    K0: if KIND=0 generate Y<=not A; end generate;
    K1: if KIND=1 generate Y<=not(A and B); end generate;
    K2: if KIND=2 generate Y<=not(A or B); end generate;
    K3: if KIND=3 generate Y<=A and B; end generate;
    K4: if KIND=4 generate Y<=A or B; end generate;
    K5: if KIND=5 generate Y<=A xor B; end generate;
    K6: if KIND=6 generate Y<=A xnor B; end generate;
    K7: if KIND=7 generate Y<=(A and not C) or (B and C); end generate;
end architecture;

-- =====================================================================
-- sk_recursive_network : registered XOR over N-bit buses
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity sk_recursive_network is
    generic(NODES : positive := 16);
    port(CLK,RST : in std_logic;
         A,B     : in  std_logic_vector(NODES-1 downto 0);
         Y       : out std_logic_vector(NODES-1 downto 0));
end entity;
architecture structural of sk_recursive_network is
    signal state : std_logic_vector(NODES-1 downto 0);
begin
    process(CLK) begin
        if rising_edge(CLK) then
            if RST='1' then state<=(others=>'0');
            else             state<=A xor B;
            end if;
        end if;
    end process;
    Y <= state;
end architecture;

-- =====================================================================
-- ASIC boundary stubs — technology-independent
-- Replace architecture body with a standard-cell library binding
-- during technology mapping.
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;

entity sk_asic_nand2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture binding of sk_asic_nand2 is begin Y<=not(A and B); end architecture;

entity sk_asic_inv is port(A:in std_logic; Y:out std_logic); end entity;
architecture binding of sk_asic_inv is begin Y<=not A; end architecture;

entity sk_asic_xor2 is port(A,B:in std_logic; Y:out std_logic); end entity;
architecture binding of sk_asic_xor2 is
    signal N0,N1,N2 : std_logic;
begin
    N0<=not(A and B); N1<=not(A and N0); N2<=not(B and N0); Y<=not(N1 and N2);
end architecture;

-- =====================================================================
-- sk_top : XOR + register, demonstrating cell composition
-- =====================================================================
library ieee; use ieee.std_logic_1164.all;
entity sk_top is
    port(A,B,CLK,RST : in std_logic; Y : out std_logic);
end entity;
architecture structural of sk_top is
    signal XOR_Y, REG_Y : std_logic;
begin
    LOGIC: entity work.sk_asic_xor2
        port map(A=>A, B=>B, Y=>XOR_Y);
    REGISTER_0: entity work.sk_dff
        port map(CLK=>CLK, D=>XOR_Y, Q=>REG_Y);
    Y <= REG_Y;
end architecture;
