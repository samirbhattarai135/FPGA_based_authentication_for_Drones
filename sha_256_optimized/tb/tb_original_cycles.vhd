----------------------------------------------------------------------------------
-- Testbench: cycle count of the ORIGINAL design (../sha_256_implementation), the
-- baseline for the speedup in README.md. Its own testbench imports sha_512_pkg
-- and does not compile in that folder.
--
-- The original chebyshev1 overflows VHDL integer for any seed. Vivado xsim runs
-- through it; nvc stops, so run_sim.sh simulates it with 32-bit wraparound
-- (what the synthesized hardware does). The cycle count does not depend on the
-- Chebyshev values: chebyshev1 finishes in one clock whatever it computes.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.key_matrix_pkg.all;

entity tb_original_cycles is
end tb_original_cycles;

architecture sim of tb_original_cycles is
    constant CLK_PERIOD : time := 10 ns;

    signal clk, start : std_logic := '0';
    signal rst        : std_logic := '1';
    signal processing, l1_done, l2_done, l3_done, key_valid : std_logic;
    signal cur_v      : integer range 0 to NUM_VENDOR_VARIANTS-1;
    signal cur_e      : integer range 0 to NUM_EVTOL_PER_VARIANT-1;
    signal cur_k      : integer range 0 to NUM_KEYS_PER_EVTOL-1;
    signal key_out    : std_logic_vector(255 downto 0);
    signal vseed, eseed : integer;
    signal cycles     : natural := 0;
    signal key_count  : natural := 0;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.top_module_matrix_streaming
        port map (clk => clk, rst => rst, start => start, genseed1 => 500,
                  processing => processing, level1_done => l1_done, level2_done => l2_done,
                  level3_done => l3_done, current_vendor => cur_v, current_evtol => cur_e,
                  current_key => cur_k, key_valid => key_valid, current_key_out => key_out,
                  read_vendor_seed => 0, read_evtol_seed_v => 0, read_evtol_seed_e => 0,
                  vendor_seed_out => vseed, evtol_seed_out => eseed);

    process(clk)
    begin
        if rising_edge(clk) then
            if processing = '1' then
                cycles <= cycles + 1;
            end if;
            if key_valid = '1' then
                key_count <= key_count + 1;
            end if;
        end if;
    end process;

    process
    begin
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for 2 * CLK_PERIOD;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        wait until l3_done = '1' for 10 ms;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        report "RESULT original keys=" & integer'image(key_count) & " cycles=" & integer'image(cycles) &
               " cycles_per_key=" & integer'image(cycles / key_count) &
               " time_at_100MHz=" & time'image(cycles * CLK_PERIOD);
        std.env.finish;
    end process;
end sim;
