# Focused HQ2X integration benches

See [build instructions](../../docs/BUILD.md#focused-streaming-simulations).
Run `python sim/hq2x/run-native.py` from the repository root with Python 3,
Node.js and Icarus Verilog installed. `--only` selects waveform, control,
spatial, differential or reset. Optional executable arguments are `--node`,
`--iverilog` and `--vvp`.

The preparation script extracts production selection logic and normalizes only
simulation copies: declarations, packed struct storage, ROM initialization,
and the chosen video_mixer generate branch. It records hashes in generated/.
The differential reference shares the HQ2X engine; constant-color interiors
alone cannot establish spatial alignment. The coordinate-coded spatial bench
checks that separately. Reset tests cover differing asynchronous phases rather
than claiming exact coincident source/video edges.

These are streaming integration tests, not full-core or hardware qualification.
