----------------------------------------------------------------------------------
-- Testbench: sha256_core against FIPS 180-4 example vectors ("abc", the empty
-- message, and the 448-bit two-block message). Also checks the 66-cycle latency.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sha256_core is
end tb_sha256_core;

architecture sim of tb_sha256_core is
    constant CLK_PERIOD : time := 10 ns;
    constant LATENCY    : natural := 66;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal start       : std_logic := '0';
    signal first_block : std_logic := '1';
    signal block_in    : std_logic_vector(511 downto 0) := (others => '0');
    signal busy, done  : std_logic;
    signal digest      : std_logic_vector(255 downto 0);
    signal failures    : natural := 0;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.sha256_core
        port map (clk => clk, rst => rst, start => start, first_block => first_block,
                  block_in => block_in, busy => busy, done => done, digest => digest);

    process
        procedure hash_block(blk : std_logic_vector(511 downto 0); first : std_logic) is
            variable cycles : natural := 0;
        begin
            block_in    <= blk;
            first_block <= first;
            start       <= '1';
            wait until rising_edge(clk);
            start <= '0';
            loop
                wait until rising_edge(clk);
                cycles := cycles + 1;
                exit when done = '1';
            end loop;
            if cycles /= LATENCY then
                report "latency " & integer'image(cycles) & " cycles, expected " & integer'image(LATENCY) severity error;
                failures <= failures + 1;
            end if;
        end procedure;

        procedure check(name : string; expected : std_logic_vector(255 downto 0)) is
        begin
            if digest = expected then
                report "PASS " & name & " = " & to_hstring(digest);
            else
                report "FAIL " & name & ": got " & to_hstring(digest) & ", expected " & to_hstring(expected) severity error;
                failures <= failures + 1;
            end if;
        end procedure;
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        hash_block(x"61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018", '1');
        check("abc", x"BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD");

        hash_block(x"80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", '1');
        check("empty", x"E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855");

        hash_block(x"6162636462636465636465666465666765666768666768696768696A68696A6B696A6B6C6A6B6C6D6B6C6D6E6C6D6E6F6D6E6F706E6F70718000000000000000", '1');
        hash_block(x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001C0", '0');
        check("two-block 448-bit", x"248D6A61D20638B8E5C026930C3E6039A33CE45964FF2167F6ECEDD419DB06C1");

        wait until rising_edge(clk);
        if failures = 0 then
            report "ALL SHA-256 VECTORS PASSED (latency " & integer'image(LATENCY) & " cycles per block)";
        else
            report integer'image(failures) & " CHECK(S) FAILED" severity failure;
        end if;
        std.env.finish;
    end process;
end sim;
