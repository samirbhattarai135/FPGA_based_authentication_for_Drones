----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
--
-- Module Name: chebyshev_stream - rtl
-- Target Devices: Xilinx Artix-7 (Nexys A7-100T)
-- Description: Streams T_2(x), T_3(x), T_4(x), ... mod p = 2^31 - 1.
--
--   Keys k = 0, 1, 2, ... need T_{k+2} of the same eVTOL seed, one degree apart,
--   so the three-term recurrence T_{m+1} = 2*x*T_m - T_{m-1} produces each one
--   from the previous two with a single modular multiply. Fast doubling would
--   need ten steps per key. Each value takes four pipelined cycles: multiply,
--   multiply register (absorbed into the DSP48), fold, finish. That is far below
--   the 66 cycles a SHA core spends per key.
--
--   load: restart the sequence for a new seed x (sets T_0 = 1, T_1 = x).
--   step: produce the next value; the first step after load yields T_2(x).
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.modp_pkg.all;

entity chebyshev_stream is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;                       -- synchronous, active high
        load   : in  std_logic;                       -- one-cycle pulse; ignored while busy
        x      : in  residue;
        step   : in  std_logic;                       -- one-cycle pulse; ignored while busy or loading
        busy   : out std_logic;
        done   : out std_logic;                       -- one-cycle pulse per step
        result : out residue                          -- latest value, held until the next step
    );
end chebyshev_stream;

architecture rtl of chebyshev_stream is
    type state_t is (IDLE, MUL, MUL_REG, FOLD_STAGE, FINISH);
    signal state  : state_t := IDLE;
    signal x_r    : residue := (others => '0');
    signal prev   : residue := (others => '0');       -- T_{m-1}
    signal cur    : residue := (others => '0');       -- T_m
    signal prod   : product := (others => '0');
    signal prod_d : product := (others => '0');
    signal r_prod : residue := (others => '0');
    signal done_r : std_logic := '0';
begin
    busy   <= '0' when state = IDLE else '1';
    done   <= done_r;
    result <= cur;

    process(clk)
    begin
        if rising_edge(clk) then
            done_r <= '0';
            if rst = '1' then
                state <= IDLE;
            else
                case state is
                    when IDLE =>
                        if load = '1' then
                            x_r  <= x;
                            prev <= ONE;
                            cur  <= x;
                        elsif step = '1' then
                            state <= MUL;
                        end if;

                    when MUL =>
                        prod  <= x_r * cur;
                        state <= MUL_REG;

                    when MUL_REG =>
                        prod_d <= prod;
                        state  <= FOLD_STAGE;

                    when FOLD_STAGE =>
                        r_prod <= fold(prod_d);
                        state  <= FINISH;

                    when FINISH =>
                        prev   <= cur;
                        cur    <= sub_mod(times2(r_prod), prev);
                        done_r <= '1';
                        state  <= IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;
