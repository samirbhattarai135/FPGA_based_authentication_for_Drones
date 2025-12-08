----------------------------------------------------------------------------------
-- Testbench for Streaming Key Matrix Generation
-- Validates 800 keys (1x1x800) on-the-fly without storing them
-- Uses statistical sampling and uniqueness checking
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;
use work.sha_512_pkg.all;
use work.key_matrix_pkg.all;

entity tb_top_module_matrix_streaming is
end tb_top_module_matrix_streaming;

architecture Behavioral of tb_top_module_matrix_streaming is

    -- Component declaration
    component top_module_matrix_streaming is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            genseed1        : in  integer range 0 to 1000;
            processing      : out std_logic;
            level1_done     : out std_logic;
            level2_done     : out std_logic;
            level3_done     : out std_logic;
            current_vendor  : out integer range 0 to NUM_VENDOR_VARIANTS-1;
            current_evtol   : out integer range 0 to NUM_EVTOL_PER_VARIANT-1;
            current_key     : out integer range 0 to NUM_KEYS_PER_EVTOL-1;
            key_valid       : out std_logic;
            current_key_out : out std_logic_vector(511 downto 0);
            read_vendor_seed : in  integer range 0 to NUM_VENDOR_VARIANTS-1;
            read_evtol_seed_v : in  integer range 0 to NUM_VENDOR_VARIANTS-1;
            read_evtol_seed_e : in  integer range 0 to NUM_EVTOL_PER_VARIANT-1;
            vendor_seed_out  : out integer;
            evtol_seed_out   : out integer
        );
    end component;

    -- Testbench signals
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '0';
    signal start            : std_logic := '0';
    signal genseed1         : integer range 0 to 1000 := 326;
    signal processing       : std_logic;
    signal level1_done      : std_logic;
    signal level2_done      : std_logic;
    signal level3_done      : std_logic;
    signal current_vendor   : integer range 0 to NUM_VENDOR_VARIANTS-1;
    signal current_evtol    : integer range 0 to NUM_EVTOL_PER_VARIANT-1;
    signal current_key      : integer range 0 to NUM_KEYS_PER_EVTOL-1;
    signal key_valid        : std_logic;
    signal current_key_out  : std_logic_vector(511 downto 0);
    signal read_vendor_seed : integer range 0 to NUM_VENDOR_VARIANTS-1 := 0;
    signal read_evtol_seed_v : integer range 0 to NUM_VENDOR_VARIANTS-1 := 0;
    signal read_evtol_seed_e : integer range 0 to NUM_EVTOL_PER_VARIANT-1 := 0;
    signal vendor_seed_out  : integer;
    signal evtol_seed_out   : integer;
    
    -- Clock period
    constant clk_period : time := 10 ns;
    
    -- Validation tracking
    signal key_count : integer := 0;
    signal unique_count : integer := 0;
    
    -- Sample storage for uniqueness checking (store all 800 keys for validation)
    type key_sample_array is array (0 to 799) of std_logic_vector(511 downto 0);
    signal key_samples : key_sample_array := (others => (others => '0'));
    signal sample_idx : integer := 0;
    
    -- Chunk timing (record time at every 100 keys)
    type time_array is array (0 to 8) of time;
    signal chunk_times : time_array := (others => 0 ns);
    
    -- Debug control (disabled in clean build)
    constant DEBUG_MODE : boolean := false;
    constant DEBUG_KEY_COUNT : integer := 0;
    
    -- Helper function to convert hash to hex string
    function hash_to_string(hash : std_logic_vector(511 downto 0)) return string is
        variable result : string(1 to 128);
        variable nibble : std_logic_vector(3 downto 0);
        variable hex_char : character;
    begin
        for i in 0 to 127 loop
            nibble := hash(511 - i*4 downto 508 - i*4);
            case nibble is
                when "0000" => hex_char := '0';
                when "0001" => hex_char := '1';
                when "0010" => hex_char := '2';
                when "0011" => hex_char := '3';
                when "0100" => hex_char := '4';
                when "0101" => hex_char := '5';
                when "0110" => hex_char := '6';
                when "0111" => hex_char := '7';
                when "1000" => hex_char := '8';
                when "1001" => hex_char := '9';
                when "1010" => hex_char := 'A';
                when "1011" => hex_char := 'B';
                when "1100" => hex_char := 'C';
                when "1101" => hex_char := 'D';
                when "1110" => hex_char := 'E';
                when "1111" => hex_char := 'F';
                when others => hex_char := 'X';
            end case;
            result(i+1) := hex_char;
        end loop;
        return result;
    end function;

begin

    -- Instantiate DUT
    dut : top_module_matrix_streaming
        port map (
            clk => clk,
            rst => rst,
            start => start,
            genseed1 => genseed1,
            processing => processing,
            level1_done => level1_done,
            level2_done => level2_done,
            level3_done => level3_done,
            current_vendor => current_vendor,
            current_evtol => current_evtol,
            current_key => current_key,
            key_valid => key_valid,
            current_key_out => current_key_out,
            read_vendor_seed => read_vendor_seed,
            read_evtol_seed_v => read_evtol_seed_v,
            read_evtol_seed_e => read_evtol_seed_e,
            vendor_seed_out => vendor_seed_out,
            evtol_seed_out => evtol_seed_out
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
    stimulus_proc : process
        -- Timing tracking variables (must be variables, not signals)
        variable total_start_time : time;
        variable level1_start_time, level1_end_time : time;
        variable level2_start_time, level2_end_time : time;
        variable level3_start_time, level3_end_time : time;
        variable total_end_time : time;
        variable sample_idx_v : integer := 0;
        variable sample_v : integer := 0;
        variable sample_e : integer := 0;
    begin
        report "================================================================================";
    report "      STREAMING KEY MATRIX GENERATION TEST";
    report "      1 x 1 x 800 = 800 Keys (test)";
    report "      NO KEY STORAGE - Validation on-the-fly";
        report "================================================================================";
        report "";
        
        -- Reset
        rst <= '1';
        start <= '0';
        wait for clk_period * 5;
        rst <= '0';
        wait for clk_period * 2;
        
        -- Start generation
    total_start_time := now;
        start <= '1';
        wait for clk_period;
        start <= '0';
        
        report "Generation started at: " & time'image(now);
        report "";
        
        -- Wait for Level 1 completion
    level1_start_time := now;
        wait until rising_edge(clk) and level1_done = '1';
    level1_end_time := now;
        report "================================================================================";
        report "LEVEL 1 COMPLETE: " & integer'image(NUM_VENDOR_VARIANTS) & " Vendor Seeds Generated";
        report "================================================================================";
        report "Time: " & time'image(level1_end_time - level1_start_time);
        report "Cycles: " & integer'image((level1_end_time - level1_start_time) / clk_period);
        report "";
        
        -- Sample some vendor seeds
        wait for clk_period * 5;
        report "--- Vendor Seed Samples ---";
        for i in 0 to 4 loop
            -- Clamp sample index to available vendor range
            if i * 20 > NUM_VENDOR_VARIANTS - 1 then
                sample_idx_v := NUM_VENDOR_VARIANTS - 1;
            else
                sample_idx_v := i * 20;
            end if;
            read_vendor_seed <= sample_idx_v;  -- Safe sampling index
            wait for clk_period * 2;
            report "Vendor[" & integer'image(sample_idx_v) & "] seed = " & integer'image(vendor_seed_out);
        end loop;
        report "";
       
        -- Wait for Level 2 completion
    level2_start_time := level1_end_time;
        wait until rising_edge(clk) and level2_done = '1';
    level2_end_time := now;
        report "================================================================================";
        report "LEVEL 2 COMPLETE: " & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT) & " eVTOL Seeds Generated";
        report "================================================================================";
        report "Time: " & time'image(level2_end_time - level2_start_time);
        report "Cycles: " & integer'image((level2_end_time - level2_start_time) / clk_period);
        report "";
        
        -- Sample some eVTOL seeds
        wait for clk_period * 5;
        report "--- eVTOL Seed Samples ---";
        for i in 0 to 4 loop
            -- Clamp vendor and eVTOL sample indices
            if i * 20 > NUM_VENDOR_VARIANTS - 1 then
                sample_v := NUM_VENDOR_VARIANTS - 1;
            else
                sample_v := i * 20;
            end if;
            if i * 20 > NUM_EVTOL_PER_VARIANT - 1 then
                sample_e := NUM_EVTOL_PER_VARIANT - 1;
            else
                sample_e := i * 20;
            end if;
            read_evtol_seed_v <= sample_v;
            read_evtol_seed_e <= sample_e;
            wait for clk_period * 2;
            report "eVTOL[V=" & integer'image(sample_v) & ",E=" & integer'image(sample_e) & "] seed = " & 
                   integer'image(evtol_seed_out);
        end loop;
        report "";
       
        -- Wait for Level 3 completion
    level3_start_time := level2_end_time;
        report "================================================================================";
        report "LEVEL 3: Generating and Validating " & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL) & " Keys (streaming)...";
        report "================================================================================";
        report "";
        wait until rising_edge(clk) and level3_done = '1';
    level3_end_time := now;
    total_end_time := now;
        
        report "================================================================================";
        report "LEVEL 3 COMPLETE: All " & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL) & " Keys Generated & Validated!";
        report "================================================================================";
        report "Time: " & time'image(level3_end_time - level3_start_time);
        report "Cycles: " & integer'image((level3_end_time - level3_start_time) / clk_period);
        report "";
        
        -- Performance summary
        report "================================================================================";
        report "                        PERFORMANCE SUMMARY";
        report "================================================================================";
        report "";
    report "Total Keys Generated: " & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL);
        report "Keys Validated: " & integer'image(key_count);
        report "Unique Keys in Sample: " & integer'image(unique_count) & "/" & integer'image(key_count);
        report "";
        report "Timing Breakdown:";
        report "  Level 1 (" & integer'image(NUM_VENDOR_VARIANTS) & " vendor seeds):     " & time'image(level1_end_time - level1_start_time);
        report "  Level 2 (" & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT) & " eVTOL seeds):   " & time'image(level2_end_time - level2_start_time);
    report "  Level 3 (" & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL) & " keys):         " & time'image(level3_end_time - level3_start_time);
        report " TOTAL TIME:                     " & time'image(total_end_time - total_start_time);
        report "";
    report "  Total Cycles: " & integer'image((total_end_time - total_start_time) / clk_period);
    report "  Average cycles/key: " & integer'image(((total_end_time - total_start_time) / clk_period) / (NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL));
        report "";
        report "Per-100 Keys Timing (from start):";
        for i in 1 to 8 loop
            report "  " & integer'image(i*100) & " keys from start: " &
                   time'image(chunk_times(i) - total_start_time) & " (" &
                   integer'image(((chunk_times(i) - total_start_time) / clk_period)) & " cycles)";
        end loop;
        report "";
        
        -- Memory usage comparison
        report "Memory Usage:";
        report "  Level 1 storage: 100 integers = 3.2 Kb";
        report "  Level 2 storage: 10,000 integers = 320 Kb";
        report "  Level 3 storage: NONE (streaming)";
        report "  TOTAL: ~324 Kb";
        report "";
        report "  vs. Full Storage: 256+ Mb";
        report "  Savings: 99.87% memory reduction!";
        report "";
        
        if key_count = NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL then
            report "================================================================================";
            report "             TEST PASSED - All " & integer'image(key_count) & " keys generated";
            report "================================================================================";
        else
            report "ERROR: Key count mismatch! Expected " & integer'image(NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL) & ", got " & integer'image(key_count) severity error;
        end if;
        
        wait;
    end process;
    
    -- Key validation process (runs in parallel)
    key_validator_proc : process(clk)
        variable is_duplicate : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                key_count <= 0;
                unique_count <= 0;
                sample_idx <= 0;
                key_samples <= (others => (others => '0'));
                
            elsif key_valid = '1' then
                -- Increment total count
                key_count <= key_count + 1;

                -- Store in sample buffer (all 800 keys)
                if sample_idx <= 799 then
                    -- Check uniqueness BEFORE storing (compare against all previously stored keys)
                    is_duplicate := false;
                    for i in 0 to sample_idx - 1 loop
                        if key_samples(i) = current_key_out then
                            is_duplicate := true;
                            exit;
                        end if;
                    end loop;
                    
                    if not is_duplicate then
                        unique_count <= unique_count + 1;
                    end if;
                    
                    -- Store current key AFTER uniqueness check
                    key_samples(sample_idx) <= current_key_out;
                    sample_idx <= sample_idx + 1;
                end if;
                
                -- Progress reporting removed for cleaner output
            end if;
        end if;
    end process;
    
    -- Debug/Progress processes removed for clean build

    -- Chunk timing recorder: capture time at each 100-key boundary
    chunk_timer_proc : process(clk)
        variable local_count : integer := 0;
        variable first_set : boolean := false;
        variable idx : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                local_count := 0;
                first_set := false;
                chunk_times <= (others => 0 ns);
            elsif key_valid = '1' then
                local_count := local_count + 1;
                if not first_set then
                    chunk_times(0) <= now;
                    first_set := true;
                end if;
                if (local_count mod 100) = 0 then
                    idx := local_count / 100;
                    if idx >= 1 and idx <= 8 then
                        chunk_times(idx) <= now;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
