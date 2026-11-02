"""Golden model for key_stream_top: prints one key per line as "v e k HEX".

Run with --check FILE to compare a simulation dump against the model.
Defaults match key_matrix_pkg_streaming.vhd (1 vendor, 1 eVTOL, 800 keys).
"""
import argparse
import hashlib
import struct
import sys

P = 2**31 - 1
RV, REV = 134, 256


def chebyshev(x: int, n: int) -> int:
    """T_n(x) mod P by the plain recurrence; independent of the RTL's fast doubling."""
    t0, t1 = 1, x % P
    if n == 0:
        return t0
    for _ in range(n - 1):
        t0, t1 = t1, (2 * x * t1 - t0) % P
    return t1


def keys(genseed: int, vendors: int, evtols: int, per_evtol: int):
    vendor_seeds = [(chebyshev(genseed, v + 2) + RV) % P for v in range(vendors)]
    for v in range(vendors):
        for e in range(evtols):
            seed = (chebyshev(vendor_seeds[v], e + 2) + REV) % P
            for k in range(per_evtol):
                message = struct.pack(">IIII", chebyshev(seed, k + 2), v, e, k)
                yield v, e, k, hashlib.sha256(message).hexdigest().upper()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--genseed", type=int, default=500)
    ap.add_argument("--vendors", type=int, default=1)
    ap.add_argument("--evtols", type=int, default=1)
    ap.add_argument("--keys", type=int, default=800)
    ap.add_argument("--check", help="simulation dump to compare against the model")
    args = ap.parse_args()

    expected = [f"{v} {e} {k} {h}" for v, e, k, h in keys(args.genseed, args.vendors, args.evtols, args.keys)]
    if not args.check:
        print("\n".join(expected))
        return 0

    with open(args.check) as f:
        got = [line.strip() for line in f if line.strip()]
    mismatches = [(i, x, y) for i, (x, y) in enumerate(zip(expected, got)) if x != y]
    if len(got) != len(expected) or mismatches:
        print(f"FAIL: {len(got)} keys from simulation, {len(expected)} expected, {len(mismatches)} mismatched")
        for i, x, y in mismatches[:5]:
            print(f"  line {i}: expected {x}\n          got      {y}")
        return 1
    print(f"PASS: all {len(expected)} keys match the model (SHA-256 from hashlib)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
