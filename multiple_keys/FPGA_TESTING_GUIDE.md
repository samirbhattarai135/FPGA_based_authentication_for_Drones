# FPGA Implementation Testing and Analysis Guide

## Overview

After successfully programming your Nexys A7 board with `fpga_top.bit`, you need to verify that the key generation works correctly. This guide covers hardware testing, debugging, and results analysis.

---

## 1. Hardware Setup

### Physical Connections

1. **Connect the board:**

   - USB cable from Nexys A7 to your computer
   - Power LED should be ON
   - DONE LED should be ON (indicates programming success)

2. **Initial state after programming:**
   - All LEDs may be random initially
   - 7-segment displays will show something
   - Board is waiting for inputs

---

## 2. Understanding the Interface

### Input Controls (fpga_top.vhd)

**Switches (SW[15:0]):**

- `SW[9:0]`: Set genseed1 value (0-1023 decimal)
  - Example: 0b0001100100 = 100 decimal
  - This is your x value for Chebyshev polynomial
- `SW[15:10]`: Set Chebyshev order n (1-63)
  - Example: 0b000001 = order 1, 0b001010 = order 10
  - This determines which Tn(x) to compute

**Buttons:**

- `BTNC` (Center): Start key generation
- `BTNU` (Up): Increment order (if implemented)
- `BTND` (Down): Decrement order (if implemented)
- `CPU_RESETN`: Reset system (may need to release after programming)

### Output Indicators

**LEDs (LED[15:0]):**

- `LED[0]`: Processing indicator (should blink during computation)
- `LED[1]`: Key ready indicator (ON when key is ready)
- `LED[15:8]`: Lower 8 bits of generated key (for quick verification)
- `LED[7:2]`: Current Chebyshev order being processed

**7-Segment Display:**

- Shows genseed1 value in decimal (4 digits)
- `DP`: Decimal point control

---

## 3. Step-by-Step Testing Procedure

### Test 1: Basic Functionality Check

1. **Set known inputs:**

   ```
   SW[9:0]  = 0000000001 (genseed1 = 1)
   SW[15:10] = 000001     (order = 1)
   ```

2. **Press BTNC** to start key generation

3. **Observe:**

   - LED[0] should blink briefly (processing)
   - LED[1] should turn ON (key ready)
   - LED[15:8] should show some value (part of hash)
   - 7-segment should display "0001"

4. **Expected result:**
   - Key K1 = H(T1(1)) = H(1)
   - Processing time: ~70 cycles @ 100 MHz = 700 ns (too fast to see!)

### Test 2: Different Orders

1. **Test order 2:**

   ```
   SW[9:0]  = 0001100100 (genseed1 = 100)
   SW[15:10] = 000010     (order = 2)
   ```

   - Press BTNC
   - Result: K2 = H(T2(100))
   - T2(100) should be calculated first, then hashed

2. **Test order 10:**
   ```
   SW[9:0]  = 0001100100 (genseed1 = 100)
   SW[15:10] = 001010     (order = 10)
   ```
   - Press BTNC
   - Result: K10 = H(T10(100))
   - Processing time: ~79 cycles (still very fast)

### Test 3: Different Seeds

1. **Change genseed1:**
   ```
   SW[9:0]  = 0011111010 (genseed1 = 250)
   SW[15:10] = 000001     (order = 1)
   ```
   - Press BTNC
   - LED[15:8] should show different value than Test 1
   - This verifies the input is being used

### Test 4: Repeatability

1. **Set inputs:**

   ```
   SW[9:0]  = 0001100100 (genseed1 = 100)
   SW[15:10] = 000101     (order = 5)
   ```

2. **Press BTNC multiple times**
   - LED[15:8] should show the SAME value each time
   - This verifies deterministic operation

---

## 4. Using a Logic Analyzer / ILA (Advanced)

If you want to see internal signals, you can add Integrated Logic Analyzer (ILA):

### Add ILA in Vivado:

1. **Mark signals for debug:**
   In your VHDL, add attribute:

   ```vhdl
   attribute mark_debug : string;
   attribute mark_debug of key_out : signal is "true";
   attribute mark_debug of chebyshev_result : signal is "true";
   ```

2. **Insert ILA IP:**

   - Tools → Set Up Debug
   - Select signals to monitor
   - Re-run implementation

3. **Capture waveforms:**
   - Hardware Manager → Run Trigger
   - Set trigger on `start = 1`
   - Observe internal state transitions

### Signals to Monitor:

- `current_state`: State machine progression
- `cheby_done`: When Chebyshev completes
- `sha_finished`: When SHA-256 completes
- `cheby_result`: Raw Chebyshev output
- `key_out`: Final 256-bit hash

---

## 5. Extracting Full Key Data

Since LEDs only show 8 bits, you have several options to get the full 256-bit key:

### Option A: Add UART Output

Modify `fpga_top.vhd` to add UART transmitter:

```vhdl
-- Send 256-bit key over UART when ready
-- Can read on PC using terminal (115200 baud)
```

### Option B: Use ChipScope/ILA

1. Add ILA to monitor `key_out` signal
2. Trigger on `key_ready = 1`
3. View full 256-bit value in waveform
4. Export to file for analysis

### Option C: Multiple LED Displays

Add a counter to cycle through key bytes:

```vhdl
-- Press BTNU to show next 8 bits
-- Display on LEDs in sequence
```

### Option D: Store in Block RAM

```vhdl
-- Store generated keys in BRAM
-- Read back through JTAG or UART
```

---

## 6. Verification Against Simulation

### Compare Hardware vs Simulation Results

1. **Run testbench** with same inputs:

   ```vhdl
   genseed1 = 100
   cheby_order = 5
   ```

2. **Record simulation output:**

   ```
   Chebyshev T5(100) = <value>
   Key K5 = <256-bit hash>
   ```

3. **Program FPGA** with same inputs:

   ```
   SW[9:0] = 100
   SW[15:10] = 5
   ```

4. **Compare:**
   - ILA capture should match simulation exactly
   - LED[15:8] should match simulation bits [7:0]

---

## 7. Performance Analysis

### Measure Timing in Hardware

**Method 1: LED Blink Counter**

- If LED[0] blinks, count cycles
- Use oscilloscope on LED[0]
- Measure pulse width

**Method 2: ILA Timestamps**

- Capture `key_ready` rising edge
- Measure time from `start` to `key_ready`
- Should be ~70-170 cycles depending on order

**Method 3: Add Cycle Counter**
Modify design to add counter:

```vhdl
signal cycle_count : unsigned(15 downto 0);

process(clk, rst)
begin
    if rst = '1' then
        cycle_count <= (others => '0');
    elsif rising_edge(clk) then
        if start = '1' and current_state = IDLE then
            cycle_count <= (others => '0');
        elsif current_state /= IDLE then
            cycle_count <= cycle_count + 1;
        end if;
    end if;
end process;

-- Display on 7-segment when done
```

---

## 8. Common Issues and Debugging

### Issue 1: No LED Response

**Symptoms:** Press BTNC, nothing happens
**Check:**

- CPU_RESETN button released?
- Switches set correctly?
- Bitstream programmed successfully?

**Debug:**

```tcl
# In Hardware Manager
refresh_hw_device [current_hw_device]
```

### Issue 2: LED[1] Never Turns ON

**Symptoms:** LED[0] blinks but LED[1] stays off
**Possible causes:**

- State machine stuck
- SHA-256 not finishing
- Check with ILA

### Issue 3: Different Results Each Time

**Symptoms:** Same inputs give different LED outputs
**Possible causes:**

- Uninitialized registers
- Timing violations (check timing report)
- Metastability on inputs

**Check timing:**

```tcl
# In Vivado
open_run impl_1
report_timing_summary -file timing.rpt
```

Look for negative slack (WNS < 0)

### Issue 4: All LEDs Same Value

**Symptoms:** LED[15:8] always show same pattern
**Possible causes:**

- key_out not updating
- Output mapping incorrect
- Check signal connections

---

## 9. Automated Testing with TCL

### Create Test Script for Hardware Manager

```tcl
# test_fpga.tcl
# Connect to hardware
open_hw_manager
connect_hw_server
open_hw_target

# Program device
set_property PROGRAM.FILE {fpga_top.bit} [current_hw_device]
program_hw_devices [current_hw_device]

# If using ILA, setup triggers
current_hw_ila [get_hw_ilas -of_objects [current_hw_device]]
run_hw_ila [current_hw_ila]

# Wait and capture
after 1000
display_hw_ila_data [upload_hw_ila_data [current_hw_ila]]
```

---

## 10. Expected Results Table

| Test | genseed1 | Order | Expected Behavior       | Time (cycles) |
| ---- | -------- | ----- | ----------------------- | ------------- |
| 1    | 1        | 1     | LED[1] ON, LED[0] blink | ~70           |
| 2    | 100      | 1     | Different LED pattern   | ~70           |
| 3    | 100      | 2     | Different from Test 2   | ~71           |
| 4    | 100      | 10    | Different from Test 3   | ~79           |
| 5    | 100      | 100   | Different from Test 4   | ~169          |
| 6    | 250      | 1     | Different from Test 2   | ~70           |

**Note:** "Different" means LED[15:8] shows different values, confirming unique keys.

---

## 11. Documentation of Results

### Record Your Findings

Create a test log:

```
Date: Oct 3, 2025
Board: Nexys A7-100T
Bitstream: fpga_top.bit
Clock: 100 MHz

Test 1:
- Input: genseed1=100, order=1
- SW[9:0] = 0001100100
- SW[15:10] = 000001
- LED[15:8] = 0xAB (example)
- LED[1] = ON
- Status: PASS

Test 2:
- Input: genseed1=100, order=2
- LED[15:8] = 0xCD (different from Test 1)
- Status: PASS

...
```

### Take Photos/Videos

- Capture board with LEDs showing results
- Video of LED[0] blinking during computation
- Useful for presentations/reports

---

## 12. Next Steps

After basic verification:

1. **Test all 100 keys:**

   - Loop through orders 1-100
   - Record LED outputs
   - Verify uniqueness

2. **Performance benchmarking:**

   - Measure actual throughput
   - Compare to simulation predictions

3. **Stress testing:**

   - Rapid button presses
   - Random input patterns
   - Long-duration operation

4. **Integration testing:**
   - If this is part of larger system
   - Test with actual authentication protocol

---

## Quick Reference Card

### Input Setup

```
SW[9:0]   → genseed1 (0-1023)
SW[15:10] → order (1-63)
BTNC      → Start
```

### Output Reading

```
LED[0]    → Blinking = processing
LED[1]    → ON = key ready
LED[15:8] → Key bits [7:0]
7-Seg     → genseed1 value
```

### Quick Test

```
1. Set SW[9:0] = 0001100100 (decimal 100)
2. Set SW[15:10] = 000001 (order 1)
3. Press BTNC
4. Check LED[1] turns ON
5. Note LED[15:8] value
6. Change SW[15:10] to 000010 (order 2)
7. Press BTNC again
8. Verify LED[15:8] changed (different key!)
```

---

## Conclusion

The key to successful FPGA analysis is:

1. ✅ Know your inputs and outputs
2. ✅ Test systematically with known values
3. ✅ Compare hardware results to simulation
4. ✅ Use ILA for deep debugging if needed
5. ✅ Document everything!

Good luck with your testing! 🎉
