"""Run focused integration benches using installed Node.js and Icarus Verilog."""
from pathlib import Path
import argparse
import subprocess

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only', choices=['waveform', 'control', 'spatial', 'differential', 'reset'])
parser.add_argument('--node', default='node')
parser.add_argument('--iverilog', default='iverilog')
parser.add_argument('--vvp', default='vvp')
args = parser.parse_args()
subprocess.run([args.node, str(here / 'prepare.mjs')], check=True)
generated = here / 'generated'
common = ['hq2x_sim.sv', 'scandoubler.v', 'psx_hq2x_under_test.sv']
suites = {
    'waveform': common + ['tb_hq2x.sv'],
    'control': common + ['tb_hq2x_control.sv', 'tb_hq2x_sync_observer.sv'],
    'spatial': common + ['gamma_corr_sim.sv', 'tb_hq2x_spatial.sv'],
    'differential': common + ['gamma_corr_sim.sv', 'video_freezer.sv', 'video_mixer_sim.sv', 'tb_hq2x_differential.sv'],
    'reset': common + ['tb_hq2x_reset.sv'],
}
for name, files in suites.items():
    if args.only and args.only != name:
        continue
    output = generated / (name + '.vvp')
    tops = ['-s', 'tb']
    if name == 'control':
        tops += ['-s', 'hq2x_sync_observer']
    sources = [str((here if file.startswith('tb_') else generated) / file) for file in files]
    subprocess.run([args.iverilog, '-g2012', *tops, '-o', str(output), *sources], check=True)
    subprocess.run([args.vvp, str(output)], check=True)
print('Selected focused suites passed')
