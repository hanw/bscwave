#!/usr/bin/env bash
# Builds libsim.so for this example by:
#   1. Running bsc on Counter.bsv to generate the model + sim runtime
#   2. Linking the bsc-generated model objects with bscwave's generic
#      bsim_wrapper into libsim.so, which the Haskell executable links.

set -euo pipefail

cd "$(dirname "$0")"

# Derive BLUESPECDIR from `bsc` on PATH if not already set
if [ -z "${BLUESPECDIR:-}" ]; then
  BLUESPECDIR="$(dirname "$(dirname "$(command -v bsc)")")/lib"
fi
BSC_INC="$BLUESPECDIR/Bluesim"

WRAPPER="$(cd .. && pwd)/../csrc/bsim_wrapper.cxx"

cd src

# 1. bsc compile + link to bluesim runtime
bsc -sim -g mkCounter -u Counter.bsv
bsc -sim -e mkCounter -o sim.so mkCounter.ba

# 2. Build libsim.so = bscwave wrapper + model objects, dynamically linked
#    against bsc's Bluesim runtime (sim.so.so).
g++ -shared -fPIC \
  -I"$BSC_INC" \
  "$WRAPPER" \
  model_mkCounter.o mkCounter.o \
  -L. -l:sim.so.so -ldl \
  -Wl,-rpath,'$ORIGIN' \
  -o libsim.so

cd ..
ln -sf src/libsim.so libsim.so

# 3. Generate the typed port record from the bsc-emitted .cxx so the
#    testbench can reference inputs/outputs by name with widths checked
#    at compile time.
(cd ../.. && cabal --project-dir=. run -v0 bscwave-gen-ports -- \
   examples/counter-tb/src/mkCounter.cxx \
   -o examples/counter-tb/app/MkCounter.hs)

echo
echo "Built. Now run:   LD_LIBRARY_PATH=./src cabal run testbench"
