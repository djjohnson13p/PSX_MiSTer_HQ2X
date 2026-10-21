# Experimental PSX HQ2X for MiSTer

An optional full-color HQ2X path for the MiSTer PlayStation core. This is an
experimental source release based on [PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer)
at public upstream commit `cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3`.

**The selected build is Dual SDRAM and requires two SDRAM modules.** It fits
without an additional analog-only/HDMI-only split and passed the bounded tests
below. Single source is included for development: it fits, but the matched
Single build misses timing and has not been hardware validated.

## Using the filter

Open **Video & Audio -> HQ2x (240p/288p)** and select **On**. **Off** retains the
native pixel path. Switching may take a few frames while timing settles.
HQ2X runs after gamma and doubles eligible progressive video in both axes,
including the different horizontal resolutions. It is separate from texture
filtering and the final HDMI scaler.

The native path is retained for interlaced/high-vertical-resolution output,
direct framebuffer mode, the 480p hack, fast-forward, Direct Video and
GunCon/Justifier/SNAC-port configurations. On may remain selected while bypassed.

## Install the experimental Dual build

Keep your original PSX core and configuration. Using the [release package](releases/20261021/)'s validated
Dual RBF, isolated launcher and **binary 16-byte** profile:

1. Place the RBF at `_Console/PSX_HQ2X_Test.rbf` on the MiSTer SD card.
2. Place the launcher at `_Console/PSX HQ2X Test.mgl` and the profile at
   `config/PSX_HQ2X_Test.CFG`.
3. Select the GUI entry **PSX HQ2X Test** (spaces), rather than the underscored
   bare-RBF entry. Its setname
   selects the isolated test CFG while retaining normal PSX BIOS/game paths.

The minimal launcher is:

```xml
<mistergamedescription>
  <setname same_dir="1">PSX_HQ2X_Test</setname>
  <rbf>_Console/PSX_HQ2X_Test</rbf>
</mistergamedescription>
```

It specifies no game or test program. Normal PSX BIOS/startup behavior applies;
provide your own BIOS as described in [the upstream guide](UPSTREAM_README.md).
No BIOS, games or user saves are distributed here.

The isolated profile starts with HQ2X **On**, SPU RAM **SDRAM2**, memory-card
saving **Manual**, and **Automount Memory Card 1: No**. Review those settings
before ordinary saved-game use. Its 16 bytes, in file order, are
`00000000001000808000002000000000`; this is binary data, not a text file.
The original PSX CFG is separate. Dual also supports the DDR3 SPU option.

Validated Dual RBF SHA-256:
`384046b41006c595c6cd9d24873dc3c30080f7cf2a14d2d96506c393b5f5fc3c`
(4,467,892 bytes).

## Measured result and limits

Quartus Prime Lite 25.1, Cyclone V `5CSEBA6U23I7`, four workers, seed 1:

| Variant | ALMs / 41,910 | RAM blocks | DSP blocks / 112 | Minimum Slow/Fast 0C setup/hold |
| --- | ---: | ---: | ---: | ---: |
| Selected Dual | 41,119 | 432 | 112 | +0.013 ns |
| Unqualified Single | 41,206 | 433 | 112 | -0.374 ns |

Dual setup, hold, recovery, removal and pulse-width checks pass at the discrete
Slow/Fast 0C, 85C and 100C device models at 1100 mV. Its minimum warm
setup/hold margin is +0.087 ns. **Slow -40C setup still misses by -0.045 ns.**
Single's minimum warm setup/hold is -0.672 ns. These are junction-temperature
models, not room-temperature measurements or full board timing certification.
The small positive margin and inherited constraint-coverage limits matter.

The exact Dual artifact completed an exact native-pixel progressive fixture
comparison (337,920 HQ pixels), finite mode-transition/interlace-bypass sweeps,
four-pattern SPU readback on a 1 KiB region through both DDR3 and SDRAM2, and
bounded Ridge Racer attract rendering. Native captures do not establish
physical HDMI/analog/audio behavior, frame rate, whole-RAM health or general
game compatibility. A supplemental named FIFO-buffer physical audit remains
unproved; the timing result comes from global analysis of the routed design.

See [build instructions](docs/BUILD.md) and the [public validation bundle](validation/README.md) for
scope, timing summaries and source provenance. Successful fitting alone is not
a timing pass. A rebuilt RBF is a new artifact requiring its own review.

## Credits and license

The PlayStation core comes from PSX_MiSTer and its authors/contributors,
including Robert Peip / [FPGAzumSpass](https://github.com/FPGAzumSpass).
The MiSTer framework and shared video path come from Sorgelig and contributors.
The shared HQ2X RTL retains Ludvig Strigeus and Sorgelig's copyright notices.
This change integrates that engine; it does not introduce a new HQ2X algorithm.

Original source notices and the [GPL v2 license](LICENSE) are retained;
component/vendor notices continue to apply. `COPYING` contains the same license
text for source headers that reference that filename. The original public
[README](UPSTREAM_README.md) is retained for upstream usage information.
