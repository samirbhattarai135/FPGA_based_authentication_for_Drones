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
    -- State machine for iterative computation
    type state_type is (IDLE, COMPUTING, DONE_STATE);
    signal current_state : state_type := IDLE;
    
    -- Computation registers
    signal T0_reg : integer := 1000;
    signal T1_reg : integer := 0;
    signal iteration : integer range 0 to 100 := 0;
    signal target_n : integer range 0 to 100 := 0;
    signal x_stored : integer := 0;

begin
    process(clk, rst)
        variable Tn_temp : integer;
    begin
        if rst = '1' then
            result <= 0;
            done <= '0';
            current_state <= IDLE;
            T0_reg <= 1000;
            T1_reg <= 0;
            iteration <= 0;
            target_n <= 0;
            x_stored <= 0;
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    done <= '0';
                    if start = '1' then
                        -- Store inputs and initialize
                        x_stored <= x;
                        target_n <= n;
                        T0_reg <= 1000;  -- T0 = 1
                        T1_reg <= x;     -- T1 = x
                        iteration <= 0;
                        
                        -- Handle special cases immediately
                        if n = 0 then
                            result <= 1000;
                            current_state <= DONE_STATE;
                        elsif n = 1 then
                            result <= x;
                            current_state <= DONE_STATE;
                        else
                            iteration <= 2;
                            current_state <= COMPUTING;
                        end if;
                    end if;
                
                when COMPUTING =>
                    -- Compute one iteration: Tn = 2*x*T1 - T0
                    Tn_temp := (2 * x_stored * T1_reg) / 1000 - T0_reg;
                    T0_reg <= T1_reg;
                    T1_reg <= Tn_temp;
                    
                    if iteration >= target_n then
                        result <= Tn_temp;
                        current_state <= DONE_STATE;
                    else
                        iteration <= iteration + 1;
                    end if;
                
                when DONE_STATE =>
                    done <= '1';
                    if start = '0' then
                        current_state <= IDLE;
                    end if;
                    
            end case;
        end if;
    end process;

end Behavioral;
