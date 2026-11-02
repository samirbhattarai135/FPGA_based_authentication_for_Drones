----------------------------------------------------------------------------------
-- Testbench: key_stream_top. Generates the full key set, writes each key to
-- keys_out.txt as "v e k HEX" for model/key_model.py --check, and reports the
-- cycle count from start to level3_done.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.key_matrix_pkg.all;

entity tb_key_stream is
    generic (
        NUM_CORES : positive := 2;
        GENSEED   : natural  := 500
    );
end tb_key_stream;

architecture sim of tb_key_stream is
    constant CLK_PERIOD : time := 10 ns;

    signal clk, start : std_logic := '0';
    signal rst        : std_logic := '1';
    signal processing, l1_done, l2_done, l3_done, key_valid : std_logic;
    signal key_out    : std_logic_vector(255 downto 0);
    signal key_vendor : natural range 0 to NUM_VENDOR_VARIANTS-1;
    signal key_evtol  : natural range 0 to NUM_EVTOL_PER_VARIANT-1;
    signal key_index  : natural range 0 to NUM_KEYS_PER_EVTOL-1;
    signal cycles     : natural := 0;
    signal key_count  : natural := 0;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.key_stream_top
        generic map (NUM_CORES => NUM_CORES)
        port map (clk => clk, rst => rst, start => start, genseed => GENSEED,
                  processing => processing, level1_done => l1_done, level2_done => l2_done,
                  level3_done => l3_done, key_valid => key_valid, key_out => key_out,
                  key_vendor => key_vendor, key_evtol => key_evtol, key_index => key_index);

    -- Count every cycle from the start pulse until the last key is out.
    process(clk)
        file dump   : text open write_mode is "keys_out.txt";
        variable ln : line;
    begin
        if rising_edge(clk) then
            if processing = '1' then
                cycles <= cycles + 1;
            end if;
            if key_valid = '1' then
                key_count <= key_count + 1;
                write(ln, integer'image(key_vendor) & " " & integer'image(key_evtol) & " " &
                          integer'image(key_index) & " " & to_hstring(key_out));
                writeline(dump, ln);
            end if;
        end if;
    end process;

    process
        constant TOTAL : natural := NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL;
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until l3_done = '1' for 10 ms;
        -- The last key is counted on the edge after level3_done rises; let that settle.
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        assert l3_done = '1' report "timed out before level3_done" severity failure;
        assert key_count = TOTAL
            report "emitted " & integer'image(key_count) & " keys, expected " & integer'image(TOTAL) severity failure;
        report "RESULT cores=" & integer'image(NUM_CORES) & " keys=" & integer'image(key_count) &
               " cycles=" & integer'image(cycles) &
               " cycles_per_key=" & integer'image(cycles / key_count) &
               " time_at_100MHz=" & time'image(cycles * CLK_PERIOD);
        std.env.finish;
    end process;
end sim;
