----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10/13/2025 
-- Design Name: 
-- Module Name: top_module_matrix_streaming - Behavioral
-- Project Name: eVTOL Key Matrix Generation - STREAMING VERSION
-- Target Devices: Xilinx FPGA
-- Tool Versions: Vivado 2020.1+
-- Description: Optimized for 100x100x100 key generation WITHOUT storing all keys
--              Keys are streamed out as generated - testbench validates on-the-fly
--              Only Level 1 & 2 seeds are stored (as integers for efficiency)
-- 
-- Memory Usage:
--   Level 1: 100 vendor seeds × 32 bits = 3.2 Kb
--   Level 2: 10,000 eVTOL seeds × 32 bits = 320 Kb
--   Level 3: NO STORAGE (streaming output)
--   Total: ~324 Kb (vs 256+ Mb with full storage)
--
-- Architecture:
--   Level 1: Generate 100 Vendor Seeds using Rv
--   Level 2: Generate 10,000 eVTOL Seeds using Rev  
--   Level 3: Stream 1,000,000 Keys as generated (no storage)
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sha_256_pkg.all;
use work.key_matrix_pkg.all;

entity top_module_matrix_streaming is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        start           : in  std_logic;
        
        -- Initial seed input
        genseed1        : in  integer range 0 to 1000;
        
        -- Control and status
        processing      : out std_logic;
        level1_done     : out std_logic;
        level2_done     : out std_logic;
        level3_done     : out std_logic;
        
        -- Progress indicators
        current_vendor  : out integer range 0 to NUM_VENDOR_VARIANTS-1;
        current_evtol   : out integer range 0 to NUM_EVTOL_PER_VARIANT-1;
        current_key     : out integer range 0 to NUM_KEYS_PER_EVTOL-1;
        
        -- STREAMING OUTPUT (no storage, keys output as generated)
    key_valid       : out std_logic;  -- High when current_key_out is valid
    current_key_out : out std_logic_vector(127 downto 0);  -- Current generated key (SHA-256 truncated to 128)
        
        -- Seed read interface (for verification)
        read_vendor_seed : in  integer range 0 to NUM_VENDOR_VARIANTS-1;
        read_evtol_seed_v : in  integer range 0 to NUM_VENDOR_VARIANTS-1;
        read_evtol_seed_e : in  integer range 0 to NUM_EVTOL_PER_VARIANT-1;
        vendor_seed_out  : out integer;
        evtol_seed_out   : out integer
    );
end top_module_matrix_streaming;

architecture Behavioral of top_module_matrix_streaming is

    -- Integer array types for efficient seed storage (streaming version)
    type vendor_seed_array_int is array (0 to NUM_VENDOR_VARIANTS-1) of integer;
    type evtol_seed_matrix_int is array (0 to NUM_VENDOR_VARIANTS-1, 0 to NUM_EVTOL_PER_VARIANT-1) of integer;

    -- Component declarations
    component chebyshev1 is
        port (
            clk    : in  std_logic;
            rst    : in  std_logic;
            start  : in  std_logic;
            x      : in  integer;
            n      : in  integer;
            done   : out std_logic;
            result : out integer
        );
    end component;
   
    component sha_256_trunc128 is
        generic(
            RESET_VALUE : std_logic := '0'
        );
        port(
            clk : in std_logic;
            rst : in std_logic;
            data_ready : in std_logic;  -- the edge of this signal triggers capture and hashing
            n_blocks : in natural; -- number of padded message blocks
            msg_block_in : in std_logic_vector(0 to (16 * WORD_SIZE)-1);
            finished : out std_logic;
            data_out : out std_logic_vector(127 downto 0)
        );
    end component;

    -- State machine
    type state_type is (
        IDLE,
        LEVEL1_CHEBY_COMPUTE,
        LEVEL1_ADD_RANDOM,
        LEVEL1_STORE,
        LEVEL2_CHEBY_COMPUTE,
        LEVEL2_ADD_RANDOM,
        LEVEL2_STORE,
        LEVEL3_CHEBY_WAIT,     -- Wait for Chebyshev to be ready
        LEVEL3_CHEBY_COMPUTE,
        LEVEL3_SHA_COMPUTE,
        LEVEL3_STREAM,  -- Stream key out instead of storing
        COMPLETE
    );
    
    signal current_state, next_state : state_type;
    
    -- Chebyshev signals
    signal cheby_start   : std_logic;
    signal cheby_done    : std_logic;
    signal cheby_x       : integer;
    signal cheby_n       : integer;
    signal cheby_result  : integer;
    
    -- Hashing signals
    signal sha_start     : std_logic;
    signal sha_start_edge : std_logic := '0';  -- Edge-triggered pulse for SHA
    signal sha_finished  : std_logic;
    signal sha_finished_edge : std_logic := '0'; -- Rising edge of SHA finished
    signal sha_data_in   : std_logic_vector(0 to (16 * WORD_SIZE)-1); -- 512-bit block for SHA-256
    signal sha_result    : std_logic_vector(127 downto 0); -- 128-bit result (truncated SHA-256)
   
    -- Seed storage arrays (ONLY Level 1 & 2 - integers only)
    signal vendor_seeds  : vendor_seed_array_int := (others => 0);
    signal evtol_seeds   : evtol_seed_matrix_int := (others => (others => 0));
    -- NO key_matrix storage!
   
    -- Loop counters
    signal v_idx : integer range 0 to NUM_VENDOR_VARIANTS - 1 := 0;
    signal e_idx : integer range 0 to NUM_EVTOL_PER_VARIANT - 1 := 0;
    signal k_idx : integer range 0 to NUM_KEYS_PER_EVTOL - 1 := 0;
    
    -- Internal control signals
    signal hash_input_ready : std_logic;
    signal start_latched    : std_logic;
    signal level3_cheby_started : std_logic := '0';
    signal level3_sha_started : std_logic := '0';  
    signal level3_first_key : std_logic := '1';  
    signal level3_counters_updated : std_logic := '0';  
    signal sha_input_prepared : std_logic := '0';  
    
    -- Constants random values  for hierarchical key generation
    constant Rv  : integer := 134;  
    constant Rev : integer := 256; 
    
    -- Intermediate computation values
    signal current_seed_value   : integer;
    signal temp_cheby_result    : integer;  -- Store Chebyshev result before adding random

begin

    -- Component instantiations
    chebyshev_inst : chebyshev1
        port map (
            clk    => clk,
            rst    => rst,
            start  => cheby_start,
            x      => cheby_x,
            n      => cheby_n,
            done   => cheby_done,
            result => cheby_result
        );
    
    sha256_inst : sha_256_trunc128
        generic map (
            RESET_VALUE => '1'  -- Match top-level active-high reset
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_ready   => sha_start_edge,  -- Use edge-triggered signal
            n_blocks     => 1,
            msg_block_in => sha_data_in,
            finished     => sha_finished,
            data_out     => sha_result
        );

    -- Output progress indicators
    current_vendor <= v_idx;
    current_evtol  <= e_idx;
    current_key    <= k_idx;
    
    -- Seed read interface
    vendor_seed_out <= vendor_seeds(read_vendor_seed);
    evtol_seed_out <= evtol_seeds(read_evtol_seed_v, read_evtol_seed_e);
    
    -- Directly drive output from sha_result when valid

    -- State register
    process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            start_latched <= '0';
        elsif rising_edge(clk) then
            current_state <= next_state;
            if start = '1' then
                start_latched <= '1';
            elsif current_state = IDLE then
                start_latched <= '0';
            end if;
        end if;
    end process;
   
    -- Next state logic
    process(current_state, start_latched, cheby_done, sha_finished, sha_finished_edge,
        v_idx, e_idx, k_idx, hash_input_ready)
    begin
        next_state <= current_state;
        
        case current_state is
            when IDLE =>
                if start_latched = '1' then
                    next_state <= LEVEL1_CHEBY_COMPUTE;
                end if;
                
            -- LEVEL 1: Vendor Seed Generation
            when LEVEL1_CHEBY_COMPUTE =>
                if cheby_done = '1' then
                    next_state <= LEVEL1_ADD_RANDOM;
                end if;
                
            when LEVEL1_ADD_RANDOM =>
                next_state <= LEVEL1_STORE;
                
            when LEVEL1_STORE =>
                if v_idx < NUM_VENDOR_VARIANTS - 1 then
                    next_state <= LEVEL1_CHEBY_COMPUTE;
                else
                    next_state <= LEVEL2_CHEBY_COMPUTE;
                end if;
                
            -- LEVEL 2: eVTOL Seed Generation
            when LEVEL2_CHEBY_COMPUTE =>
                if cheby_done = '1' then
                    next_state <= LEVEL2_ADD_RANDOM;
                end if;
                
            when LEVEL2_ADD_RANDOM =>
                next_state <= LEVEL2_STORE;
                
            when LEVEL2_STORE =>
                if e_idx < NUM_EVTOL_PER_VARIANT - 1 then
                    next_state <= LEVEL2_CHEBY_COMPUTE;
                elsif v_idx < NUM_VENDOR_VARIANTS - 1 then
                    next_state <= LEVEL2_CHEBY_COMPUTE;
                else
                    next_state <= LEVEL3_CHEBY_WAIT;
                end if;
                
            -- LEVEL 3: Key Generation (STREAMING - no storage)
            when LEVEL3_CHEBY_WAIT =>
                if cheby_done = '0' then
                    next_state <= LEVEL3_CHEBY_COMPUTE;
                end if;
                
            when LEVEL3_CHEBY_COMPUTE =>
                -- Only proceed to SHA if we started AND completed a computation
                if cheby_done = '1' and level3_cheby_started = '1' then
                    next_state <= LEVEL3_SHA_COMPUTE;
                end if;
                
            when LEVEL3_SHA_COMPUTE =>
                if sha_finished_edge = '1' and level3_sha_started = '1' then
                    next_state <= LEVEL3_STREAM;
                end if;
                
            when LEVEL3_STREAM =>
                -- Check completion
                if k_idx = NUM_KEYS_PER_EVTOL - 1 and 
                   e_idx = NUM_EVTOL_PER_VARIANT - 1 and 
                   v_idx = NUM_VENDOR_VARIANTS - 1 then
                    next_state <= COMPLETE;
                else
                    next_state <= LEVEL3_CHEBY_WAIT;  -- Go through WAIT state to reset signals
                end if;
                
            when COMPLETE =>
                next_state <= COMPLETE;
                
        end case;
    end process;
    
    -- Output logic and control
    process(clk, rst)
    begin
        if rst = '1' then
            processing <= '0';
            level1_done <= '0';
            level2_done <= '0';
            level3_done <= '0';
            key_valid <= '0';
            v_idx <= 0;
            e_idx <= 0;
            k_idx <= 0;
            cheby_start <= '0';
            sha_start <= '0';
            current_seed_value <= 0;
            temp_cheby_result <= 0;
            level3_cheby_started <= '0';
            level3_sha_started <= '0';
            level3_first_key <= '1';
            level3_counters_updated <= '0';
            sha_input_prepared <= '0';
            
            
        elsif rising_edge(clk) then

            case current_state is
                when IDLE =>
                    processing <= '0';
                    level1_done <= '0';
                    level2_done <= '0';
                    level3_done <= '0';
                    v_idx <= 0;
                    e_idx <= 0;
                    k_idx <= 0;
                    cheby_start <= '0';
                    if start_latched = '1' then
                        processing <= '1';
                    end if;
                    
                -- LEVEL 1
                when LEVEL1_CHEBY_COMPUTE =>
                    if cheby_done = '0' then
                        cheby_x <= genseed1;
                        cheby_n <= v_idx + 2;  -- T2, T3, T4, ...
                        cheby_start <= '1';
                    elsif cheby_done = '1' then
                        -- Capture result when done
                        temp_cheby_result <= cheby_result;
                    end if;
                    
                when LEVEL1_ADD_RANDOM =>
                    -- Add Rv to Chebyshev result
                    current_seed_value <= temp_cheby_result + Rv;
                    
                when LEVEL1_STORE =>
                    vendor_seeds(v_idx) <= current_seed_value;
                    if v_idx < NUM_VENDOR_VARIANTS - 1 then
                        v_idx <= v_idx + 1;
                    else
                        level1_done <= '1';
                        v_idx <= 0;  -- Reset for Level 2
                    end if;
                    
                -- LEVEL 2
                when LEVEL2_CHEBY_COMPUTE =>
                    if cheby_done = '0' then
                        cheby_x <= vendor_seeds(v_idx);
                        cheby_n <= e_idx + 2;
                        cheby_start <= '1';
                    elsif cheby_done = '1' then
                        -- Capture result when done
                        temp_cheby_result <= cheby_result;
                    end if;
                    
                when LEVEL2_ADD_RANDOM =>
                    -- Add Rev to Chebyshev result
                    current_seed_value <= temp_cheby_result + Rev;
                    
                when LEVEL2_STORE =>
                    evtol_seeds(v_idx, e_idx) <= current_seed_value;
                    if e_idx < NUM_EVTOL_PER_VARIANT - 1 then
                        e_idx <= e_idx + 1;
                    elsif v_idx < NUM_VENDOR_VARIANTS - 1 then
                        e_idx <= 0;
                        v_idx <= v_idx + 1;
                    else
                        level2_done <= '1';
                        v_idx <= 0;
                        e_idx <= 0;
                    end if;
                    
                -- LEVEL 3 (STREAMING)
                when LEVEL3_CHEBY_WAIT =>

                    level3_cheby_started <= '0';
                    level3_sha_started <= '0';
                    cheby_start <= '0';
                    sha_start <= '0';
                    key_valid <= '0'; 
                    
                    if level3_counters_updated = '0' then
                        -- Haven't incremented yet in this WAIT session
                        if level3_first_key = '0' then
                            -- Not first key, so increment for next iteration
                            if k_idx < NUM_KEYS_PER_EVTOL - 1 then
                                k_idx <= k_idx + 1;
                            else
                                -- k_idx reached limit, wrap to next eVTOL or vendor
                                k_idx <= 0;
                                if e_idx < NUM_EVTOL_PER_VARIANT - 1 then
                                    e_idx <= e_idx + 1;
                                else
                                    -- e_idx reached limit, wrap to next vendor
                                    e_idx <= 0;
                                    if v_idx < NUM_VENDOR_VARIANTS - 1 then
                                        v_idx <= v_idx + 1;
                                    end if;
                                end if;
                            end if;
                        else
                            -- First key, don't increment, just clear the flag
                            level3_first_key <= '0';
                        end if;
                        -- Mark that we've updated counters
                        level3_counters_updated <= '1';
                    end if;


                when LEVEL3_CHEBY_COMPUTE =>
                    -- Capture Chebyshev result when computation completes
                    if cheby_done = '1' then
                        temp_cheby_result <= cheby_result;
                    end if;
                    

                    if level3_cheby_started = '0' and cheby_done = '0' then
                        -- Set inputs and trigger new computation
                        cheby_x <= evtol_seeds(v_idx, e_idx);
                        cheby_n <= k_idx + 2;  -- T2, T3, T4, T5, ... (k_idx=0→n=2, k_idx=1→n=3, etc.)
                        cheby_start <= '1';
                        level3_cheby_started <= '1';  -- Mark that we started this computation

                    elsif cheby_done = '1' and level3_cheby_started = '1' then
                        -- Computation complete - clear start to prepare for next iteration
                        cheby_start <= '0';  
                        
                    else
                        -- Keep cheby_start high while waiting for computation to complete
                        cheby_start <= '1';
                    end if;        
                            
                when LEVEL3_SHA_compute =>
                    -- Ensure cheby_start is clear (should already be clear from COMPUTE state)
                    cheby_start <= '0';
                    key_valid <= '0';  -- Keep key_valid low during SHA computation
                    
                    if level3_sha_started = '0' and hash_input_ready = '1' then
                        sha_start <= '1';
                        level3_sha_started <= '1';
                       
                    elsif level3_sha_started = '1' and sha_finished_edge = '1' then
                        -- SHA computation complete, capture result
                        sha_start <= '0';
                        current_key_out <= sha_result;
                       
                    else
                        -- Keep sha_start low while waiting
                        sha_start <= '0';
                    end if;
                   
                when LEVEL3_STREAM =>
                    key_valid <= '1';
                    sha_start <= '0';
                    
                    -- Clear the counters_updated flag to allow next increment in CHEBY_WAIT
                    level3_counters_updated <= '0';
                    
                when COMPLETE =>
                    processing <= '0';
                    level3_done <= '1';
                    key_valid <= '0';  -- Ensure key_valid is cleared
                    cheby_start <= '0';
                    sha_start <= '0';
                    
            end case;
        end if;
    end process;
  
    -- SHA-512 edge detection (convert sha_start to single-cycle pulse)
    process(clk, rst)
        variable sha_start_prev : std_logic := '0';
    begin
        if rst = '1' then
            sha_start_edge <= '0';
            sha_start_prev := '0';
        elsif rising_edge(clk) then
            -- Generate a single-cycle pulse on rising edge of sha_start
            if sha_start = '1' and sha_start_prev = '0' then
                sha_start_edge <= '1';
            else
                sha_start_edge <= '0';
            end if;
            sha_start_prev := sha_start;
        end if;
    end process;

    -- Detect rising edge of sha_finished to avoid capturing stale DONE
    process(clk, rst)
        variable sha_finished_prev : std_logic := '0';
    begin
        if rst = '1' then
            sha_finished_edge <= '0';
            sha_finished_prev := '0';
        elsif rising_edge(clk) then
            if sha_finished = '1' and sha_finished_prev = '0' then
                sha_finished_edge <= '1';
            else
                sha_finished_edge <= '0';
            end if;
            sha_finished_prev := sha_finished;
        end if;
    end process;
   
    -- SHA-512 input preparation
    process(clk, rst)
    begin
        if rst = '1' then
            sha_data_in <= (others => '0');
            hash_input_ready <= '0';

        elsif rising_edge(clk) then
        
            if current_state = LEVEL3_CHEBY_COMPUTE and cheby_done = '1' and sha_input_prepared = '0' then
                
                -- Prepare SHA input using current iteration's values - ONCE ONLY
                sha_data_in(0 to 31) <= std_logic_vector(to_signed(cheby_result, 32));
                sha_data_in(32 to 63) <= std_logic_vector(to_signed(v_idx, 32));
                sha_data_in(64 to 95) <= std_logic_vector(to_signed(e_idx, 32));
                sha_data_in(96 to 127) <= std_logic_vector(to_signed(k_idx, 32));
                sha_data_in(128 to 511) <= (others => '0');
                hash_input_ready <= '1';
                sha_input_prepared <= '1';  -- Mark as prepared

            elsif current_state = LEVEL3_SHA_COMPUTE then
                hash_input_ready <= '1';
                
            elsif current_state = LEVEL3_CHEBY_WAIT then
                hash_input_ready <= '0';
                sha_input_prepared <= '0';  -- Reset for next key
            else
                -- Clear ready flag in other states
                hash_input_ready <= '0';
            end if;
        end if;
    end process;

        -- Status outputs
    processing <= '1' when current_state /= IDLE and current_state /= COMPLETE else '0';
    level1_done <= '1' when (current_state = LEVEL2_CHEBY_COMPUTE or 
                             current_state = LEVEL2_ADD_RANDOM or 
                             current_state = LEVEL2_STORE or
                             current_state = LEVEL3_CHEBY_WAIT or
                             current_state = LEVEL3_CHEBY_COMPUTE or
                             current_state = LEVEL3_SHA_COMPUTE or
                             current_state = LEVEL3_STREAM or
                             current_state = COMPLETE) else '0';
                             
    level2_done <= '1' when (current_state = LEVEL3_CHEBY_WAIT or
                             current_state = LEVEL3_CHEBY_COMPUTE or
                             current_state = LEVEL3_SHA_COMPUTE or
                             current_state = LEVEL3_STREAM or
                             current_state = COMPLETE) else '0';
                             
    level3_done <= '1' when current_state = COMPLETE else '0';

end Behavioral;
