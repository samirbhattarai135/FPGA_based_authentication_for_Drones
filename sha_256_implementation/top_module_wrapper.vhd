----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
--
-- Create Date: 01/29/2026
-- Design Name: FPGA-based Key Generation for Drones
-- Module Name: top_module_wrapper - Behavioral
-- Project Name: eVTOL Key Matrix Generation - Hardware Wrapper
-- Target Devices: Nexys4 DDR (Artix-7)
-- Tool Versions: Vivado 2020.1+
-- Description: Wrapper module that converts between std_logic_vector (for FPGA pins)
--              and integer types (used by top_module_matrix_streaming internally)
--              This is a minimal wrapper with only constrained ports for implementation.
--
-- Pin Mapping:
--   Inputs:  Switches for genseed1, Buttons for rst/start
--   Outputs: LEDs for status
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sha_256_pkg.all;
use work.key_matrix_pkg.all;

entity top_module_wrapper is
    port (
        -- Clock and control
        clk             : in  std_logic;
        rst             : in  std_logic;
        start           : in  std_logic;

        -- Initial seed input (10 bits for range 0-1000)
        genseed1        : in  std_logic_vector(9 downto 0);

        -- Status outputs (directly usable as std_logic)
        processing      : out std_logic;
        level1_done     : out std_logic;
        level2_done     : out std_logic;
        level3_done     : out std_logic;
        key_valid       : out std_logic
    );
end top_module_wrapper;

architecture Behavioral of top_module_wrapper is

    -- Component declaration for the core module
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
            current_key_out : out std_logic_vector(255 downto 0);
            read_vendor_seed  : in  integer range 0 to NUM_VENDOR_VARIANTS-1;
            read_evtol_seed_v : in  integer range 0 to NUM_VENDOR_VARIANTS-1;
            read_evtol_seed_e : in  integer range 0 to NUM_EVTOL_PER_VARIANT-1;
            vendor_seed_out   : out integer;
            evtol_seed_out    : out integer
        );
    end component;

    -- Internal signals for integer interface to core module
    signal genseed1_int        : integer range 0 to 1000;

    -- Unused outputs from core (directly connected but not exposed)
    signal current_vendor_int  : integer range 0 to NUM_VENDOR_VARIANTS-1;
    signal current_evtol_int   : integer range 0 to NUM_EVTOL_PER_VARIANT-1;
    signal current_key_int     : integer range 0 to NUM_KEYS_PER_EVTOL-1;
    signal current_key_out_int : std_logic_vector(255 downto 0);
    signal vendor_seed_out_int : integer;
    signal evtol_seed_out_int  : integer;

begin

    -- Instantiate the core module
    core_inst : top_module_matrix_streaming
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            genseed1        => genseed1_int,
            processing      => processing,
            level1_done     => level1_done,
            level2_done     => level2_done,
            level3_done     => level3_done,
            current_vendor  => current_vendor_int,
            current_evtol   => current_evtol_int,
            current_key     => current_key_int,
            key_valid       => key_valid,
            current_key_out => current_key_out_int,
            read_vendor_seed  => 0,  -- Tie to constant (not used)
            read_evtol_seed_v => 0,  -- Tie to constant (not used)
            read_evtol_seed_e => 0,  -- Tie to constant (not used)
            vendor_seed_out   => vendor_seed_out_int,
            evtol_seed_out    => evtol_seed_out_int
        );

    -- Input conversion: std_logic_vector -> integer
    genseed1_int <= to_integer(unsigned(genseed1));

end Behavioral;
