# Building and checking the experimental source

## Toolchain and projects

Use **Quartus Prime Lite 25.1std.0, Build 1129** with Cyclone V support.
The fitted device is `5CSEBA6U23I7`. Put `quartus_sh` and `quartus_sta` on PATH,
or invoke their installed paths. Start from this clean source tree, without
copied compiler databases. No private history or device-access tools are needed.

The exported hardware files retain the completed Dual compiler inputs byte for
byte. The Single project wrapper comes from the matched completed Single build;
its shared HDL is identical, but the original board frameworks differ:

- `PSX_HQ2X_DualSDRAM`: original Dual SDRAM framework, SDRAM2 SPU option;
  selected experimental build for a two-module MiSTer.
- `PSX_HQ2X`: original Single analog/HDMI framework, DDR3 SPU RAM; **not timing
  qualified and not hardware validated** in this release.

Both HQ wrappers enable `PSX_HQ2X`, use four parallel workers, and retain the
scoped MAX16 and FIFO buffer-preservation assignments. Their compiled wrappers
write `output_files`. The original declared range remains -40..100C.
No clocks/SDC exceptions were relaxed and no MIN0 override or additional output
split was introduced. Quartus 25.1's fitted initial placement seed was **1**
(the unchanged default). Check the seed/worker values in your fitted report.

Optional source-integrity check, using Python 3:

```sh
python tools/check_source.py
```

Build one project at a time from the repository root:

```sh
quartus_sh --flow compile PSX_HQ2X_DualSDRAM
```

The experimental RBF is `output_files/PSX_HQ2X_DualSDRAM.rbf`.
For research on the unqualified Single variant, use the same command with
`PSX_HQ2X`. Do not treat its successful compilation as timing qualification.

The frozen `build_id.v` records the released build date. The upstream
`sys/build_id.tcl` regenerates it using the current date during a rebuild.
Tool revision, generated dates and place-and-route results can affect binary
identity: these instructions do not promise the validated release RBF hash.
Do not publish a new RBF as validated solely because its build exits zero.

## Post-fit timing reports

The portable reporting Tcl preserves project constraints and queries **all**
available operating conditions. Run it only after fitting has completed, with
no concurrent build/STA job using that project database. Use a new output
folder for every command, and run the following serially:

```sh
quartus_sta -t tools/report_timing.tcl PSX_HQ2X_DualSDRAM.qpf PSX_HQ2X_DualSDRAM timing-full 20 full
quartus_sta -t tools/report_timing.tcl PSX_HQ2X_DualSDRAM.qpf PSX_HQ2X_DualSDRAM timing-focused 64 clock-paths
quartus_sta -t tools/report_timing.tcl PSX_HQ2X_DualSDRAM.qpf PSX_HQ2X_DualSDRAM timing-reset 20 reset-chain
```

Review setup/hold, recovery/removal, minimum pulse width, clocks/transfers,
ignored SDC, unconstrained paths and `check_timing`. The expected model set is
Slow/Fast at -40/0/85/100C, 1100 mV. A REPORTS_GENERATED marker only confirms
collection. Negative checks remain failures; the release explicitly retains
its -40C miss. The selected pass covers only the discrete 0/85/100C internal
checks. Existing external-I/O and other coverage limits are not a complete
board electrical signoff. The first 20/64 printed paths are report limits,
not constraints limiting the global timing search to those endpoints.

## Focused streaming simulations

`sim/hq2x` extracts the actual filter selection block from `PSX.sv` and uses
the shared HQ2X/scandoubler engine. Node.js prepares Icarus-compatible simulation
copies; production HDL is not edited. With Node.js, Python 3 and Icarus Verilog
installed on PATH:

```sh
python sim/hq2x/run-native.py
python sim/hq2x/run-native.py --only differential
```

The five suites cover waveform/geometry, enable and bypass controls, short-VS
switching, spatial patterns/gamma, comparison with stock MiSTer video_mixer,
and reset/rearming. They include the normal pixel divisors 4/5/7/8/10. The
shared-engine differential test verifies integration, not an independent
specification of all HQ2X blend rules. These benches are not a full PSX
simulation, FPGA timing analysis, or a substitute for artifact-specific hardware
checks. Generated sources, executables and manifests stay in ignored
`sim/hq2x/generated/`. The portable native runner is provided for convenience;
the original recorded regression used the same benches with an Icarus WASM
runtime. No simulator binaries are bundled and no tool is downloaded by scripts.

## Source changes

The integration adds status bit 93 and a progressive-only HQ2X stream after
gamma. Original timing/gun inputs retain their native pixel enable. Enable
requests are committed in common blanking after priming; unsafe output modes
bypass. A registered core reset crosses into VIDEO through two synchronizer
stages. The shared HQ2X arithmetic is unchanged.

Timing work keeps the original scaler pipeline, narrows one guarded unsigned
row decrement, limits adaptive-selector fanout, and adds a default-off FIFO
write-address bit-1 identity-buffer option enabled only on memorymux.iwritefifo.
The buffer adds no cycle. Source KEEP/LCELL directives do not by themselves
prove the named physical implementation; that supplemental audit is unproved.

Unused legacy upstream simulation projects are omitted from this clean export.
The core build inputs and focused portable HQ2X benches remain included.
