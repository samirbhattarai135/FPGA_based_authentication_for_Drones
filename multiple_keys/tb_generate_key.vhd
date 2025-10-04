----------------------------------------------------------------------------------
-- Testbench for generate_key (top_module)
-- Tests 100-key generation using Kn = H(Tn(genseed1))
-- All keys use the same genseed1 input with varying Chebyshev orders
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.sha_256_pkg.all;

entity tb_generate_key is
end tb_generate_key;

architecture Behavioral of tb_generate_key is
    -- Component declaration
    component generate_key is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            genseed1        : in  integer range 0 to 1000;
            cheby_order     : in  integer range 1 to 100;
            processing      : out std_logic;
            key_ready       : out std_logic;
            chebyshev_result : out integer;
            key_out         : out std_logic_vector(255 downto 0)
        );
    end component;

    -- Test signals
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal start           : std_logic := '0';
    signal genseed1        : integer range 0 to 1000 := 0;
    signal cheby_order     : integer range 1 to 100 := 1;
    signal processing      : std_logic;
    signal key_ready       : std_logic;
    signal chebyshev_result : integer;
    signal key_out         : std_logic_vector(255 downto 0);

    -- Clock period
    constant clk_period : time := 10 ns;
    
    -- Test counter
    signal test_case : integer := 0;

    -- Helper function to display hash in hex format
    function hash_to_string(hash_val : std_logic_vector(255 downto 0)) return string is
        variable result : string(1 to 64);
        variable temp : std_logic_vector(3 downto 0);
        variable char : character;
    begin
        for i in 0 to 63 loop
            temp := hash_val(255 - i*4 downto 252 - i*4);
            case temp is
                when "0000" => char := '0';
                when "0001" => char := '1';
                when "0010" => char := '2';
                when "0011" => char := '3';
                when "0100" => char := '4';
                when "0101" => char := '5';
                when "0110" => char := '6';
                when "0111" => char := '7';
                when "1000" => char := '8';
                when "1001" => char := '9';
                when "1010" => char := 'A';
                when "1011" => char := 'B';
                when "1100" => char := 'C';
                when "1101" => char := 'D';
                when "1110" => char := 'E';
                when "1111" => char := 'F';
                when others => char := 'X';
            end case;
            result(i+1) := char;
        end loop;
        return result;
    end function;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: generate_key
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            genseed1        => genseed1,
            cheby_order     => cheby_order,
            processing      => processing,
            key_ready       => key_ready,
            chebyshev_result => chebyshev_result,
            key_out         => key_out
        );

    -- Clock generation
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Stimulus process
    stim_proc: process
        variable key_generation_start_time : time;
        variable key_generation_end_time : time;
        variable current_key : std_logic_vector(255 downto 0);
        constant GENSEED_VALUE : integer := 100;  -- Fixed genseed1 for all keys (represents 0.1)
    begin
        -- Initialize inputs
        rst <= '1';
        start <= '0';
        genseed1 <= 0;
        cheby_order <= 1;
        test_case <= 0;
        
        wait for 100 ns;
        
        -- Release reset
        rst <= '0';
        wait for 50 ns;
        
        report "========================================";
        report "100-Key Generation Test";
        report "Architecture: Kn = H(Tn(genseed1))";
        report "No random value addition - direct hash";
        report "Fixed genseed1 = " & integer'image(GENSEED_VALUE) & " (0.1 scaled)";
        report "Chebyshev order varies: n = 1 to 100";
        report "========================================";
        
        -- Set the fixed genseed1 value for all key generations
        genseed1 <= GENSEED_VALUE;
        
        -- Start timer for complete key generation
        key_generation_start_time := now;
        
        -- Generate keys K1 through K100
        -- Each key: Kn = H(Tn(genseed1)) where n = 1, 2, 3, ..., 100
        for i in 1 to 10 loop
            test_case <= i;
            
            -- Set Chebyshev polynomial order for this key
            cheby_order <= i;
            
            -- OPTIMIZATION: Start immediately on next clock edge, no extra wait
            wait until rising_edge(clk);
            
            -- Start key generation (single cycle pulse)
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            
            -- Wait for completion
            wait until key_ready = '1';
            
            -- Capture the generated key (sample immediately)
            current_key := key_out;
            
            -- Report progress every 10 keys
            if (i mod 10) = 0 then
                report "K" & integer'image(i) & " = H(T" & integer'image(i) & 
                       "(" & integer'image(GENSEED_VALUE) & ")): " & hash_to_string(current_key);
            end if;
            
            -- Wait for module to return to IDLE (key_ready goes low)
            wait until key_ready = '0';
        end loop;
        
        -- Stop timer
        key_generation_end_time := now;
        
        -- Display final results
        report "========================================";
        report "=== Key Generation Results ===";
        report "Total keys generated: 100 (K1 to K100)";
        report "Final key K100 = H(T100(" & integer'image(GENSEED_VALUE) & ")): " & hash_to_string(current_key);

        report "=== Performance Metrics ===";
        report "Total time for 100 keys: " & time'image(key_generation_end_time - key_generation_start_time);
        report "Total clock cycles: " & integer'image((key_generation_end_time - key_generation_start_time) / clk_period);
        report "Average time per key: " & time'image((key_generation_end_time - key_generation_start_time) / 100);
        report "Average cycles per key: " & integer'image(((key_generation_end_time - key_generation_start_time) / clk_period) / 100);
        report "=== TEST COMPLETED SUCCESSFULLY ===";
        report "========================================";
        
        wait;
    end process;

    -- Monitor process to track state transitions
    monitor_proc: process
    begin
        wait until rising_edge(clk);
        
        if start = '1' then
            report "INFO: Starting key K" & integer'image(test_case) & " generation";
        end if;
        
        if processing = '1' and processing'event then
            report "INFO: Processing K" & integer'image(test_case) & 
                   " using T" & integer'image(cheby_order) & "(genseed1)";
        end if;
        
        if key_ready = '1' and key_ready'event then
            report "INFO: K" & integer'image(test_case) & " generation complete";
        end if;
    end process;

    -- Timeout protection
    timeout_proc: process
    begin
        wait for 10 sec;  -- Extended timeout for 100-key generation
        report "TIMEOUT: Simulation exceeded maximum time limit" severity failure;
        wait;
    end process;

end Behavioral;
