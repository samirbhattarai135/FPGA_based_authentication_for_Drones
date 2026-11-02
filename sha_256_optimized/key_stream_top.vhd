----------------------------------------------------------------------------------
-- Company: The University of Southern Mississippi
-- Engineer: Samir Bhattarai
--
-- Module Name: key_stream_top - rtl
-- Target Devices: Xilinx Artix-7 (Nexys A7-100T)
-- Description: Three-level eVTOL key generator (vendor seeds -> eVTOL seeds ->
--              streamed keys), restructured so the stages overlap.
--
--   Level 1 and Level 2 are computed once with the fast-doubling Chebyshev unit
--   and stored, as in the original design. Level 3 is a three-stage stream:
--
--     chebyshev_stream (T_2, T_3, ... of the eVTOL seed)  ->  one-entry slot
--       -> dispatch round-robin to NUM_CORES SHA-256 cores
--       -> collect in the same round-robin order -> key_valid / key_out
--
--   The Chebyshev stream computes the next key's T value while the SHA cores hash
--   earlier keys. Cores start in round-robin order and share one fixed latency,
--   so collecting in the same order keeps the key stream in index order.
--
--   Key[v,e,k] = SHA-256( T_{k+2}(eVTOL_seed[v,e]) || v || e || k ), with each
--   field a 32-bit big-endian word. The 16-byte message gets standard FIPS 180-4
--   padding, so every key can be checked against any SHA-256 library.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.key_matrix_pkg.all;
use work.modp_pkg.all;

entity key_stream_top is
    generic (
        NUM_CORES : positive := 2
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;                     -- synchronous, active high
        start        : in  std_logic;
        genseed      : in  natural range 0 to 1000;
        processing   : out std_logic;
        level1_done  : out std_logic;
        level2_done  : out std_logic;
        level3_done  : out std_logic;
        key_valid    : out std_logic;                     -- one-cycle pulse per key
        key_out      : out std_logic_vector(255 downto 0);
        key_vendor   : out natural range 0 to NUM_VENDOR_VARIANTS-1;
        key_evtol    : out natural range 0 to NUM_EVTOL_PER_VARIANT-1;
        key_index    : out natural range 0 to NUM_KEYS_PER_EVTOL-1
    );
end key_stream_top;

architecture rtl of key_stream_top is
    function clog2(v : positive) return positive is
        variable r : natural := 0;
    begin
        while 2**r < v loop
            r := r + 1;
        end loop;
        if r = 0 then
            return 1;
        end if;
        return r;
    end function;

    function maximum2(a_in, b_in : natural) return natural is
    begin
        if a_in >= b_in then return a_in; else return b_in; end if;
    end function;

    -- Largest degree the fast-doubling unit is asked for: (count - 1) + 2 at Level 1 or 2.
    constant MAX_DEGREE : natural := maximum2(NUM_VENDOR_VARIANTS, NUM_EVTOL_PER_VARIANT) + 1;
    constant N_BITS     : positive := clog2(MAX_DEGREE + 1);
    constant TOTAL_KEYS : natural := NUM_VENDOR_VARIANTS * NUM_EVTOL_PER_VARIANT * NUM_KEYS_PER_EVTOL;

    -- Per-level offsets; the same constants as the original design.
    constant RV  : residue := to_unsigned(134, 31);
    constant REV : residue := to_unsigned(256, 31);

    -- 16-byte message T || v || e || k with FIPS 180-4 padding: a single 1 bit,
    -- zeros, then the 64-bit message length (128 bits).
    function padded_block(t : residue; v, e, k : natural) return std_logic_vector is
        variable blk : std_logic_vector(511 downto 0) := (others => '0');
    begin
        blk(511 downto 480) := std_logic_vector(resize(t, 32));
        blk(479 downto 448) := std_logic_vector(to_unsigned(v, 32));
        blk(447 downto 416) := std_logic_vector(to_unsigned(e, 32));
        blk(415 downto 384) := std_logic_vector(to_unsigned(k, 32));
        blk(383)            := '1';
        blk(63 downto 0)    := std_logic_vector(to_unsigned(128, 64));
        return blk;
    end function;

    type vendor_seed_array is array (0 to NUM_VENDOR_VARIANTS-1) of residue;
    type evtol_seed_matrix is array (0 to NUM_VENDOR_VARIANTS-1, 0 to NUM_EVTOL_PER_VARIANT-1) of residue;
    signal vendor_seeds : vendor_seed_array := (others => (others => '0'));
    signal evtol_seeds  : evtol_seed_matrix := (others => (others => (others => '0')));

    type phase_t is (IDLE, L1_ISSUE, L1_WAIT, L2_ISSUE, L2_WAIT, L3_STREAM, FINISHED);
    signal phase : phase_t := IDLE;

    -- Fast-doubling Chebyshev unit (Levels 1 and 2)
    signal cheb_start  : std_logic := '0';
    signal cheb_x      : residue := (others => '0');
    signal cheb_n      : unsigned(N_BITS-1 downto 0) := (others => '0');
    signal cheb_busy   : std_logic;
    signal cheb_done   : std_logic;
    signal cheb_result : residue;

    -- Chebyshev stream (Level 3)
    signal stream_load   : std_logic := '0';
    signal stream_step   : std_logic := '0';
    signal stream_x      : residue := (others => '0');
    signal stream_busy   : std_logic;
    signal stream_done   : std_logic;
    signal stream_result : residue;
    signal need_load     : std_logic := '0';

    -- Level 1/2 counters and the Level 3 producer's position
    signal v_idx, prod_v : natural range 0 to NUM_VENDOR_VARIANTS-1 := 0;
    signal e_idx, prod_e : natural range 0 to NUM_EVTOL_PER_VARIANT-1 := 0;
    signal prod_k        : natural range 0 to NUM_KEYS_PER_EVTOL-1 := 0;
    signal produced      : natural range 0 to TOTAL_KEYS := 0;
    signal stream_inflight : std_logic := '0';
    signal tag_v_stream    : natural range 0 to NUM_VENDOR_VARIANTS-1 := 0;
    signal tag_e_stream    : natural range 0 to NUM_EVTOL_PER_VARIANT-1 := 0;
    signal tag_k_stream    : natural range 0 to NUM_KEYS_PER_EVTOL-1 := 0;

    -- One-entry slot between the Chebyshev unit and the SHA cores
    signal slot_valid : std_logic := '0';
    signal slot_t     : residue := (others => '0');
    signal slot_v     : natural range 0 to NUM_VENDOR_VARIANTS-1 := 0;
    signal slot_e     : natural range 0 to NUM_EVTOL_PER_VARIANT-1 := 0;
    signal slot_k     : natural range 0 to NUM_KEYS_PER_EVTOL-1 := 0;

    -- SHA cores
    type block_array  is array (0 to NUM_CORES-1) of std_logic_vector(511 downto 0);
    type digest_array is array (0 to NUM_CORES-1) of std_logic_vector(255 downto 0);
    type v_array is array (0 to NUM_CORES-1) of natural range 0 to NUM_VENDOR_VARIANTS-1;
    type e_array is array (0 to NUM_CORES-1) of natural range 0 to NUM_EVTOL_PER_VARIANT-1;
    type k_array is array (0 to NUM_CORES-1) of natural range 0 to NUM_KEYS_PER_EVTOL-1;
    signal core_start  : std_logic_vector(NUM_CORES-1 downto 0) := (others => '0');
    signal core_done   : std_logic_vector(NUM_CORES-1 downto 0);
    signal core_busy   : std_logic_vector(NUM_CORES-1 downto 0);
    signal core_block  : block_array := (others => (others => '0'));
    signal core_digest : digest_array;
    signal inflight    : std_logic_vector(NUM_CORES-1 downto 0) := (others => '0');  -- dispatched, not yet collected
    signal ready       : std_logic_vector(NUM_CORES-1 downto 0) := (others => '0');  -- digest finished, not yet collected
    signal tag_v       : v_array := (others => 0);
    signal tag_e       : e_array := (others => 0);
    signal tag_k       : k_array := (others => 0);
    signal dispatch_i  : natural range 0 to NUM_CORES-1 := 0;
    signal collect_i   : natural range 0 to NUM_CORES-1 := 0;
    signal collected   : natural range 0 to TOTAL_KEYS := 0;
begin
    cheb : entity work.chebyshev_modp
        generic map (N_BITS => N_BITS)
        port map (clk => clk, rst => rst, start => cheb_start, x => cheb_x, n => cheb_n,
                  busy => cheb_busy, done => cheb_done, result => cheb_result);

    stream : entity work.chebyshev_stream
        port map (clk => clk, rst => rst, load => stream_load, x => stream_x, step => stream_step,
                  busy => stream_busy, done => stream_done, result => stream_result);

    cores : for i in 0 to NUM_CORES-1 generate
        core : entity work.sha256_core
            port map (clk => clk, rst => rst, start => core_start(i), first_block => '1',
                      block_in => core_block(i), busy => core_busy(i), done => core_done(i),
                      digest => core_digest(i));
    end generate;

    processing <= '0' when phase = IDLE or phase = FINISHED else '1';

    process(clk)
    begin
        if rising_edge(clk) then
            cheb_start  <= '0';
            stream_load <= '0';
            stream_step <= '0';
            core_start <= (others => '0');
            key_valid  <= '0';

            if rst = '1' then
                phase       <= IDLE;
                level1_done <= '0';
                level2_done <= '0';
                level3_done <= '0';
                slot_valid  <= '0';
                inflight    <= (others => '0');
                ready       <= (others => '0');
            else
                -- Results are caught here so no done pulse is missed in any phase.
                for i in 0 to NUM_CORES-1 loop
                    if core_done(i) = '1' then
                        ready(i) <= '1';
                    end if;
                end loop;

                case phase is
                    when IDLE =>
                        if start = '1' then
                            level1_done <= '0';
                            level2_done <= '0';
                            level3_done <= '0';
                            v_idx <= 0;
                            e_idx <= 0;
                            phase <= L1_ISSUE;
                        end if;

                    -- Level 1: VendorSeed[v] = T_{v+2}(genseed) + Rv
                    when L1_ISSUE =>
                        cheb_x     <= to_unsigned(genseed, 31);
                        cheb_n     <= to_unsigned(v_idx + 2, N_BITS);
                        cheb_start <= '1';
                        phase      <= L1_WAIT;

                    when L1_WAIT =>
                        if cheb_done = '1' then
                            vendor_seeds(v_idx) <= add_mod(cheb_result, RV);
                            if v_idx = NUM_VENDOR_VARIANTS-1 then
                                level1_done <= '1';
                                v_idx <= 0;
                                phase <= L2_ISSUE;
                            else
                                v_idx <= v_idx + 1;
                                phase <= L1_ISSUE;
                            end if;
                        end if;

                    -- Level 2: eVTOL_Seed[v,e] = T_{e+2}(VendorSeed[v]) + Rev
                    when L2_ISSUE =>
                        cheb_x     <= vendor_seeds(v_idx);
                        cheb_n     <= to_unsigned(e_idx + 2, N_BITS);
                        cheb_start <= '1';
                        phase      <= L2_WAIT;

                    when L2_WAIT =>
                        if cheb_done = '1' then
                            evtol_seeds(v_idx, e_idx) <= add_mod(cheb_result, REV);
                            if e_idx < NUM_EVTOL_PER_VARIANT-1 then
                                e_idx <= e_idx + 1;
                                phase <= L2_ISSUE;
                            elsif v_idx < NUM_VENDOR_VARIANTS-1 then
                                e_idx <= 0;
                                v_idx <= v_idx + 1;
                                phase <= L2_ISSUE;
                            else
                                level2_done   <= '1';
                                prod_v        <= 0;
                                prod_e        <= 0;
                                prod_k        <= 0;
                                produced      <= 0;
                                collected     <= 0;
                                stream_inflight <= '0';
                                need_load     <= '1';
                                dispatch_i    <= 0;
                                collect_i     <= 0;
                                phase         <= L3_STREAM;
                            end if;
                        end if;

                    -- Level 3: three overlapped stages, each guarded by its own handshake.
                    when L3_STREAM =>
                        -- Stage 1: (re)load the stream at each new eVTOL seed, then step it
                        -- once per key whenever the slot is free for the result.
                        if stream_busy = '0' and need_load = '1' then
                            stream_x    <= evtol_seeds(prod_v, prod_e);
                            stream_load <= '1';
                            need_load   <= '0';
                        elsif stream_busy = '0' and stream_inflight = '0' and slot_valid = '0'
                              and produced < TOTAL_KEYS then
                            stream_step   <= '1';
                            stream_inflight <= '1';
                            tag_v_stream    <= prod_v;
                            tag_e_stream    <= prod_e;
                            tag_k_stream    <= prod_k;
                            produced      <= produced + 1;
                            if prod_k < NUM_KEYS_PER_EVTOL-1 then
                                prod_k <= prod_k + 1;
                            else
                                prod_k    <= 0;
                                need_load <= '1';
                                if prod_e < NUM_EVTOL_PER_VARIANT-1 then
                                    prod_e <= prod_e + 1;
                                else
                                    prod_e <= 0;
                                    if prod_v < NUM_VENDOR_VARIANTS-1 then
                                        prod_v <= prod_v + 1;
                                    end if;
                                end if;
                            end if;
                        end if;

                        if stream_done = '1' and stream_inflight = '1' then
                            slot_valid    <= '1';
                            slot_t        <= stream_result;
                            slot_v        <= tag_v_stream;
                            slot_e        <= tag_e_stream;
                            slot_k        <= tag_k_stream;
                            stream_inflight <= '0';
                        end if;

                        -- Stage 2: hand the slot to the next core in round-robin order.
                        if slot_valid = '1' and inflight(dispatch_i) = '0' then
                            core_block(dispatch_i) <= padded_block(slot_t, slot_v, slot_e, slot_k);
                            core_start(dispatch_i) <= '1';
                            inflight(dispatch_i)   <= '1';
                            tag_v(dispatch_i)      <= slot_v;
                            tag_e(dispatch_i)      <= slot_e;
                            tag_k(dispatch_i)      <= slot_k;
                            slot_valid             <= '0';
                            dispatch_i             <= (dispatch_i + 1) mod NUM_CORES;
                        end if;

                        -- Stage 3: emit keys in the same round-robin order.
                        if inflight(collect_i) = '1' and ready(collect_i) = '1' then
                            key_valid           <= '1';
                            key_out             <= core_digest(collect_i);
                            key_vendor          <= tag_v(collect_i);
                            key_evtol           <= tag_e(collect_i);
                            key_index           <= tag_k(collect_i);
                            inflight(collect_i) <= '0';
                            ready(collect_i)    <= '0';
                            collect_i           <= (collect_i + 1) mod NUM_CORES;
                            collected           <= collected + 1;
                            if collected = TOTAL_KEYS-1 then
                                level3_done <= '1';
                                phase       <= FINISHED;
                            end if;
                        end if;

                    when FINISHED =>
                        if start = '1' then
                            phase <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end rtl;
