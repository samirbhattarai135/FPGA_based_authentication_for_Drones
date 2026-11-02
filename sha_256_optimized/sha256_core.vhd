----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
--
-- Module Name: sha256_core - rtl
-- Target Devices: Xilinx Artix-7 (Nexys A7-100T)
-- Description: SHA-256 compression engine (FIPS 180-4) that retires one round
--              per clock.
--
--   * Message schedule: a 16-word sliding window. W[t+16] depends only on
--     W[t..t+14], so the 64-word schedule never has to exist at once. The window
--     shifts every round while the digest runs, so schedule generation and the
--     rounds share the same 64 cycles.
--   * Round path: h + K[t] + W[t] and d + h + K[t] + W[t] are summed one round
--     early (the next round's h is this round's g, and its d is this round's c).
--     The new e is then a three-operand sum and the new a a five-operand sum.
--     Both are reduced with carry-save adders (XOR and majority in LUTs), so each
--     costs one 32-bit carry chain instead of two to four chained adders.
--
--   Latency, start -> done: 66 cycles (1 load + 64 rounds + 1 final add).
--   Multi-block messages: assert first_block on block 0 only; later blocks
--   chain from the digest held in this core.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha_256_pkg.all;

entity sha256_core is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;                       -- synchronous, active high
        start       : in  std_logic;                       -- one-cycle pulse; ignored while busy
        first_block : in  std_logic;                       -- '1': start from the FIPS initial hash value
        block_in    : in  std_logic_vector(511 downto 0);  -- word 0 in bits 511..480 (big-endian)
        busy        : out std_logic;
        done        : out std_logic;                       -- one-cycle pulse when digest is valid
        digest      : out std_logic_vector(255 downto 0)   -- H0 in bits 255..224; held until next start
    );
end sha256_core;

architecture rtl of sha256_core is
    subtype word is unsigned(31 downto 0);
    type word_array is array (natural range <>) of word;

    constant K : word_array(0 to 63) := (
        x"428a2f98", x"71374491", x"b5c0fbcf", x"e9b5dba5", x"3956c25b", x"59f111f1", x"923f82a4", x"ab1c5ed5",
        x"d807aa98", x"12835b01", x"243185be", x"550c7dc3", x"72be5d74", x"80deb1fe", x"9bdc06a7", x"c19bf174",
        x"e49b69c1", x"efbe4786", x"0fc19dc6", x"240ca1cc", x"2de92c6f", x"4a7484aa", x"5cb0a9dc", x"76f988da",
        x"983e5152", x"a831c66d", x"b00327c8", x"bf597fc7", x"c6e00bf3", x"d5a79147", x"06ca6351", x"14292967",
        x"27b70a85", x"2e1b2138", x"4d2c6dfc", x"53380d13", x"650a7354", x"766a0abb", x"81c2c92e", x"92722c85",
        x"a2bfe8a1", x"a81a664b", x"c24b8b70", x"c76c51a3", x"d192e819", x"d6990624", x"f40e3585", x"106aa070",
        x"19a4c116", x"1e376c08", x"2748774c", x"34b0bcb5", x"391c0cb3", x"4ed8aa4a", x"5b9cca4f", x"682e6ff3",
        x"748f82ee", x"78a5636f", x"84c87814", x"8cc70208", x"90befffa", x"a4506ceb", x"bef9a3f7", x"c67178f2");

    constant H_INIT : word_array(0 to 7) := (
        x"6a09e667", x"bb67ae85", x"3c6ef372", x"a54ff53a", x"510e527f", x"9b05688c", x"1f83d9ab", x"5be0cd19");

    -- The package functions work on std_logic_vector; these keep the datapath in unsigned.
    function s0_up(x : word) return word is begin return unsigned(SIGMA_UCASE_0(std_logic_vector(x))); end;
    function s1_up(x : word) return word is begin return unsigned(SIGMA_UCASE_1(std_logic_vector(x))); end;
    function s0_lo(x : word) return word is begin return unsigned(SIGMA_LCASE_0(std_logic_vector(x))); end;
    function s1_lo(x : word) return word is begin return unsigned(SIGMA_LCASE_1(std_logic_vector(x))); end;
    function ch_f (x, y, z : word) return word is begin return (x and y) xor ((not x) and z); end;
    function maj_f(x, y, z : word) return word is begin return (x and y) xor (x and z) xor (y and z); end;

    -- Carry-save addition: three operands become two (sum, carry) with no carry chain,
    -- so a sum of n operands needs n - 2 LUT levels and a single carry-chain adder.
    type sum_carry is record
        s : word;
        c : word;
    end record;
    function csa(x, y, z : word) return sum_carry is
    begin
        return (s => x xor y xor z, c => shift_left(maj_f(x, y, z), 1));
    end;
    function add3(x, y, z : word) return word is
        variable r : sum_carry;
    begin
        r := csa(x, y, z);
        return r.s + r.c;
    end;
    function add4(x, y, z, u : word) return word is
        variable r : sum_carry;
    begin
        r := csa(x, y, z);
        r := csa(r.s, r.c, u);
        return r.s + r.c;
    end;
    function add5(x, y, z, u, v : word) return word is
        variable r : sum_carry;
    begin
        r := csa(x, y, z);
        r := csa(r.s, r.c, u);
        r := csa(r.s, r.c, v);
        return r.s + r.c;
    end;

    type state_t is (IDLE, ROUNDS, FINAL);
    signal state : state_t := IDLE;

    signal a, b, c, d, e, f, g, h : word := (others => '0');
    signal hkw    : word := (others => '0');                  -- h + K[t] + W[t] for the current round
    signal dhkw   : word := (others => '0');                  -- d + h + K[t] + W[t]
    signal w      : word_array(0 to 15) := (others => (others => '0'));  -- w(i) holds W[t+i]
    signal hv     : word_array(0 to 7) := H_INIT;             -- chaining value / digest
    signal round  : unsigned(5 downto 0) := (others => '0');
    signal done_r : std_logic := '0';
begin
    busy   <= '0' when state = IDLE else '1';
    done   <= done_r;
    digest_gen : for i in 0 to 7 generate
        digest(255 - 32*i downto 224 - 32*i) <= std_logic_vector(hv(i));
    end generate;

    process(clk)
        variable base   : word_array(0 to 7);
        variable s1e, che : word;
    begin
        if rising_edge(clk) then
            done_r <= '0';
            if rst = '1' then
                state <= IDLE;
                hv    <= H_INIT;
            else
                case state is
                    when IDLE =>
                        if start = '1' then
                            if first_block = '1' then base := H_INIT; else base := hv; end if;
                            hv <= base;
                            a <= base(0); b <= base(1); c <= base(2); d <= base(3);
                            e <= base(4); f <= base(5); g <= base(6); h <= base(7);
                            for i in 0 to 15 loop
                                w(i) <= unsigned(block_in(511 - 32*i downto 480 - 32*i));
                            end loop;
                            hkw   <= add3(base(7), K(0), unsigned(block_in(511 downto 480)));
                            dhkw  <= add4(base(3), base(7), K(0), unsigned(block_in(511 downto 480)));
                            round <= (others => '0');
                            state <= ROUNDS;
                        end if;

                    when ROUNDS =>
                        -- T1 = h + S1(e) + Ch(e,f,g) + K[t] + W[t];  T2 = S0(a) + Maj(a,b,c)
                        s1e := s1_up(e);
                        che := ch_f(e, f, g);
                        h <= g;  g <= f;  f <= e;  e <= add3(dhkw, s1e, che);                          -- d + T1
                        d <= c;  c <= b;  b <= a;  a <= add5(hkw, s1e, che, s0_up(a), maj_f(a, b, c));  -- T1 + T2
                        -- Next round's h is this round's g and its d is this round's c; W[t+1] is w(1).
                        -- K wraps harmlessly after round 63.
                        hkw  <= add3(g, K(to_integer(round + 1)), w(1));
                        dhkw <= add4(c, g, K(to_integer(round + 1)), w(1));
                        for i in 0 to 14 loop
                            w(i) <= w(i + 1);
                        end loop;
                        w(15) <= add4(s1_lo(w(14)), w(9), s0_lo(w(1)), w(0));
                        round <= round + 1;
                        if round = 63 then
                            state <= FINAL;
                        end if;

                    when FINAL =>
                        hv(0) <= hv(0) + a;  hv(1) <= hv(1) + b;  hv(2) <= hv(2) + c;  hv(3) <= hv(3) + d;
                        hv(4) <= hv(4) + e;  hv(5) <= hv(5) + f;  hv(6) <= hv(6) + g;  hv(7) <= hv(7) + h;
                        done_r <= '1';
                        state  <= IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;
