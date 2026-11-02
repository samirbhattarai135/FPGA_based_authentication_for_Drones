# SHA-256 key generator, restructured for throughput

This folder rebuilds the `sha_256_implementation` key generator in hand-written VHDL-2008. On the Nexys A7's Artix-7 it closes timing at **130 MHz**, where the original reaches 3.4 MHz, and it needs **6.1× fewer clock cycles** for the same 800-key stream. Together that is about **230× faster in wall-clock time with a third of the LUTs and an eighth of the DSPs**. Each key is now standard FIPS 180-4 SHA-256 and is checked bit-for-bit against Python's `hashlib`. The original folder is left untouched so the two versions can be compared.

The two main changes follow the ones in AMD's [LLM-aided HLS dataflow optimization of SHA-256](https://www.amd.com/en/developer/resources/technical-articles/2026/llm-aided-hls-dataflow-optimization-a-sha-256.html), done here in RTL instead of Vitis HLS:

| AMD (Vitis HLS, Alveo U200) | This design (VHDL RTL, Artix-7) |
|---|---|
| Merge preprocessing and message-schedule stages | Message schedule is a 16-word sliding window updated during the rounds, with no separate schedule stage |
| Digest loop at II=1 | One SHA-256 round per clock (was three) |
| Two-way block parallelism with dispatch/collect | `NUM_CORES` SHA cores fed round-robin and drained in the same order |

## Results

800 keys, `genseed = 500`, cycles counted from start to the last key. Cycles come from cycle-accurate simulation (nvc); area and clock from Vivado 2024.2 out-of-context place and route on xc7a100tcsg324-1 (`vivado/compare.tcl`).

| | Original | Optimized, 2 cores |
|---|---|---|
| Max clock (post-route) | 3.4 MHz | 130.5 MHz |
| Critical path | 291 ns, 272 logic levels (31 chained DSP48s) | 7.7 ns, one DSP48 cascade |
| Total cycles | 168,011 | 27,638 |
| Time for 800 keys | 48.9 ms at 3.4 MHz | 0.212 ms at 130 MHz (0.276 ms at 100 MHz) |
| Speedup | 1.0× | **231×** (177× at 100 MHz) |
| Slice LUTs | 9,707 | 3,539 |
| Flip-flops | 2,737 | 2,890 |
| DSP48E1 | 93 | 12 |
| SHA-256 cycles per 512-bit block | ~200 | 66 per core |
| Output checked against a reference | No | 800/800 vs `hashlib` |

With one SHA core the optimized design takes 55,230 cycles (69 per key, 3.0× fewer than the original).

The original was reported at 1.68 ms, which is its 168,011 cycles at the Nexys A7's 100 MHz clock. Its Chebyshev unit evaluates the whole polynomial loop in one clock, so place and route shows it cannot run above 3.4 MHz, and on the board it would need about 48.9 ms. The optimized Fmax comes from a run constrained to 6 ns (`-tclargs 6.0`, which is also where both designs' numbers in this table come from): the worst path took 7.66 ns, so 100 MHz closes with 2.3 ns of slack. That path is the 31×31-bit multiply, which spans four cascaded DSP48s, in the Chebyshev seed unit.

`run_sim.sh` reproduces the cycle counts. `tb/tb_original_cycles.vhd` measures the original, because the original folder's testbench imports `sha_512_pkg` and does not compile. nvc stops on the original's integer overflow, so the script simulates it with 32-bit wraparound, which is what synthesized hardware does. The cycle count doesn't depend on those values, because `chebyshev1` returns in one clock whatever it computes.

## What changed and why

**`sha256_core.vhd`: one round per clock**
- The original core spent three states per round: compute T1/T2, rotate a–h, then increment the counter. All of that now happens in one cycle.
- `h + K[t] + W[t]` and `d + h + K[t] + W[t]` are summed a round early, since the next round's `h` is this round's `g`. The remaining additions for the new `a` and `e` go through carry-save adders, so each needs one carry chain instead of up to four in series.
- The original built all 64 schedule words up front as one combinational chain, then registered them over four states. `W[t+16]` needs only `W[t..t+14]`, so a 16-word window that shifts every round replaces both. That removes the 2,048-bit `W` register file, the four `PREP_MSG_SCHEDULE` states and a long combinational path.
- Latency is 66 cycles per block: load, 64 rounds, final add. It passes the FIPS 180-4 vectors for "abc", the empty message, and the 448-bit two-block message, which also exercises chaining.

**`modp_pkg.vhd`, `chebyshev_modp.vhd`, `chebyshev_stream.vhd`: Chebyshev polynomials mod p = 2³¹ − 1**
- The original `chebyshev1` used 32-bit `integer` arithmetic. `2·x·T` overflows within a few iterations; nvc stops with a fatal error, and synthesized hardware silently wraps.
- Its loop capped the degree at 32, but key `k` asks for degree `k+2`. So keys 30 to 799 all received the same T value and differed only through `k` in the hash input.
- Its loop is also fully unrolled into one clock cycle: 31 multiplies in series, which is what limits it to 3.4 MHz.
- Working mod a prime is the standard integer form of Chebyshev-map cryptography. Values stay bounded, any degree is valid, and the semigroup property `T_m(T_n(x)) = T_mn(x)` holds.
- Reduction mod 2³¹ − 1 needs no divider: a product folds as low half plus high half, and doubling is a 31-bit rotate. Each modular add or subtract computes both candidate results side by side and muxes, so every stage has at most one carry chain.
- The vendor and eVTOL seeds use fast doubling (`T_2k = 2T_k² − 1`, `T_2k+1 = 2·T_k·T_k+1 − x`): four pipelined cycles per bit of `n`.
- The streamed keys need consecutive degrees of one seed, so `chebyshev_stream` uses the recurrence `T_m+1 = 2x·T_m − T_m-1`: one multiply and four cycles per key, well under the 66 cycles a SHA core spends on it.

**`key_stream_top.vhd`: overlapped stages**
- Level 3 is a three-stage stream: `chebyshev_stream`, then a one-entry slot, then `NUM_CORES` SHA cores, then ordered output. The next key's T value is computed while earlier keys are hashing.
- Cores start in round-robin order and share one fixed latency, so collecting in the same order keeps keys in index order without a reorder buffer.
- The 16-byte message `T ‖ v ‖ e ‖ k` gets FIPS padding. The original hashed it with the padding bit and length field left as zeros, so its output wasn't SHA-256 of the message.

Because of the mod-p fix, the optimized design produces different key values from the original by design. `model/key_model.py` is the specification: it uses the plain Chebyshev recurrence rather than fast doubling, and `hashlib` for SHA-256.

## Running it

```sh
./run_sim.sh                                         # needs nvc and python3
cd vivado && vivado -mode batch -source compare.tcl  # area and Fmax, original vs optimized
```

`run_sim.sh` runs the FIPS vectors, then the full 800-key stream with 1 and 2 cores, comparing every key against the model.

## Files

| File | Purpose |
|---|---|
| `sha256_core.vhd` | One-round-per-cycle SHA-256 compression engine |
| `modp_pkg.vhd` | Arithmetic mod 2³¹−1 |
| `chebyshev_modp.vhd` | T_n(x) mod 2³¹−1 by fast doubling (vendor and eVTOL seeds) |
| `chebyshev_stream.vhd` | Consecutive T_n(x) mod 2³¹−1 by recurrence (per-key values) |
| `key_stream_top.vhd` | Three-level key generator with overlapped Chebyshev / SHA stages |
| `tb/tb_sha256_core.vhd` | FIPS 180-4 vectors and the latency check |
| `tb/tb_key_stream.vhd` | Full key stream, cycle count, writes `keys_out.txt` |
| `tb/tb_original_cycles.vhd` | Cycle count of the original design (the baseline) |
| `model/key_model.py` | Golden model and checker |
| `vivado/compare.tcl` | Out-of-context synthesis and implementation of both designs on xc7a100tcsg324-1 |

Shared from `../sha_256_implementation`: `sha_256_pkg.vhd` (SHA-256 functions) and `key_matrix_pkg_streaming.vhd` (matrix size).
