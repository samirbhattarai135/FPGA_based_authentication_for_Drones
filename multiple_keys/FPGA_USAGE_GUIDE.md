# FPGA Implementation Guide

## Key Generator on Basys3/Nexys A7/Arty A7 Boards

---

## Quick Start

### 1. **Open Vivado and Create Project**

```tcl
cd "/Users/samir/Projects/FPGA/Simple Implementation/multiple_keys"
source create_fpga_project.tcl
```

### 2. **Build the Design**

```tcl
# In Vivado TCL Console:
build_all

# Or step-by-step:
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

### 3. **Program the FPGA**

- Open Hardware Manager
- Connect your board
- Program device with generated `.bit` file

---

## Board Interface

### **Inputs**

| Input          | Function | Description                                   |
| -------------- | -------- | --------------------------------------------- |
| **BTNC**       | Start    | Press to generate a key with current settings |
| **BTNU**       | Order+   | Increment Chebyshev polynomial order          |
| **BTND**       | Order-   | Decrement Chebyshev polynomial order          |
| **CPU_RESETN** | Reset    | System reset (active-low)                     |
| **SW[9:0]**    | GenSeed1 | Set seed value (0-1000, displayed on 7-seg)   |
| **SW[15:10]**  | Order    | Set Chebyshev order (1-63)                    |

### **Outputs**

| Output            | Function      | Description                            |
| ----------------- | ------------- | -------------------------------------- |
| **LED[0]**        | Processing    | Blinks while computing key             |
| **LED[1]**        | Key Ready     | Solid when key generation complete     |
| **LED[7:2]**      | Order Display | Shows current Chebyshev order (binary) |
| **LED[15:8]**     | Key Hash      | Lower 8 bits of generated 256-bit key  |
| **7-Seg Display** | GenSeed1      | Shows current seed value in decimal    |

---

## Usage Instructions

### **Generate a Key**

1. **Set GenSeed1 Value:**

   - Use switches SW[9:0] to set a value from 0-1000
   - The 7-segment display shows the value in decimal
   - Example: `0000000100` (binary) = 100 (decimal) = 0.1 scaled

2. **Set Chebyshev Order:**

   - Use switches SW[15:10] OR buttons BTNU/BTND
   - Sets polynomial order n (1-100)
   - LED[7:2] displays current order in binary

3. **Generate Key:**

   - Press **BTNC** (center button)
   - LED[0] will blink during computation
   - LED[1] will light solid when complete
   - LED[15:8] shows lower 8 bits of the hash

4. **View Results:**
   - The 256-bit key is generated internally
   - LED[15:8] displays `key_out[7:0]` for verification
   - Full key available in internal signals (view in ChipScope/ILA)

---

## Example Workflow

### **Generate K1 = H(T1(100))**

```
1. Set SW[9:0] = 0000000100 (decimal 100, represents 0.1)
2. Set SW[15:10] = 000001 (order = 1) OR press BTND until LED[7:2] = 000001
3. Press BTNC
4. Wait for LED[1] to turn ON (key ready)
5. Check LED[15:8] for hash verification
```

### **Generate K2 = H(T2(100))**

```
1. Keep SW[9:0] = 0000000100 (same seed)
2. Press BTNU once (order increments to 2)
3. Press BTNC
4. Wait for LED[1] ON
5. LED[15:8] will show different hash than K1
```

### **Generate Multiple Keys**

```
Repeat above process, incrementing order each time:
- K1 = H(T1(100))
- K2 = H(T2(100))
- K3 = H(T3(100))
...
- K100 = H(T100(100))
```

---

## Architecture Details

### **Key Generation Formula**

```
Kn = H(Tn(genseed1))

Where:
- Kn: Generated key (256-bit SHA-256 hash)
- H(): SHA-256 hash function
- Tn(): Chebyshev polynomial of order n
- genseed1: Input seed value (0-1000, scaled from 0.0-1.0)
- n: Polynomial order (1-100)
```

### **Processing Pipeline**

```
IDLE → CHEBYSHEV_COMPUTE → SHA_COMPUTE → IDLE
  ↓           ↓                  ↓           ↓
Setup      Compute Tn(x)     Hash result   Ready
(1 cycle)   (~1 cycle)       (~64 cycles)  (1 cycle)

Total: ~69 clock cycles per key @ 100 MHz = 690 ns
```

### **Resource Utilization (Estimated)**

| Resource  | Usage  | Available (Basys3) | Utilization |
| --------- | ------ | ------------------ | ----------- |
| LUTs      | ~3,500 | 20,800             | ~17%        |
| FFs       | ~2,000 | 41,600             | ~5%         |
| Block RAM | 0      | 50                 | 0%          |
| DSPs      | 0      | 90                 | 0%          |

_Note: Actual values may vary. Run `show_utilization` in Vivado for exact numbers._

---

## Timing Specifications

### **Clock Frequency**

- **System Clock**: 100 MHz (10 ns period)
- **Target**: All paths meet timing at 100 MHz
- **Margin**: Designed for >20% timing margin

### **Key Generation Speed**

- **Cycles per key**: ~69 cycles
- **Time per key**: ~690 ns @ 100 MHz
- **Throughput**: ~1.45 million keys/second

---

## Board Selection

### **Currently Configured: Basys3**

The project is set up for Basys3 by default. To change boards:

#### **For Nexys A7:**

1. Open `create_fpga_project.tcl`
2. Comment out Basys3 line:
   ```tcl
   # set fpga_part "xc7a35tcpg236-1"
   ```
3. Uncomment Nexys A7 line:
   ```tcl
   set fpga_part "xc7a50ticsg324-1L"  # For Nexys A7-50T
   # OR
   set fpga_part "xc7a100tcsg324-1"   # For Nexys A7-100T
   ```
4. Open `fpga_constraints.xdc`
5. Comment out Basys3 section
6. Uncomment Nexys A7 section

#### **For Arty A7:**

1. Similar process, use:
   ```tcl
   set fpga_part "xc7a35ticsg324-1L"  # Arty A7-35T
   # OR
   set fpga_part "xc7a100tcsg324-1"   # Arty A7-100T
   ```
2. Add Arty-specific constraints (buttons/LEDs differ)

---

## Debugging and Verification

### **Check Synthesis Results**

```tcl
open_run synth_1
report_utilization -file synth_utilization.rpt
report_timing_summary -file synth_timing.rpt
```

### **Check Implementation Results**

```tcl
open_run impl_1
report_timing_summary -file impl_timing.rpt
report_utilization -file impl_utilization.rpt
```

### **Verify Timing**

```tcl
check_timing
# Should show WNS (Worst Negative Slack) >= 0
```

### **Add Integrated Logic Analyzer (ILA)**

To view the full 256-bit key output:

1. Add ILA core to project
2. Connect to `key_out` signal
3. Trigger on `key_ready`
4. Capture and view 256-bit hash in hex

---

## Troubleshooting

### **Problem: Timing Violation (WNS < 0)**

**Solution:**

- Reduce clock frequency in constraints
- Enable more aggressive optimization strategies
- Add pipeline registers in critical paths

### **Problem: No LED Activity**

**Solution:**

- Check reset button (must be released)
- Verify switches are in valid range
- Press BTNC to start generation
- Check board power and USB connection

### **Problem: Synthesis Errors**

**Solution:**

- Verify all source files are added
- Check file paths in TCL script
- Ensure SHA-256 package is included
- Review error messages for missing dependencies

### **Problem: Different Hash Than Simulation**

**Solution:**

- Verify genseed1 and order values match simulation
- Check that implementation uses same formula: Kn = H(Tn(genseed1))
- Ensure no random value is being added

---

## Performance Optimization

### **To Increase Throughput:**

1. **Higher Clock Frequency:**

   - Modify constraints to use faster clock (if board supports)
   - May require additional pipeline stages

2. **Parallel Processing:**

   - Instantiate multiple `generate_key` modules
   - Generate multiple keys simultaneously
   - Area cost: Linear with number of instances

3. **Pipelined SHA-256:**
   - Add pipeline registers in SHA computation
   - Reduces critical path, allows higher frequency

---

## File Structure

```
multiple_keys/
├── create_fpga_project.tcl      # Project creation script
├── fpga_constraints.xdc         # Pin assignments and timing
├── fpga_top.vhd                 # Top-level FPGA wrapper
├── generate_key.vhd             # Key generation module
├── chebyshev1.vhd               # Chebyshev polynomial
├── sha_256.vhd                  # SHA-256 hash engine
├── sha_256_pkg.vhd              # SHA-256 constants/functions
└── fpga_project/                # Generated project (after TCL run)
    ├── key_generator_fpga.xpr   # Vivado project file
    └── ...
```

---

## Additional Resources

### **Vivado Commands Reference**

```tcl
# Build everything
build_all

# Check timing
check_timing

# Show utilization
show_utilization

# Open implemented design
open_run impl_1

# Generate reports
report_timing_summary
report_utilization
report_power
```

### **Hardware Manager Commands**

```tcl
# Open hardware manager
open_hw_manager

# Auto-connect to board
connect_hw_server
open_hw_target

# Program device
set_property PROGRAM.FILE {fpga_project/key_generator_fpga.runs/impl_1/fpga_top.bit} [get_hw_devices]
program_hw_devices [get_hw_devices]
```

---

## Support

For issues or questions:

1. Check Vivado message console for errors
2. Review synthesis/implementation reports
3. Verify board connections and power
4. Check constraint file matches your board model

---

**End of FPGA Implementation Guide**
