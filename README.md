# eVTOL Key Matrix Generator - FPGA Implementation

This project implements a hierarchical key generation scheme for eVTOL drone authentication using Chebyshev chaotic maps and cryptographic hash functions. Based on the research paper "FPGA-Based Authentication Scheme for eVTOL Drones Using Chaotic Maps".

## Overview

The implementation provides a memory-efficient streaming architecture for generating large-scale key matrices (1 vendors × 1 eVTOLs × 800 keys = 800 keys) without storing all keys in memory. Three implementation variants are provided with different hash output sizes.

### Key Features

- **Hierarchical 3-Level Architecture**: Vendor seeds → eVTOL seeds → Authentication keys
- **Streaming Output**: Keys generated on-the-fly, no bulk storage required
- **Memory Efficient**: ~324 Kb vs 256+ Mb with full storage
- **Multiple Hash Variants**: SHA-512, SHA-256, and SHA-128 (truncated) implementations
- **Chebyshev Chaotic Maps**: Provides unpredictable key sequences

## Optimized SHA-256 version

[`sha_256_optimized/`](sha_256_optimized/) restructures the SHA-256 variant: one hash round per clock, a 16-word on-the-fly message schedule, Chebyshev maps mod 2³¹−1, and two SHA cores fed round-robin while the next key's Chebyshev value is computed. It generates the 800 keys in 27,638 cycles instead of 168,011 and closes timing at 130 MHz instead of 3.4 MHz on the Artix-7, so it is **about 230× faster in wall-clock time** with a third of the LUTs. Every key is standard FIPS 180-4 SHA-256, checked against Python's `hashlib`. Details, results and the reproduction script are in its [README](sha_256_optimized/README.md).

## Project Structure

```
FPGA_based_authentication/
├── Sha_512_Implementation/       # 512-bit key output
│   ├── chebyshev1.vhd           # Chebyshev polynomial module
│   ├── top_module_matrix_streaming.vhd    # Main streaming key generator
│   ├── tb_top_module_matrix_streaming.vhd # Testbench
│   ├── sha_512_core.vhd         # SHA-512 hash core
│   ├── sha_512_pkg.vhd          # SHA-512 constants/types
│   └── key_matrix_pkg_streaming.vhd       # Key matrix configuration
│
├── sha_256_implementation/       # 256-bit key output
│   ├── chebyshev1.vhd
│   ├── top_module_matrix_streaming.vhd
│   ├── tb_top_module_matrix_streaming.vhd
│   ├── sha_256.vhd              # SHA-256 hash core
│   ├── sha_256_pkg.vhd
│   └── key_matrix_pkg_streaming.vhd
│
└── sha_128_implementation/       # 128-bit key output (truncated SHA-256)
    ├── chebyshev1.vhd
    ├── top_module_matrix_streaming.vhd
    ├── tb_top_module_matrix_streaming.vhd
    ├── sha_256.vhd
    ├── sha_256_trunc128.vhd     # SHA-256 with 128-bit truncation
    ├── sha_256_pkg.vhd
    └── key_matrix_pkg_streaming.vhd
```

## Architecture

### 3-Level Hierarchical Key Generation

| Level   | Description         | Storage                    | Output                  |
| ------- | ------------------- | -------------------------- | ----------------------- | --- | --------- |
| Level 1 | Vendor Seeds        | 100 × 32-bit = 3.2 Kb      | `T_n(GenSeed) + Rv`     |
| Level 2 | eVTOL Seeds         | 10,000 × 32-bit = 320 Kb   | `T_n(VendorSeed) + Rev` |
| Level 3 | Authentication Keys | **Streaming (no storage)** | `SHA(T_n(eVTOL_Seed)    |     | indices)` |

### State Machine Flow

```
IDLE → LEVEL1_CHEBY_COMPUTE → LEVEL1_ADD_RANDOM → LEVEL1_STORE
                                                       ↓
     LEVEL2_STORE ← LEVEL2_ADD_RANDOM ← LEVEL2_CHEBY_COMPUTE
           ↓
     LEVEL3_CHEBY_WAIT → LEVEL3_CHEBY_COMPUTE → LEVEL3_SHA_COMPUTE
           ↑                                           ↓
           └──────────────── LEVEL3_STREAM ←──────────┘
                                   ↓
                              COMPLETE
```

### Mathematical Foundation

**Chebyshev Polynomial Recurrence:**

```
T_0(x) = 1
T_1(x) = x
T_n(x) = 2x·T_{n-1}(x) - T_{n-2}(x)
```

**Key Generation:**

```
VendorSeed[v] = T_{v+2}(GenSeed) + Rv
eVTOL_Seed[v,e] = T_{e+2}(VendorSeed[v]) + Rev
Key[v,e,k] = SHA(T_{k+2}(eVTOL_Seed[v,e]) || v || e || k)
```

## Getting Started

### Prerequisites

- Xilinx Vivado 2020.1 or later
- Target FPGA: Xilinx (Zynq-7000 series or similar)
- VHDL-2008 support

### Simulation Setup

1. **Create New Vivado Project**
2. **Add Source Files** from your chosen implementation directory:
   - `chebyshev1.vhd`
   - `sha_*.vhd` (hash implementation)
   - `*_pkg.vhd` (packages)
   - `top_module_matrix_streaming.vhd`
3. **Add Simulation Sources**:
   - `tb_top_module_matrix_streaming.vhd`
4. **Set Top Module**: `top_module_matrix_streaming`
5. **Run Behavioral Simulation**

### Configuration

Edit `key_matrix_pkg_streaming.vhd` to adjust matrix dimensions:

```vhdl
constant NUM_VENDOR_VARIANTS : integer := 1;   -- Number of vendors
constant NUM_EVTOL_PER_VARIANT : integer := 1; -- eVTOLs per vendor
constant NUM_KEYS_PER_EVTOL : integer := 800;    -- Keys per eVTOL
constant HASH_WIDTH : integer := 256;            -- Output key width
```

## Interface

### Port Description

| Port              | Direction | Width       | Description                        |
| ----------------- | --------- | ----------- | ---------------------------------- |
| `clk`             | in        | 1           | System clock                       |
| `rst`             | in        | 1           | Active-high reset                  |
| `start`           | in        | 1           | Start key generation               |
| `genseed1`        | in        | integer     | Initial generation seed (0-1000)   |
| `processing`      | out       | 1           | High during key generation         |
| `level1_done`     | out       | 1           | Level 1 (vendor seeds) complete    |
| `level2_done`     | out       | 1           | Level 2 (eVTOL seeds) complete     |
| `level3_done`     | out       | 1           | All keys generated                 |
| `key_valid`       | out       | 1           | Current key output is valid        |
| `current_key_out` | out       | 128/256/512 | Generated key (depends on variant) |
| `current_vendor`  | out       | integer     | Current vendor index               |
| `current_evtol`   | out       | integer     | Current eVTOL index                |
| `current_key`     | out       | integer     | Current key index                  |

### Usage Example

```vhdl
-- Instantiate key generator
key_gen_inst : entity work.top_module_matrix_streaming
    port map (
        clk             => clk,
        rst             => rst,
        start           => start_signal,
        genseed1        => 500,  -- Initial seed
        processing      => busy,
        level3_done     => done,
        key_valid       => valid,
        current_key_out => generated_key,
        -- ... other ports
    );

-- Key capture process
process(clk)
begin
    if rising_edge(clk) then
        if valid = '1' then
            -- Process/transmit generated_key
        end if;
    end if;
end process;
```

## Memory Footprint

| Component     | Storage     | Notes                        |
| ------------- | ----------- | ---------------------------- |
| Level 1 Seeds | 3.2 Kb      | 100 vendors × 32 bits        |
| Level 2 Seeds | 320 Kb      | 10,000 eVTOLs × 32 bits      |
| Level 3 Keys  | 0           | Streaming output             |
| **Total**     | **~324 Kb** | vs 256+ Mb with full storage |

## Implementation Variants

| Variant | Key Size | Hash Algorithm      | Use Case                      |
| ------- | -------- | ------------------- | ----------------------------- |
| SHA-512 | 512-bit  | SHA-512             | Maximum security              |
| SHA-256 | 256-bit  | SHA-256             | Balanced security/performance |
| SHA-128 | 128-bit  | SHA-256 (truncated) | Resource-constrained          |

## Security Considerations

### Implemented Features

- **Vendor Isolation**: Separate key spaces per vendor
- **Chaotic Properties**: Unpredictable sequences from Chebyshev maps
- **Cryptographic Hashing**: Industry-standard SHA algorithms

### Production Recommendations

1. **True Random Seeds**: Use hardware TRNG for `genseed1`
2. **Side-Channel Protection**: Add masking/shuffling for sensitive operations
3. **Key Storage**: Implement secure storage for vendor/eVTOL seeds
4. **Secure Boot**: Protect FPGA bitstream integrity

## References

1. Research Paper: "Key-Based Authentication Scheme for eVTOL Drones Using Chebyshev Chaotic Maps"
2. FIPS 180-4: Secure Hash Standard (SHA)
3. Chebyshev Polynomials: Mathematical properties and cryptographic applications

## License

This implementation is provided for educational and research purposes. For commercial deployment in eVTOL systems, ensure compliance with relevant aviation security standards and regulations.
