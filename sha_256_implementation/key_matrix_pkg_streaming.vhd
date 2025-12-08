----------------------------------------------------------------------------------
-- Package for Key Matrix Data Types - STREAMING VERSION
-- Optimized for large-scale simulation (100x100x100 = 1M keys)
-- Does NOT store all keys - uses streaming validation instead
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package key_matrix_pkg is
    -- Constants - Modified for 1 vendor x 800 eVTOLs x 800 keys (testing)
    constant NUM_VENDOR_VARIANTS : integer := 1;     -- 1 vendor
    constant NUM_EVTOL_PER_VARIANT : integer := 1;   -- 1 eVTOL
    constant NUM_KEYS_PER_EVTOL : integer := 800;    -- 800 keys
    constant HASH_WIDTH : integer := 256;            -- SHA-256 output width
        -- Type definitions for seed storage arrays
    -- Level 1: Vendor variant seeds (100 seeds) - stored as INTEGERS
    type vendor_seed_array is array (0 to NUM_VENDOR_VARIANTS-1) of integer;
    
    -- Level 2: eVTOL-specific seeds (100x100 = 10,000 seeds) - stored as INTEGERS
    type evtol_seed_matrix is array (0 to NUM_VENDOR_VARIANTS-1, 0 to NUM_EVTOL_PER_VARIANT-1) of integer;
    
    -- Level 3: NO STORAGE - Keys are validated as they're generated
    -- Only store a small sampling buffer for verification
    constant SAMPLE_BUFFER_SIZE : integer := 16;  -- Store only 16 keys for sampling
    type sample_key_buffer is array (0 to SAMPLE_BUFFER_SIZE-1) of std_logic_vector(HASH_WIDTH-1 downto 0);
    
    -- Helper function to convert integer seed to valid Chebyshev input range
    function seed_to_scaled_int(seed_val : integer) return integer;
    
end package key_matrix_pkg;

package body key_matrix_pkg is
    
    -- Convert seed to integer in valid Chebyshev range
    function seed_to_scaled_int(seed_val : integer) return integer is
        variable result : integer;
    begin
        -- Map to range 0-1000 for Chebyshev stability
        result := abs(seed_val) mod 1001;
        -- Ensure non-zero
        if result = 0 then
            result := 100;
        end if;
        return result;
    end function;
    
end package body key_matrix_pkg;
