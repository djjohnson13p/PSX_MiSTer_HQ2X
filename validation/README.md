# PSX HQ2X validation

**Selected test build: Dual SDRAM.** Both matched variants fit at about 98% ALMs. Dual has the better measured 0°C setup/hold result and passed the bounded hardware tests below. The existing board/output frameworks remain in place; no additional HQ2X analog/HDMI split was needed.

## Timing and build provenance

The builds used Quartus Prime Lite 25.1std.0 build 1129, Cyclone V 5CSEBA6U23I7, seed 1 and four workers. See [build-provenance.json](build-provenance.json) for public source-relative fingerprints, exact RBF identities and the full eight-model numerical summary.

| Matched variant | Slow 0°C setup / hold | Fast 0°C setup / hold | Minimum 0°C | Minimum 85/100°C |
| --- | ---: | ---: | ---: | ---: |
| Dual, selected | +0.013 / +0.138 | +3.358 / +0.076 | **+0.013** | +0.087 |
| Single, comparison only | −0.374 / +0.195 | +2.848 / +0.080 | **−0.374** | −0.672 |

All slacks are nanoseconds at 1100 mV. Dual passes the selected Slow/Fast 0°C, 85°C and 100°C internal checks. Slow −40°C setup remains −0.045 ns and is explicitly outside that qualification. These are FPGA junction models, not ambient measurements, an interpolated 20°C model or full board certification. Single fits but is not timing-qualified or hardware-tested; this does not prove all future Single placements would fail.

The six TSVs below are exact byte copies of the completed report summaries:

| Variant | Full global checks | Focused VIDEO/HDMI | Reset chain |
| --- | --- | --- | --- |
| Dual | [dual-full.tsv](timing/dual-full.tsv) | [dual-focused.tsv](timing/dual-focused.tsv) | [dual-reset.tsv](timing/dual-reset.tsv) |
| Single | [single-full.tsv](timing/single-full.tsv) | [single-focused.tsv](timing/single-focused.tsv) | [single-reset.tsv](timing/single-reset.tsv) |

Full reports sample 20 paths per check, focused reports 64 and reset reports one direct path. `NA` is not a supplied TNS value. These lists do not enumerate every alternative path. Inherited unconstrained I/O coverage remains; the internal results do not certify module or external electrical timing. A rebuilt RBF needs its own fit/timing review; results here identify exact tested binaries.

## Hardware scope on the selected Dual RBF

- A source-owned 320×240 diagonal/checker/grid/color-bar fixture produced 352×240 native capture with HQ Off and 704×480 with HQ On. All 337,920 On pixels, including padding and borders, matched the actual shared-engine reference. The 640×480 visible crop contains 307,200 exact pixels. This validates integration for one fixture, not an independent algorithm specification.
- Fresh Off/On runs each finished two eight-mode sweeps and final PAL480i register/liveness checks. The final body matched 97,280 source pixels. Every intermediate mode's geometry and physical field cadence were not captured.
- Fresh DDR3 and SDRAM2 SPU tests each passed four patterns over the same 1 KiB region: 4,096 compared bytes, error 0, cleanup 0 and no byte mismatch. Ten passive digital-board enable samples accompanied each backend. This is not full RAM health or pin-level transaction proof.
- Fresh Off/On Ridge Racer runs each produced three complete, distinct 3D road/tunnel/coastal scenes. Off was 352×240; On was 704×480. Frames were unsynchronized, so no exact cross-frame comparison or frame-rate claim is made.
- The no-file/no-reset isolated launcher booted a complete BIOS Main Menu. The same 172 bytes were then exclusively installed and read back. Runtime smoke used a temporary path; permanent-path publication verified bytes and resolver rather than another runtime launch.

Tracked originals and saves were preserved, owned temporary files were removed, and tests returned MENU/User with closed transport. Only one project test RBF and its launcher remained active; experiment history was kept separately. These are bounded observations, not universal compatibility or physical HDMI/analog/audio certification.
