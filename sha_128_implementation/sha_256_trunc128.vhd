library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha_256_pkg.all;

entity sha_256_trunc128 is
    generic(
        RESET_VALUE : std_logic := '0'
    );
    port(
        clk          : in  std_logic;
        rst          : in  std_logic;
        data_ready   : in  std_logic;
        n_blocks     : in  natural;
        msg_block_in : in  std_logic_vector(0 to (16 * WORD_SIZE)-1);
        finished     : out std_logic;
        data_out     : out std_logic_vector(127 downto 0)
    );
end entity;

architecture rtl of sha_256_trunc128 is
    signal full_digest : std_logic_vector((WORD_SIZE * 8)-1 downto 0);
begin
    core: entity work.sha_256
        generic map (
            RESET_VALUE => RESET_VALUE
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_ready   => data_ready,
            n_blocks     => n_blocks,
            msg_block_in => msg_block_in,
            finished     => finished,
            data_out     => full_digest
        );

    -- Truncate SHA-256 to 128 bits (take high 128 bits)
    data_out <= full_digest(255 downto 128);
end architecture;