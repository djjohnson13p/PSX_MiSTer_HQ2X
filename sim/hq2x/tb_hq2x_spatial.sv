`timescale 1ns / 1ps
module tb;
localparam WIDTH=32, HEIGHT=16;
reg clk=0;
always #5 clk=~clk;
reg ce=0, reset=1, gamma_en=0, gamma_wr=0;
reg [9:0] gamma_addr=0;
reg [7:0] gamma_value=0;
reg [2:0] hres=0;
reg [127:0] status=0;
reg [23:0] rgb=0;
reg hs=0, vs=0, hb=1, vb=1;
wire [23:0] gamma_rgb;
wire gamma_hs, gamma_vs, gamma_hb, gamma_vb;
wire oce, ohs, ovs, ode, ofield, active;
wire [7:0] outr,outg,outb;
integer div=4, x=0,y=0, phase=0, source_frame=0;
integer errors=0, checked_pixels=0, checked_rows=0;
reg checking=0;
gamma_corr gamma_stage (
 .clk_sys(clk),.clk_vid(clk),.ce_pix(ce),.gamma_en(gamma_en),
 .gamma_wr(gamma_wr),.gamma_wr_addr(gamma_addr),.gamma_value(gamma_value),
 .HSync(hs),.VSync(vs),.HBlank(hb),.VBlank(vb),.RGB_in(rgb),
 .HSync_out(gamma_hs),.VSync_out(gamma_vs),.HBlank_out(gamma_hb),.VBlank_out(gamma_vb),.RGB_out(gamma_rgb)
);
psx_hq2x_under_test dut (
 .CLK_VIDEO(clk),.ce_pix(ce),.reset(reset),.video_highres(1'b0),
 .video_hResMode(hres),.video_isPal(1'b0),.FB_EN(1'b0),.hack_480p(1'b0),
 .fast_forward(1'b0),.DIRECT_VIDEO(1'b0),
 .PadPortGunCon1(1'b0),.PadPortGunCon2(1'b0),.PadPortJustif1(1'b0),.PadPortJustif2(1'b0),
 .snacPort1(1'b0),.snacPort2(1'b0),.status(status),
 .in_r(gamma_rgb[23:16]),.in_g(gamma_rgb[15:8]),.in_b(gamma_rgb[7:0]),
 .in_hs(gamma_hs),.in_vs(gamma_vs),.in_hb(gamma_hb),.in_vb(gamma_vb),.native_field(1'b0),
 .CE_PIXEL(oce),.VGA_R(outr),.VGA_G(outg),.VGA_B(outb),
 .VGA_HS(ohs),.VGA_VS(ovs),.VGA_DE(ode),.VGA_F1(ofield),.active(active)
);

// Each 3x3 source neighborhood has nine distinct red/green coordinates,
// separated by >=126 channel levels. Blue encodes x, y and source-frame ID.
// HQ2x's all-neighbors-different case preserves the center in all four outputs;
// see original Stepin hq2x.c case255, PIXEL00/01/10/11_0. No ROM model is used.
function [23:0] pixel(input integer px,input integer py,input integer frame_id);
 reg [7:0] pr,pg,pb;
 begin
  pr=(px%3)*127;
  pg=(py%3)*127;
  pb=(px*13+py*29+frame_id*37)%256;
  pixel={pr,pg,pb};
 end
endfunction

always @(posedge clk) begin
 ce <= (phase==0);
 if(phase==0) begin
  hs <= (x<8*div);
  vs <= (y>=21);
  hb <= !(x>=32*div && x<(32+WIDTH)*div);
  vb <= !(y>=4 && y<4+HEIGHT);
  if(x>=32*div && x<(32+WIDTH)*div && y>=4 && y<4+HEIGHT)
   rgb <= pixel((x-32*div)/div,y-4,source_frame);
  else rgb <= 0;
 end
 if(phase==div-1) phase<=0; else phase<=phase+1;
 // One extra master-clock tick makes the line fractional in pixel units.
 if(x==96*div) begin
  x<=0; phase<=0;
  if(y==23) begin y<=0;source_frame<=source_frame+1;end else y<=y+1;
 end else x<=x+1;
end

// Model the real downstream consumer: sample the output before the rising-edge
// updates, exactly as ascal does. A post-edge pixel probe can be one ahead when
// ce_x4 remains high at div4.
reg sample_ce=0,sample_de=0,sample_vs=0,sample_active=0;
reg [23:0] sample_rgb;
integer sample_frame;
always @(posedge clk) begin
 sample_ce<=oce;sample_de<=ode;sample_vs<=ovs;sample_active<=active;
 sample_rgb<={outr,outg,outb};sample_frame<=source_frame;
end
reg old_de=0,old_vs=0;
integer ox=0,oy=-1;
reg [23:0] expected;
always @(negedge clk) begin
 if(sample_ce) begin
  if(sample_vs && !old_vs) oy=-1;
  if(sample_de && !old_de) begin ox=0;oy=oy+1;end
  if(checking && sample_active && sample_de) begin
   if(ox>=4 && ox<2*WIDTH-4 && oy>=4 && oy<2*HEIGHT-4) begin
    expected=pixel(ox/2,oy/2,sample_frame);
    checked_pixels=checked_pixels+1;
    if(sample_rgb !== expected) begin
     errors=errors+1;
     if(errors<13) $display("FAIL spatial div=%0d gamma=%0d frame=%0d outxy=%0d,%0d got=%06x expect=%06x",div,gamma_en,sample_frame,ox,oy,sample_rgb,expected);
    end
   end
  end
  if(sample_de) ox=ox+1;
  if(!sample_de && old_de && checking && sample_active) begin
   checked_rows=checked_rows+1;
   if(ox!=2*WIDTH) begin errors=errors+1;$display("FAIL spatial width got=%0d expected=%0d",ox,2*WIDTH);end
  end
  old_de=sample_de;old_vs=sample_vs;
 end
end
task next_frame;
 integer target;
 begin target=source_frame+1;wait(source_frame==target);@(negedge clk);end
endtask
task test_case(input integer divisor,input [2:0] code,input integer enable_gamma);
 integer i,start_pixels,start_errors,start_rows;
 begin
  checking=0;div=divisor;hres=code;gamma_en=enable_gamma;
  for(i=0;i<4;i=i+1) next_frame();
  start_pixels=checked_pixels;start_errors=errors;start_rows=checked_rows;
  checking=1;next_frame();checking=0;
  $display("CASE spatial div=%0d gamma=%0d checked_pixels=%0d checked_rows=%0d errors=%0d",div,gamma_en,checked_pixels-start_pixels,checked_rows-start_rows,errors-start_errors);
  if(checked_pixels-start_pixels!=1344 || checked_rows-start_rows!=32) begin
   errors=errors+1;$display("FAIL spatial coverage");
  end
 end
endtask
integer address;
initial begin
 // Program identity gamma through the real write interface.
 for(address=0;address<768;address=address+1) begin
  @(negedge clk);gamma_wr=1;gamma_addr=address;gamma_value=address%256;
 end
 @(negedge clk);gamma_wr=0;reset=0;status[93]=1;
 test_case(4,0,0);test_case(5,1,0);test_case(7,2,0);
 test_case(4,0,1);test_case(5,1,1);test_case(7,2,1);
 $display("RESULT spatial_errors=%0d checked_pixels=%0d checked_rows=%0d",errors,checked_pixels,checked_rows);
 if(errors) $fatal(1,"HQ2x spatial mapping validation failed");
 $display("PASS HQ2X coordinate/frame-coded pixel mapping through real gamma stage");
 $finish;
end
endmodule
