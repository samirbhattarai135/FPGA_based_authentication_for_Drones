----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
-- 
-- Create Date: 06/23/2025 01:32:35 PM
-- Design Name: 
-- Module Name: generate_key - Behavioral
-- Project Name: FPGA-based Key Generation for Drones
-- Target Devices: Xilinx Artix-7
-- Tool Versions: Vivado 2024.1
-- Description:
-- 
-- Dependencies: Numeric_STD, STD_LOGIC_1164, Sha_256_pkg, Key_Matrix_pkg, 
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

    -- Iterative Chebyshev polynomial function (T_n) for integer inputs
    -- x_in is treated as an integer value (not scaled by 1000)
    -- Results are also integers (not scaled)
    function chebyshev_iterative(x_in: integer; n_in: integer) return integer is
        constant MAX_N : integer := 32;     -- Maximum supported polynomial degree
        variable T0 : integer := 1;         -- T0(x) = 1
        variable T1 : integer := x_in;      -- T1(x) = x
        variable Tn : integer := 0;
    begin
        if n_in = 0 then
            return 1;  -- Return 1 (T0 = 1)
        elsif n_in = 1 then
            return x_in;  -- Return x (T1 = x)
        else
            -- Recurrence: T_n(x) = 2x·T_{n-1}(x) - T_{n-2}(x)
            -- For integer inputs (no scaling needed)
            for idx in 2 to MAX_N loop
                exit when idx > n_in;
                Tn := 2 * x_in * T1 - T0;
                T0 := T1;
                T1 := Tn;
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
