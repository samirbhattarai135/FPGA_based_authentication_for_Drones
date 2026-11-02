#!/usr/bin/env bash
# Simulates the optimized design with nvc (https://github.com/nickg/nvc):
#   1. sha256_core against FIPS 180-4 vectors
#   2. the full key stream for 1 and 2 SHA cores, each checked key-by-key against model/key_model.py
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
base="$here/../sha_256_implementation"
build="$here/build"
mkdir -p "$build"
cd "$build"

nvc --std=2008 -a \
    "$base/sha_256_pkg.vhd" "$base/key_matrix_pkg_streaming.vhd" \
    "$here/modp_pkg.vhd" "$here/sha256_core.vhd" "$here/chebyshev_modp.vhd" \
    "$here/chebyshev_stream.vhd" "$here/key_stream_top.vhd" \
    "$here/tb/tb_sha256_core.vhd" "$here/tb/tb_key_stream.vhd"

echo "== sha256_core: FIPS 180-4 vectors"
nvc --std=2008 -e tb_sha256_core -r 2>&1 | grep -E "PASS|FAIL|PASSED|latency"

for cores in 1 2; do
    echo "== key_stream_top: NUM_CORES=$cores"
    nvc --std=2008 -e tb_key_stream -gNUM_CORES=$cores -r 2>&1 | grep -E "RESULT|Error|Failure" | sed 's/^.*RESULT/RESULT/'
    python3 "$here/model/key_model.py" --check keys_out.txt
done

# Baseline: the original design, with chebyshev1's integer arithmetic wrapped to
# 32 bits (see tb/tb_original_cycles.vhd for why).
echo "== original design (sha_256_implementation)"
sed -e 's/variable Tn : integer := 0;/variable Tn : integer := 0;\n        variable p : signed(63 downto 0);/' \
    -e 's/Tn := 2 \* x_in \* T1 - T0;/p := resize(to_signed(x_in, 32) * to_signed(T1, 32), 64);\n                Tn := to_integer(resize(shift_left(p, 1) - to_signed(T0, 64), 32));/' \
    "$base/chebyshev1.vhd" > chebyshev1_wrap32.vhd
nvc --std=2008 --work=orig -a \
    "$base/sha_256_pkg.vhd" "$base/key_matrix_pkg_streaming.vhd" chebyshev1_wrap32.vhd \
    "$base/sha_256.vhd" "$base/top_module_matrix_streaming.vhd" "$here/tb/tb_original_cycles.vhd"
nvc --std=2008 --work=orig -e tb_original_cycles -r 2>&1 | grep "RESULT" | sed 's/^.*RESULT/RESULT/'
