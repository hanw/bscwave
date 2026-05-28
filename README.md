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
  - `Interface` — `Port n` / `Bit n` with type-level widths, and the
    `Interface` typeclass that generated port records implement
  - `Sim` — `Sim i o` parameterised over typed input/output records;
    `create` enumerates ports via the `Interface` instances. A captured
    cycle reflects the register state from the *previous* posedge
    (matches Hardcaml `Cyclesim` semantics — input at cycle K affects
    `dout` at K+1).
  - `Waveform` — sample capture, driven by `traverseI_` over the same
    records
  - `Render` — terminal renderer: two-line clock, two-line binaries,
    three-line multi-bit values with run-merging and zero-padded hex
- `app/GenPorts.hs` — `bscwave-gen-ports` codegen. Parses the
  `init_symbol(...)` table in a bsc-emitted `<model>.cxx` and writes a
  Haskell module exposing `Inputs`/`Outputs` higher-kinded records
- `csrc/bsim_wrapper.cxx` — generic C++ shim over the Bluesim `bk_*`
  kernel API. One wrapper for any bsc design; uses
  `dlsym(RTLD_DEFAULT, "new_MODEL_<name>")` for the model factory and
  `bk_lookup_symbol` for port access.
- `examples/counter-tb/` — runnable example, see below

## Example: counter-tb

```bash
cd examples/counter-tb
./build.sh                              # bsc + g++ + bscwave-gen-ports
LD_LIBRARY_PATH=./src cabal run testbench
```

`build.sh` does three steps:

1. `bsc -sim` on `Counter.bsv` → model objects + `sim.so.so`
2. `g++` link → `libsim.so` (bscwave wrapper + model)
3. `bscwave-gen-ports mkCounter.cxx -o app/MkCounter.hs` → typed
   `Inputs`/`Outputs` records, one field per bsc symbol

The testbench drives the generated record:

```haskell
import qualified MkCounter as C

sim <- create @C.Inputs @C.Outputs C.modelName
let i = inputs sim
writePort (C.en_clear i) 1        -- :: Bit 1, masked to width
writePort (C.eN_incr  i) 0
simStep sim
```

Typos on port names and widths are caught at compile time:

- `C.en_clera i` → "Not in scope: ‘C.en_clera’ … Perhaps use ‘C.en_clear’"
- `writePort (C.count o) (0 :: Bit 1)` → "Couldn't match type ‘1’ with ‘8’"

## Writing a new testbench

1. Write your BSV module (e.g. `Foo.bsv` exporting `mkFoo`).
2. Run `bsc -sim -g mkFoo -u Foo.bsv && bsc -sim -e mkFoo -o sim.so mkFoo.ba`
   (or follow the pattern in `examples/counter-tb/build.sh`).
3. Run `bscwave-gen-ports mkFoo.cxx -o app/MkFoo.hs`. This produces
   `Inputs f` / `Outputs f` records with one field per port:
   - `SYM_PORT` entries (e.g. `EN_clear`) → input field, width from the
     symbol's bit count
   - `SYM_MODULE` entries (registers) → output field, width pulled from
     the C++ constructor call (`INST_count(simHdl, "count", this, 8u, …)`)
   - `SYM_DEF` (intermediate signals like `WILL_FIRE_*`) → skipped
4. Link `g++` to produce `libsim.so` (see counter-tb's `build.sh`).
5. Write `Main.hs`:
   ```haskell
   sim <- create @C.Inputs @C.Outputs C.modelName
   (waves, sim') <- Waveform.create sim
   writePort (C.<field> (inputs sim')) <value>
   simStep sim'
   ...
   Render.print waves
   ```
6. `cabal run testbench` with `LD_LIBRARY_PATH` pointing at `libsim.so`.

Regenerate `MkFoo.hs` whenever the BSV interface changes — the next
`cabal build` will fail to compile if a port was renamed or its width
changed.

## Dependencies

- GHC 9.6+ with cabal
- [bsc](https://github.com/B-Lang-org/bsc) on `PATH`
- `libgmp-dev`, `dl`, a recent g++
