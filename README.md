# bscwave

Drive [Bluespec](https://github.com/B-Lang-org/bsc) simulations from Haskell
and render terminal waveforms, in the spirit of Jane Street's
[hardcaml_waveterm](https://github.com/janestreet/hardcaml_waveterm) — but
targeting bsc-generated Bluesim models instead of Hardcaml circuits.

```
┌Signals────────┐┌Waves───────────────────────────────────────────┐
│clock          ││┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   │
│               ││    └───┘   └───┘   └───┘   └───┘   └───┘   └───│
│EN_clear       ││                        ┌───────┐               │
│               ││────────────────────────┘       └───────────────│
│EN_incr        ││        ┌───────────────┐                       │
│               ││────────┘               └───────────────────────│
│               ││────────────────┬───────┬───────┬───────────────│
│count          ││ 00             │01     │02     │00             │
│               ││────────────────┴───────┴───────┴───────────────│
│               ││                                                │
└───────────────┘└────────────────────────────────────────────────┘
```

## Layout

- `src/Bscwave/` — Haskell library
  - `FFI` — foreign imports for the `bsim_*` C ABI
  - `Sim` — port table, step function. A captured cycle reflects the
    register state from the *previous* posedge (matches Hardcaml
    `Cyclesim` semantics — input at cycle K affects `dout` at K+1).
  - `Waveform` — sample capture for inputs and outputs
  - `Render` — terminal renderer: two-line clock, two-line binaries,
    three-line multi-bit values with run-merging and zero-padded hex
- `csrc/bsim_wrapper.cxx` — generic C++ shim over the Bluesim `bk_*`
  kernel API. One wrapper for any bsc design; uses
  `dlsym(RTLD_DEFAULT, "new_MODEL_<name>")` for the model factory and
  `bk_lookup_symbol` for port access.
- `examples/counter-tb/` — runnable example, see below

## Example: counter-tb

```bash
cd examples/counter-tb
./build.sh                              # bsc + g++ → libsim.so
LD_LIBRARY_PATH=./src cabal run testbench
```

The testbench drives an 8-bit counter (`Counter.bsv`) with a sequence of
`clear`/`incr` inputs and prints the waveform above.

## Port name convention

`Sim.create` takes the model name (for `dlsym`) plus port lists keyed by
bsc symbol-table names — not BSV interface names:

- Input `Action` method `foo` → symbol `EN_foo` (the enable signal)
- `Reg#(t)` named `bar` → symbol `bar` (the wrapper auto-descends from
  the register module to its inner value)

To discover the exact names for your design, grep
`init_symbol(...)` in `<top>.cxx` after the first `bsc -sim` run.

## Dependencies

- GHC 9.6+ with cabal
- [bsc](https://github.com/B-Lang-org/bsc) on `PATH`
- `libgmp-dev`, `dl`, a recent g++
