----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/19/2025 
-- Design Name: 
-- Module Name: top_module - Behavioral
-- Project Name: eVTOL Key Generation with SHA-256
-- Target Devices: Xilinx FPGA
-- Tool Versions: Vivado 2020.1+
-- Description: Top module that combines Chebyshev polynomial calculation
--              with SHA-256 hashing for cryptographic key generation
-- 
-- Dependencies: chebyshev1.vhd, sha_256.vhd, sha_256_pkg.vhd
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments: Based on research paper key generation scheme
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sha_256_pkg.all;

entity generate_key is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        start           : in  std_logic;
        
        -- Key Generation inputs: Kn = H(Tn(genseed1))
        genseed1        : in  integer range 0 to 1000;  -- GenSeed1 as decimal 0-1 (scaled by 1000)
        cheby_order     : in  integer range 1 to 100;   -- Chebyshev polynomial order (n)
        
        -- Control and status
        processing      : out std_logic;             -- High when computation is in progress
        key_ready       : out std_logic;             -- High when key is ready
        
        -- Outputs
        chebyshev_result : out integer;              -- Raw Chebyshev result (Tn(GenSeed1))
        key_out         : out std_logic_vector(255 downto 0)  -- Final key Kn (256-bit hash)
    );
end generate_key;

architecture Behavioral of generate_key is

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
    
    component sha_256 is
        generic(
            RESET_VALUE : std_logic := '0'
        );
        port(
            clk : in std_logic;
            rst : in std_logic;
            data_ready : in std_logic;
            n_blocks : in natural;
            msg_block_in : in std_logic_vector(0 to (16 * WORD_SIZE)-1);
            finished : out std_logic;
            data_out : out std_logic_vector((WORD_SIZE * 8)-1 downto 0)
        );
    end component;

    -- State machine for key generation: Kn = H(Tn(genseed1))
    -- Optimized for minimum latency
    type state_type is (
        IDLE,
        CHEBYSHEV_COMPUTE,      -- Computing Tn(GenSeed1)
        SHA_COMPUTE             -- Computing SHA-256 hash of Chebyshev result
    );
    
    signal current_state : state_type;
    signal next_state    : state_type;
    
    -- Chebyshev signals
    signal cheby_start   : std_logic;
    signal cheby_done    : std_logic;
    signal cheby_result  : integer;
    signal cheby_x_input : integer;
    signal cheby_n_order : integer;  -- Variable order from input port
    
    -- SHA-256 signals
    signal sha_start     : std_logic;
    signal sha_finished  : std_logic;
    signal sha_data_in   : std_logic_vector(0 to (16 * WORD_SIZE)-1);
    signal sha_result    : std_logic_vector((WORD_SIZE * 8)-1 downto 0);
    signal sha_started   : std_logic;   
    
    -- Internal signals
    signal hash_input_ready : std_logic;
    
    -- Convert integer to 32-bit std_logic_vector for hashing
    function int_to_slv32(int_val : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(int_val, 32));
    end function;

begin

    -- Instantiate Chebyshev polynomial calculator
    chebyshev_inst : chebyshev1
        port map (
            clk    => clk,
            rst    => rst,
            start  => cheby_start,
            x      => cheby_x_input,
            n      => cheby_n_order,
            done   => cheby_done,
            result => cheby_result
        );

    -- Instantiate SHA-256 hash function
    sha256_inst : sha_256
        generic map (
            RESET_VALUE => '1'  -- Match our active-high reset system
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_ready   => sha_start,
            n_blocks     => 1,               
            msg_block_in => sha_data_in,
            finished     => sha_finished,
            data_out     => sha_result
        );

    -- State machine process
    state_machine : process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(clk) then
            current_state <= next_state;
        end if;
    end process;

    -- Next state logic for optimized architecture
    next_state_logic : process(current_state, start, cheby_done, sha_finished)
    begin
        case current_state is
            when IDLE =>
                if start = '1' then
                    next_state <= CHEBYSHEV_COMPUTE;
                else
                    next_state <= IDLE;
                end if;
                
            when CHEBYSHEV_COMPUTE =>
                if cheby_done = '1' then
                    next_state <= SHA_COMPUTE;  -- Jump directly to SHA computation
                else
                    next_state <= CHEBYSHEV_COMPUTE;
                end if;

            when SHA_COMPUTE =>
                if sha_finished = '1' then
                    next_state <= IDLE;  -- Return directly to IDLE, no intermediate states
                else
                    next_state <= SHA_COMPUTE;
                end if;
                
            when others =>
                next_state <= IDLE;
        end case;
    end process;

    -- Control signal generation - MAXIMUM SPEED OPTIMIZATION
    -- Key optimization: Start SHA in the same cycle Chebyshev finishes
    control_signals : process(clk, rst)
        variable cheby_started : std_logic := '0';
    begin
        if rst = '1' then
            cheby_start <= '0';
            sha_start <= '0';
            sha_started <= '0';
            hash_input_ready <= '0';
            cheby_x_input <= 0;
            cheby_n_order <= 2;
            cheby_started := '0';
        elsif rising_edge(clk) then
            -- Default values
            cheby_start <= '0';
            sha_start <= '0';
            
            case current_state is
                when IDLE =>
                    cheby_x_input <= genseed1;      -- Set input
                    cheby_n_order <= cheby_order;   -- Set order
                    sha_started <= '0';
                    cheby_started := '0';
                    hash_input_ready <= '0';
                    
                when CHEBYSHEV_COMPUTE =>
                    -- Start Chebyshev computation with a single pulse
                    if cheby_started = '0' then
                        cheby_start <= '1';
                        cheby_started := '1';
                    end if;
                    
                    -- CRITICAL OPTIMIZATION: Start SHA immediately when Chebyshev finishes
                    -- This saves 1 clock cycle by not waiting for state transition
                    if cheby_done = '1' then
                        hash_input_ready <= '1';
                        sha_start <= '1';       -- Start SHA in same cycle
                        sha_started <= '1';     -- Mark as started
                    end if;
                    
                when SHA_COMPUTE =>
                    hash_input_ready <= '0';
                    -- SHA already started in previous state, just wait for completion
                    
                when others =>
                    hash_input_ready <= '0';
            end case;
        end if;
    end process;

    -- Prepare SHA-256 input data: H(Tn(GenSeed1))
    -- Direct hash of Chebyshev result without adding random value
    sha_input_preparation : process(clk, rst)
        variable temp_block : std_logic_vector(0 to (16 * WORD_SIZE)-1);
    begin
        if rst = '1' then
            sha_data_in <= (others => '0');
        elsif rising_edge(clk) then
            if hash_input_ready = '1' then
                -- Initialize with zeros
                temp_block := (others => '0');
                
                -- Word 0: Tn(GenSeed1) - direct Chebyshev result
                temp_block(0 to 31) := int_to_slv32(cheby_result);
                
                -- Word 1: GenSeed1 for additional entropy
                temp_block(32 to 63) := int_to_slv32(genseed1);
                
                -- Word 2: Chebyshev order for differentiation
                temp_block(64 to 95) := int_to_slv32(cheby_order);
                
                -- Word 3: SHA-256 padding start
                temp_block(96 to 127) := x"80000000";
                
                -- Words 4-13: Padding (zeros) - already initialized
                
                -- Word 14: High 32 bits of message length (always 0)
                temp_block(448 to 479) := (others => '0');
                
                -- Word 15: Low 32 bits of message length in bits (3 * 32 = 96 bits)
                temp_block(480 to 511) := std_logic_vector(to_unsigned(96, 32));
                
                sha_data_in <= temp_block;
            end if;
        end if;
    end process;

    -- Output assignments - optimized
    output_assignment : process(clk, rst)
    begin
        if rst = '1' then
            processing <= '0';
            key_ready <= '0';
            chebyshev_result <= 0;
            key_out <= (others => '0');
        elsif rising_edge(clk) then
            case current_state is
                when IDLE =>
                    processing <= '0';
                    key_ready <= '0';  -- Always clear in IDLE
                    
                when CHEBYSHEV_COMPUTE =>
                    processing <= '1';
                    key_ready <= '0';
                    
                when SHA_COMPUTE =>
                    processing <= '1';
                    if sha_finished = '1' then
                        -- Output ready in the same cycle SHA finishes
                        key_ready <= '1';
                        chebyshev_result <= cheby_result;
                        key_out <= sha_result;
                    else
                        key_ready <= '0';
                    end if;
                    
                when others =>
                    processing <= '0';
                    key_ready <= '0';
            end case;
        end if;
    end process;

end Behavioral;