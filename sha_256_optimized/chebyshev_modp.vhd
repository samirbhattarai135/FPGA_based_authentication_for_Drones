----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
--
-- Module Name: chebyshev_modp - rtl
-- Target Devices: Xilinx Artix-7 (Nexys A7-100T)
-- Description: Chebyshev polynomial T_n(x) mod p, with p = 2^31 - 1, for any n.
--
--   The original chebyshev1 evaluated T_n over 32-bit integers: values overflowed
--   after a few iterations, and the degree was capped at 32, so every key with
--   k >= 30 received the same T value. Working mod a prime is the standard
--   integer form of Chebyshev-map cryptography: values stay in [0, p), any
--   degree is valid, and the semigroup property T_m(T_n(x)) = T_mn(x) holds.
--
--   Fast doubling walks the bits of n from the MSB down, keeping (T_k, T_k+1):
--     T_2k   = 2*T_k^2 - 1
--     T_2k+1 = 2*T_k*T_k+1 - x
--     T_2k+2 = 2*T_k+1^2 - 1
--   Each step is four pipeline stages: multiply, multiply output register
--   (absorbed into the DSP48), fold, finish. Latency is 4*N_BITS + 1 cycles for
--   any n. This unit only builds the vendor and eVTOL seeds; the streamed keys
--   use the one-multiply recurrence in chebyshev_stream.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.modp_pkg.all;

entity chebyshev_modp is
    generic (
        N_BITS : positive := 10                       -- width of the degree input
    );
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;                       -- synchronous, active high
        start  : in  std_logic;                       -- one-cycle pulse; ignored while busy
        x      : in  residue;
        n      : in  unsigned(N_BITS-1 downto 0);
        busy   : out std_logic;
        done   : out std_logic;                       -- one-cycle pulse
        result : out residue                          -- T_n(x) mod p, held until next start
    );
end chebyshev_modp;

architecture rtl of chebyshev_modp is
    type state_t is (IDLE, MUL, MUL_REG, FOLD_STAGE, FINISH);
    signal state   : state_t := IDLE;
    signal x_r     : residue := (others => '0');
    signal n_r     : unsigned(N_BITS-1 downto 0) := (others => '0');
    signal bit_i   : natural range 0 to N_BITS-1 := 0;
    signal tk      : residue := (others => '0');      -- T_k
    signal tk1     : residue := (others => '0');      -- T_k+1
    signal p_mix   : product := (others => '0');      -- T_k * T_k+1
    signal p_sq    : product := (others => '0');      -- T_k^2 or T_k+1^2, by bit
    signal p_mix_d : product := (others => '0');
    signal p_sq_d  : product := (others => '0');
    signal r_mix   : residue := (others => '0');
    signal r_sq    : residue := (others => '0');
    signal done_r  : std_logic := '0';
begin
    busy   <= '0' when state = IDLE else '1';
    done   <= done_r;
    result <= tk;

    process(clk)
        variable odd_term, even_term : residue;
    begin
        if rising_edge(clk) then
            done_r <= '0';
            if rst = '1' then
                state <= IDLE;
            else
                case state is
                    when IDLE =>
                        if start = '1' then
                            x_r   <= x;
                            n_r   <= n;
                            tk    <= ONE;
                            tk1   <= x;
                            bit_i <= N_BITS - 1;
                            state <= MUL;
                        end if;

                    when MUL =>
                        p_mix <= tk * tk1;
                        if n_r(bit_i) = '0' then
                            p_sq <= tk * tk;
                        else
                            p_sq <= tk1 * tk1;
                        end if;
                        state <= MUL_REG;

                    when MUL_REG =>
                        p_mix_d <= p_mix;
                        p_sq_d  <= p_sq;
                        state   <= FOLD_STAGE;

                    when FOLD_STAGE =>
                        r_mix <= fold(p_mix_d);
                        r_sq  <= fold(p_sq_d);
                        state <= FINISH;

                    when FINISH =>
                        odd_term  := sub_mod(times2(r_mix), x_r);    -- T_2k+1
                        even_term := sub_mod(times2(r_sq), ONE);     -- T_2k or T_2k+2
                        if n_r(bit_i) = '0' then
                            tk  <= even_term;
                            tk1 <= odd_term;
                        else
                            tk  <= odd_term;
                            tk1 <= even_term;
                        end if;
                        if bit_i = 0 then
                            done_r <= '1';
                            state  <= IDLE;
                        else
                            bit_i <= bit_i - 1;
                            state <= MUL;
                        end if;
                end case;
            end if;
        end if;
    end process;
end rtl;
