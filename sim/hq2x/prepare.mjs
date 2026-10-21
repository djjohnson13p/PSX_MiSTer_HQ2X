// Extract the actual PSX integration for simulation; no duplicate gate model.
// Packed storage below represents the same named struct fields used in PSX.sv.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const out = path.join(here, 'generated');
fs.mkdirSync(out, {recursive:true});
const psx = fs.readFileSync(path.join(root, 'PSX.sv'), 'utf8').replace(/\r/g, '');
const marker = '`ifdef PSX_HQ2X\n// Preserve the native pixel enable';
const start = psx.indexOf(marker);
const end = psx.indexOf('`else\nassign CE_PIXEL = ce_pix;', start);
if(start < 0 || end < 0) throw new Error('PSX integration extraction markers changed');
const body = psx.slice(start + '`ifdef PSX_HQ2X\n'.length, end);
const header = `\`timescale 1ns / 1ps
module psx_hq2x_under_test (
 input CLK_VIDEO, ce_pix, reset, video_highres,
 input [2:0] video_hResMode,
 input video_isPal, FB_EN, hack_480p, fast_forward, DIRECT_VIDEO,
 input PadPortGunCon1, PadPortGunCon2, PadPortJustif1, PadPortJustif2,
 input snacPort1, snacPort2,
 input [127:0] status,
 input [7:0] in_r, in_g, in_b,
 input in_hs, in_vs, in_hb, in_vb, native_field,
 output CE_PIXEL,
 output [7:0] VGA_R, VGA_G, VGA_B,
 output VGA_HS, VGA_VS, VGA_DE, VGA_F1,
 output active
);
typedef struct packed {
 logic [7:0] red, green, blue;
 logic hs, vs, hb, vb, interlace;
} vid_info;
wire vid_info video_gamma, video_aspect;
assign video_gamma = {in_r, in_g, in_b, in_hs, in_vs, in_hb, in_vb, 1'b0};
assign video_aspect = {24'b0, 4'b0, native_field};
`;
fs.writeFileSync(path.join(out, 'psx_hq2x_under_test.sv'), header + body + '\nassign active = hq2x_active;\nendmodule\n');
let doubler = fs.readFileSync(path.join(root, 'sys/scandoubler.v'), 'utf8');
// Quartus accepts declarations after their first use; Icarus requires these
// header dimensions and instance inputs to be declared before use.
doubler = doubler.replace('parameter HALF_DEPTH)', 'parameter HALF_DEPTH, parameter DWIDTH = HALF_DEPTH ? 3 : 7)')
 .replace('localparam DWIDTH = HALF_DEPTH ? 3 : 7;', '')
 .replace(/reg ce_x4o, ce_x2o;/, '')
 .replace(/reg \[1:0\] sd_line;/, '')
 .replace(/reg \[8:0\] hbo;/, '')
 .replace('Hq2x #(', 'reg ce_x4o, ce_x2o;\nreg [1:0] sd_line;\nreg [8:0] hbo;\n\nHq2x #(');
fs.writeFileSync(path.join(out, 'scandoubler.v'), doubler);
// Icarus lacks unpacked-array assignment patterns. Expand only this constant ROM
// initialization into equivalent element assignments in the simulation copy.
let engine = fs.readFileSync(path.join(root, 'sys/hq2x.sv'), 'utf8');
const rom = /hqTable\s*=\s*'\{([\s\S]*?)\};/;
const match = engine.match(rom);
if(!match) throw new Error('HQ2x ROM initialization pattern changed');
const values = match[1].split(',').map(s=>s.trim());
if(values.length !== 256 || values.some(s=>!/^\d+$/.test(s))) throw new Error('Unexpected HQ2x ROM');
engine = engine.replace(rom, values.map((v,i)=>`hqTable[${i}] = 6'd${v};`).join('\n\t'));
engine = engine.replace('module Hq2x #(parameter LENGTH, parameter HALF_DEPTH)', 'module Hq2x #(parameter LENGTH, parameter HALF_DEPTH, parameter DWIDTH = HALF_DEPTH ? 11 : 23)')
 .replace('localparam DWIDTH = HALF_DEPTH ? 11 : 23;', '')
 .replace('module hq2x_in #(parameter LENGTH, parameter DWIDTH)', 'module hq2x_in #(parameter LENGTH, parameter DWIDTH, parameter AWIDTH = $clog2(LENGTH)-1)');
// Keep the Hq2x module's AWIDTH, but remove the duplicate now in hq2x_in's header.
const inStart = engine.indexOf('module hq2x_in');
engine = engine.slice(0,inStart) + engine.slice(inStart).replace('localparam AWIDTH = $clog2(LENGTH)-1;', '');
engine = engine.replace('wire [5:0] hqrule = hqTable[nextpatt];', 'wire [5:0] hqrule;')
 .replace('reg  [7:0] pattern, nextpatt;', 'reg  [7:0] pattern, nextpatt;\nassign hqrule = hqTable[nextpatt];')
 .replace(/reg \[AWIDTH:0\] offs;/, '')
 .replace('hq2x_in #(', 'reg [AWIDTH:0] offs;\n\nhq2x_in #(')
 .replace('output [23:0] Result', 'output reg [23:0] Result');
fs.writeFileSync(path.join(out, 'hq2x_sim.sv'), engine);
let gamma = fs.readFileSync(path.join(root, 'sys/gamma_corr.sv'), 'utf8');
gamma = gamma.replace(/reg \[9:0\] gamma_index;/, '').replace(/reg \[7:0\] gamma;/, '')
 .replace('always @(posedge clk_sys)', 'reg [9:0] gamma_index;\nreg [7:0] gamma;\n\nalways @(posedge clk_sys)');
fs.writeFileSync(path.join(out, 'gamma_corr_sim.sv'), gamma);
let mixer = fs.readFileSync(path.join(root, 'sys/video_mixer.sv'), 'utf8');
mixer = mixer.replace('parameter GAMMA        = 0', 'parameter GAMMA        = 0,\n\tparameter DWIDTH = HALF_DEPTH ? 3 : 7')
 .replace('localparam DWIDTH = HALF_DEPTH ? 3 : 7;', '');
// Quartus resolves the selected input-depth generate branch outside its scope.
// The reference bench selects HALF_DEPTH=0, so expose that exact branch to
// standards-conforming simulators without changing its expressions.
const inputBranch = /generate\s+if\(GAMMA && HALF_DEPTH\)[\s\S]*?endgenerate/;
if(!inputBranch.test(mixer)) throw new Error('video_mixer input-depth branch changed');
mixer = mixer.replace(inputBranch, 'wire [DWIDTH:0] R_in = frz ? 1\'d0 : R;\nwire [DWIDTH:0] G_in = frz ? 1\'d0 : G;\nwire [DWIDTH:0] B_in = frz ? 1\'d0 : B;');
fs.writeFileSync(path.join(out,'video_mixer_sim.sv'),mixer);
fs.copyFileSync(path.join(root,'sys/video_freezer.sv'),path.join(out,'video_freezer.sv'));
const sourceFiles = ['PSX.sv', 'sys/scandoubler.v', 'sys/hq2x.sv', 'sys/gamma_corr.sv', 'sys/video_mixer.sv', 'sys/video_freezer.sv', 'sim/hq2x/tb_hq2x.sv', 'sim/hq2x/tb_hq2x_control.sv', 'sim/hq2x/tb_hq2x_spatial.sv', 'sim/hq2x/tb_hq2x_sync_observer.sv', 'sim/hq2x/tb_hq2x_differential.sv', 'sim/hq2x/tb_hq2x_reset.sv'];
const sha256 = (bytes)=>createHash('sha256').update(bytes).digest('hex');
fs.writeFileSync(path.join(out,'source_manifest.json'), JSON.stringify({
 created_utc:new Date().toISOString(),
 sources:sourceFiles.map(name=>({path:name,sha256:sha256(fs.readFileSync(path.join(root,name)))})),
 generated:['psx_hq2x_under_test.sv','scandoubler.v','hq2x_sim.sv','gamma_corr_sim.sv','video_mixer_sim.sv','video_freezer.sv'].map(name=>({path:name,sha256:sha256(fs.readFileSync(path.join(out,name)))})),
 changes:'Actual PSX filter block extracted; packed simulation struct storage; declaration ordering and output variable spelling normalized for Icarus; 256 ROM element assignments expanded without value changes.'
}, null, 2)+'\n');
console.log('Prepared actual PSX gate and shared filter; Icarus syntax normalization only.');
