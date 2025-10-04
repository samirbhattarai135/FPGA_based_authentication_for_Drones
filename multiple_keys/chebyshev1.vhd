----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06/23/2025 01:32:35 PM
-- Design Name: 
-- Module Name: generate_key - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity chebyshev1 is
     Port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        x      : in  integer;
        n      : in  integer;
        done   : out std_logic;
        result : out integer
    );
end chebyshev1;

architecture Behavioral of chebyshev1 is

    -- Iterative Chebyshev polynomial function (T_n) for scaled inputs
    -- FPGA-synthesizable version with fixed loop bounds
    function chebyshev_iterative(x_in: integer; n_in: integer) return integer is
        variable T0 : integer := 1000;      -- T0 = 1, scaled by 1000
        variable T1 : integer := x_in;      -- T1 = x, already scaled
        variable Tn : integer := 0;
        constant MAX_ORDER : integer := 100; -- Maximum Chebyshev order
    begin
        if n_in = 0 then
            return T0;  -- Return 1000 (representing 1.0)
        elsif n_in = 1 then
            return T1;  -- Return scaled x
        else
            -- For T2(x) = 2x² - 1, we need: T2 = 2*x*T1 - T0
            -- Since our inputs are scaled by 1000, we need to handle the scaling properly
            -- Use fixed range for FPGA synthesis, but only compute up to n_in
            for idx in 2 to MAX_ORDER loop
                if idx <= n_in then
                    -- Tn = 2 * x * T1 - T0, but account for scaling
                    -- x and T1 are scaled by 1000, so x*T1 is scaled by 1000000
                    -- We need to divide by 1000 to get back to 1000x scaling
                    Tn := (2 * x_in * T1) / 1000 - T0;
                    T0 := T1;
                    T1 := Tn;
                end if;
            end loop;
            return T1;
        end if;
    end function chebyshev_iterative;

begin
    process(clk, rst)
        variable start_prev : std_logic := '0';
        variable compute_done : std_logic := '0';
    begin
        if rst = '1' then
            result <= 0;
            done   <= '0';
            start_prev := '0';
            compute_done := '0';
        elsif rising_edge(clk) then
            -- Detect rising edge of start signal
            if start = '1' and start_prev = '0' then
                -- Start computation on rising edge
                result <= chebyshev_iterative(x, n);
                done   <= '1';
                compute_done := '1';
            elsif start = '0' then
                -- Clear done when start goes low
                done <= '0';
                compute_done := '0';
            elsif compute_done = '1' then
                -- Keep done high while start is high
                done <= '1';
            end if;
            
            start_prev := start;
        end if;
    end process;

end Behavioral;
