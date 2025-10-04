----------------------------------------------------------------------------------
-- FPGA Top Module for Key Generator
-- Target: Nexys A7
-- 
-- Description: Top-level wrapper for FPGA implementation
--              Maps board buttons, switches, and LEDs to key generation module
--
-- Interface:
--   Inputs:
--     - CLK100MHZ: 100 MHz board clock
--     - CPU_RESETN: Active-low reset button (BTNU on Basys3)
--     - BTNC: Start key generation
--     - SW[9:0]: Set genseed1 value (0-1000, display shows actual value)
--     - SW[15:10]: Set Chebyshev order (1-63, limited to 6 bits)
--
--   Outputs:
--     - LED[15:0]: Status and key output display
--       * LED[0]: Processing indicator (blinks during computation)
--       * LED[1]: Key ready indicator
--       * LED[15:8]: Lower 8 bits of generated key (for verification)
--       * LED[7:2]: Chebyshev order being processed
--     - AN[3:0]: 7-segment display anodes (for genseed1 display)
--     - SEG[6:0]: 7-segment display segments
--     - DP: Decimal point
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fpga_top is
    Port (
        -- Clock and Reset
        CLK100MHZ   : in  STD_LOGIC;                      -- 100 MHz clock
        CPU_RESETN  : in  STD_LOGIC;                      -- Active-low reset (button)
        
        -- Control Inputs
        BTNC        : in  STD_LOGIC;                      -- Center button (start)
        BTNU        : in  STD_LOGIC;                      -- Up button (increment order)
        BTND        : in  STD_LOGIC;                      -- Down button (decrement order)
        
        -- Configuration Inputs
        SW          : in  STD_LOGIC_VECTOR(15 downto 0);  -- Switches
        
        -- Status Outputs
        LED         : out STD_LOGIC_VECTOR(15 downto 0);  -- LEDs
        
        -- 7-Segment Display (for genseed1 display)
        AN          : out STD_LOGIC_VECTOR(3 downto 0);   -- Anodes
        SEG         : out STD_LOGIC_VECTOR(6 downto 0);   -- Segments
        DP          : out STD_LOGIC                        -- Decimal point
    );
end fpga_top;

architecture Behavioral of fpga_top is

    -- Component declaration
    component generate_key is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            genseed1        : in  integer range 0 to 1000;
            cheby_order     : in  integer range 1 to 100;
            processing      : out std_logic;
            key_ready       : out std_logic;
            chebyshev_result : out integer;
            key_out         : out std_logic_vector(255 downto 0)
        );
    end component;

    -- Clock and Reset
    signal clk          : std_logic;
    signal rst          : std_logic;
    signal rst_n        : std_logic;
    
    -- Button debouncing
    signal btnc_sync    : std_logic_vector(2 downto 0) := "000";
    signal btnc_debounced : std_logic := '0';
    signal btnc_pulse   : std_logic := '0';
    signal btnc_prev    : std_logic := '0';
    
    signal btnu_sync    : std_logic_vector(2 downto 0) := "000";
    signal btnu_pulse   : std_logic := '0';
    signal btnu_prev    : std_logic := '0';
    
    signal btnd_sync    : std_logic_vector(2 downto 0) := "000";
    signal btnd_pulse   : std_logic := '0';
    signal btnd_prev    : std_logic := '0';
    
    -- Key generator signals
    signal start_gen    : std_logic := '0';
    signal genseed1     : integer range 0 to 1000 := 100;
    signal cheby_order  : integer range 1 to 100 := 1;
    signal processing   : std_logic;
    signal key_ready    : std_logic;
    signal cheby_result : integer;
    signal key_out      : std_logic_vector(255 downto 0);
    
    -- Configuration
    signal sw_genseed1  : integer range 0 to 1000;
    signal sw_order     : integer range 1 to 100;
    
    -- 7-segment display
    signal digit_counter : unsigned(17 downto 0) := (others => '0');  -- ~2.6ms refresh @ 100MHz
    signal active_digit  : unsigned(1 downto 0) := "00";
    signal digit_value   : unsigned(3 downto 0);
    
    -- Status indicators
    signal led_output   : std_logic_vector(15 downto 0);
    signal blink_counter : unsigned(25 downto 0) := (others => '0');  -- ~0.67s @ 100MHz
    signal processing_blink : std_logic := '0';

begin

    -- Clock assignment
    clk <= CLK100MHZ;
    rst_n <= CPU_RESETN;
    rst <= not rst_n;  -- Convert to active-high

    ------------------------------------------------------------------------------------
    -- Button Debouncing and Edge Detection
    ------------------------------------------------------------------------------------
    
    button_debounce : process(clk, rst)
    begin
        if rst = '1' then
            btnc_sync <= "000";
            btnu_sync <= "000";
            btnd_sync <= "000";
            btnc_prev <= '0';
            btnu_prev <= '0';
            btnd_prev <= '0';
        elsif rising_edge(clk) then
            -- Synchronize buttons (3-stage shift register for metastability)
            btnc_sync <= btnc_sync(1 downto 0) & BTNC;
            btnu_sync <= btnu_sync(1 downto 0) & BTNU;
            btnd_sync <= btnd_sync(1 downto 0) & BTND;
            
            -- Debounced outputs (all 3 samples must agree)
            if btnc_sync = "111" then
                btnc_debounced <= '1';
            elsif btnc_sync = "000" then
                btnc_debounced <= '0';
            end if;
            
            -- Edge detection for pulses
            btnc_prev <= btnc_debounced;
            btnu_prev <= btnu_sync(2);
            btnd_prev <= btnd_sync(2);
        end if;
    end process;
    
    -- Generate single-cycle pulses on rising edges
    btnc_pulse <= btnc_debounced and not btnc_prev;
    btnu_pulse <= btnu_sync(2) and not btnu_prev;
    btnd_pulse <= btnd_sync(2) and not btnd_prev;

    ------------------------------------------------------------------------------------
    -- Configuration from Switches
    ------------------------------------------------------------------------------------
    
    config_process : process(clk, rst)
        variable temp_genseed : integer range 0 to 1023;
        variable temp_order   : integer range 0 to 127;
    begin
        if rst = '1' then
            sw_genseed1 <= 100;  -- Default 0.1
            sw_order <= 1;
        elsif rising_edge(clk) then
            -- SW[9:0] sets genseed1 (0-1000, 10 bits = 0-1023)
            temp_genseed := to_integer(unsigned(SW(9 downto 0)));
            if temp_genseed > 1000 then
                sw_genseed1 <= 1000;
            else
                sw_genseed1 <= temp_genseed;
            end if;
            
            -- SW[15:10] sets Chebyshev order (1-100, 6 bits = 0-63)
            temp_order := to_integer(unsigned(SW(15 downto 10)));
            if temp_order = 0 then
                sw_order <= 1;  -- Minimum order is 1
            elsif temp_order > 100 then
                sw_order <= 100;
            else
                sw_order <= temp_order;
            end if;
        end if;
    end process;
    
    ------------------------------------------------------------------------------------
    -- Order Increment/Decrement with Buttons
    ------------------------------------------------------------------------------------
    
    order_control : process(clk, rst)
    begin
        if rst = '1' then
            cheby_order <= 1;
        elsif rising_edge(clk) then
            -- Update order from switches by default
            if processing = '0' and key_ready = '0' then
                cheby_order <= sw_order;
                
                -- Button U increments order
                if btnu_pulse = '1' and cheby_order < 100 then
                    cheby_order <= cheby_order + 1;
                end if;
                
                -- Button D decrements order
                if btnd_pulse = '1' and cheby_order > 1 then
                    cheby_order <= cheby_order - 1;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------
    -- Start Control
    ------------------------------------------------------------------------------------
    
    start_control : process(clk, rst)
    begin
        if rst = '1' then
            start_gen <= '0';
            genseed1 <= 100;
        elsif rising_edge(clk) then
            start_gen <= '0';  -- Default low
            
            -- Capture genseed1 and trigger start on button press
            if btnc_pulse = '1' and processing = '0' then
                genseed1 <= sw_genseed1;
                start_gen <= '1';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------
    -- Instantiate Key Generator
    ------------------------------------------------------------------------------------
    
    key_gen_inst : generate_key
        port map (
            clk             => clk,
            rst             => rst,
            start           => start_gen,
            genseed1        => genseed1,
            cheby_order     => cheby_order,
            processing      => processing,
            key_ready       => key_ready,
            chebyshev_result => cheby_result,
            key_out         => key_out
        );

    ------------------------------------------------------------------------------------
    -- LED Status Display
    ------------------------------------------------------------------------------------
    
    -- Blink counter for processing indicator
    blink_process : process(clk, rst)
    begin
        if rst = '1' then
            blink_counter <= (others => '0');
            processing_blink <= '0';
        elsif rising_edge(clk) then
            blink_counter <= blink_counter + 1;
            if blink_counter = 0 then
                processing_blink <= not processing_blink;
            end if;
        end if;
    end process;
    
    led_assignment : process(clk, rst)
    begin
        if rst = '1' then
            led_output <= (others => '0');
        elsif rising_edge(clk) then
            -- LED[0]: Processing indicator (blinking)
            led_output(0) <= processing and processing_blink;
            
            -- LED[1]: Key ready indicator (solid)
            led_output(1) <= key_ready;
            
            -- LED[7:2]: Current Chebyshev order (6 bits)
            led_output(7 downto 2) <= std_logic_vector(to_unsigned(cheby_order, 6));
            
            -- LED[15:8]: Lower 8 bits of generated key hash
            led_output(15 downto 8) <= key_out(7 downto 0);
        end if;
    end process;
    
    LED <= led_output;

    ------------------------------------------------------------------------------------
    -- 7-Segment Display (shows genseed1 value in decimal)
    ------------------------------------------------------------------------------------
    
    -- Digit refresh counter
    digit_refresh : process(clk, rst)
    begin
        if rst = '1' then
            digit_counter <= (others => '0');
            active_digit <= "00";
        elsif rising_edge(clk) then
            digit_counter <= digit_counter + 1;
            if digit_counter = 0 then
                active_digit <= active_digit + 1;
            end if;
        end if;
    end process;
    
    -- Digit multiplexing (display genseed1 value: 0-1000)
    digit_mux : process(active_digit, sw_genseed1)
        variable temp_value : integer range 0 to 1000;
    begin
        temp_value := sw_genseed1;
        
        case active_digit is
            when "00" =>  -- Digit 0 (ones)
                digit_value <= to_unsigned(temp_value mod 10, 4);
                AN <= "1110";
            when "01" =>  -- Digit 1 (tens)
                digit_value <= to_unsigned((temp_value / 10) mod 10, 4);
                AN <= "1101";
            when "10" =>  -- Digit 2 (hundreds)
                digit_value <= to_unsigned((temp_value / 100) mod 10, 4);
                AN <= "1011";
            when "11" =>  -- Digit 3 (thousands - always 0 or 1)
                digit_value <= to_unsigned(temp_value / 1000, 4);
                AN <= "0111";
            when others =>
                digit_value <= (others => '0');
                AN <= "1111";
        end case;
    end process;
    
    -- 7-segment decoder
    seg_decoder : process(digit_value)
    begin
        case digit_value is
            when "0000" => SEG <= "1000000";  -- 0
            when "0001" => SEG <= "1111001";  -- 1
            when "0010" => SEG <= "0100100";  -- 2
            when "0011" => SEG <= "0110000";  -- 3
            when "0100" => SEG <= "0011001";  -- 4
            when "0101" => SEG <= "0010010";  -- 5
            when "0110" => SEG <= "0000010";  -- 6
            when "0111" => SEG <= "1111000";  -- 7
            when "1000" => SEG <= "0000000";  -- 8
            when "1001" => SEG <= "0010000";  -- 9
            when others => SEG <= "1111111";  -- blank
        end case;
    end process;
    
    -- Decimal point (off)
    DP <= '1';

end Behavioral;
