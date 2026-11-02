----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
--
-- Package Name: modp_pkg
-- Description: Arithmetic mod p = 2^31 - 1 (a Mersenne prime), shared by the
--              Chebyshev units.
--
--   2^31 = 1 (mod p), so reduction needs no divider. Each function below uses at
--   most one carry chain: the two candidate results are computed side by side
--   and a mux picks one, instead of compare-then-subtract. That keeps every
--   pipeline stage short enough for 100 MHz and above on Artix-7.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package modp_pkg is
    subtype residue is unsigned(30 downto 0);           -- canonical value in [0, p)
    subtype product is unsigned(61 downto 0);           -- a * b for a, b < p
    constant P     : residue := (others => '1');        -- 2^31 - 1
    constant ONE   : residue := to_unsigned(1, 31);

    -- Product -> residue. p_in < (2^31-1)^2, so lo + hi <= 2^32 - 3 < 2p.
    function fold(p_in : product) return residue;
    -- 2r mod p: a one-bit rotate, since 2^31 = 1 (mod p)
    function times2(r : residue) return residue;
    -- (a - b) mod p, with a, b < p
    function sub_mod(a, b : residue) return residue;
    -- (a + b) mod p, with a, b < p
    function add_mod(a, b : residue) return residue;
end package;

package body modp_pkg is
    function fold(p_in : product) return residue is
        variable lo, hi     : unsigned(31 downto 0);
        variable sum, sum1  : unsigned(31 downto 0);
    begin
        lo   := resize(p_in(30 downto 0), 32);
        hi   := resize(p_in(61 downto 31), 32);
        sum  := lo + hi;
        sum1 := lo + hi + 1;                -- carry-in; >= 2^31 exactly when sum >= p
        if sum1(31) = '1' then
            return sum1(30 downto 0);       -- sum - p
        else
            return sum(30 downto 0);
        end if;
    end function;

    function times2(r : residue) return residue is
    begin
        return r(29 downto 0) & r(30);
    end function;

    function sub_mod(a, b : residue) return residue is
        variable diff : unsigned(31 downto 0);
        variable wrap : unsigned(31 downto 0);
    begin
        diff := resize(a, 32) - resize(b, 32);
        wrap := resize(a, 32) + resize(not b, 32);      -- a - b + p, since p - b = not b
        if diff(31) = '1' then                          -- borrow: a < b
            return wrap(30 downto 0);
        else
            return diff(30 downto 0);
        end if;
    end function;

    function add_mod(a, b : residue) return residue is
        variable sum, sum1 : unsigned(31 downto 0);
    begin
        sum  := resize(a, 32) + resize(b, 32);
        sum1 := resize(a, 32) + resize(b, 32) + 1;
        if sum1(31) = '1' then
            return sum1(30 downto 0);
        else
            return sum(30 downto 0);
        end if;
    end function;
end package body;
