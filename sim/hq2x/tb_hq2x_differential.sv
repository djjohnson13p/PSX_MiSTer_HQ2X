`timescale 1ns / 1ps
module tb;
localparam WIDTH=32,HEIGHT=16,PIXELS=WIDTH*HEIGHT*4;
reg clk=0;
always #5 clk=~clk;
reg ce=0,reset=1,gamma_en=0,gamma_wr=0;
reg [9:0] gamma_addr=0;
reg [7:0] gamma_value=0;
reg [2:0] hres=0;
reg [127:0] status=0;
reg [23:0] rgb=0;
reg hs=0,vs=0,hb=1,vb=1;
wire [23:0] gamma_rgb;
wire gamma_hs,gamma_vs,gamma_hb,gamma_vb;
wire oce,ohs,ovs,ode,ofield,active;
wire [7:0] outr,outg,outb;
integer div=4,x=0,y=0,phase=0,source_frame=0,pattern=0;
integer errors=0,compared=0;
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
wire ref_ce,ref_hs,ref_vs,ref_de;
wire [7:0] ref_r,ref_g,ref_b;
wire [21:0] gamma_bus;
assign gamma_bus[20:0]={clk,gamma_en,gamma_wr,gamma_addr,gamma_value};
video_mixer #(.LINE_LENGTH(1024),.HALF_DEPTH(0),.GAMMA(1)) reference (
 .CLK_VIDEO(clk),.CE_PIXEL(ref_ce),.ce_pix(ce),.scandoubler(1'b1),.hq2x(1'b1),
 .gamma_bus(gamma_bus),.R(rgb[23:16]),.G(rgb[15:8]),.B(rgb[7:0]),
 .HSync(hs),.VSync(vs),.HBlank(hb),.VBlank(vb),.HDMI_FREEZE(1'b0),.freeze_sync(),
 .VGA_R(ref_r),.VGA_G(ref_g),.VGA_B(ref_b),.VGA_VS(ref_vs),.VGA_HS(ref_hs),.VGA_DE(ref_de)
);
function [23:0] pixel(input integer px,input integer py,input integer frame_id);
 reg [7:0] pr,pg,pb;
 begin
  if(pattern==0) begin
   pr=(px*73+py*131+frame_id*37)%256;
   pg=(px*px*11+py*79+frame_id*29)%256;
   pb=(px*17+py*py*23+frame_id*19)%256;
   pixel={pr,pg,pb};
  end else if(pattern==1) begin
   if(px<py*2) pixel=24'hd0a030;else pixel=24'h182848;
  end else begin
   if(px%7==0 || py%5==0) pixel=24'hffffff;
   else if((px/3+py/4)%2==0) pixel=24'h26b468;
   else pixel=24'hb42894;
  end
 end
endfunction
always @(posedge clk) begin
 ce<=(phase==0);
 if(phase==0) begin
  hs<=(x<8*div);vs<=(y>=21);
  hb<=!(x>=32*div && x<(32+WIDTH)*div);vb<=!(y>=4 && y<4+HEIGHT);
  if(x>=32*div && x<(32+WIDTH)*div && y>=4 && y<4+HEIGHT)
   rgb<=pixel((x-32*div)/div,y-4,source_frame);else rgb<=0;
 end
 if(phase==div-1) phase<=0;else phase<=phase+1;
 if(x==96*div) begin
  x<=0;phase<=0;
  if(y==23) begin y<=0;source_frame<=source_frame+1;end else y<=y+1;
 end else x<=x+1;
end
reg [23:0] actual_image[0:PIXELS-1],reference_image[0:PIXELS-1];
reg [23:0] actual_complete[0:PIXELS-1],reference_complete[0:PIXELS-1];
integer ai=0,ri=0,actual_count=0,reference_count=0,i;
reg avs=0,rvs=0;
// Capture each complete active-pixel stream at actual downstream sample edges.
// Frame association uses each path's own VS so pipeline delay is not assumed.
always @(posedge clk) begin
 if(oce) begin
  if(ovs && !avs) begin
   actual_count=ai;
   for(i=0;i<PIXELS;i=i+1) actual_complete[i]=actual_image[i];
   ai=0;
  end
  if(ode) begin
   if(ai<PIXELS) actual_image[ai]={outr,outg,outb};
   ai=ai+1;
  end
  avs=ovs;
 end
 if(ref_ce) begin
  if(ref_vs && !rvs) begin
   reference_count=ri;
   for(i=0;i<PIXELS;i=i+1) reference_complete[i]=reference_image[i];
   ri=0;
  end
  if(ref_de) begin
   if(ri<PIXELS) reference_image[ri]={ref_r,ref_g,ref_b};
   ri=ri+1;
  end
  rvs=ref_vs;
 end
end
task next_frame;
 integer target;
 begin target=source_frame+1;wait(source_frame==target);@(negedge clk);end
endtask
task test_case(input integer divisor,input [2:0] code,input integer gamma_mode,input integer pattern_kind);
 integer f,p,start_errors;
 begin
  div=divisor;hres=code;gamma_en=gamma_mode;pattern=pattern_kind;
  for(f=0;f<5;f=f+1) next_frame();
  start_errors=errors;
  if(actual_count!=PIXELS || reference_count!=PIXELS) begin
   errors=errors+1;$display("FAIL differential geometry actual=%0d reference=%0d expected=%0d",actual_count,reference_count,PIXELS);
  end
  for(p=0;p<PIXELS;p=p+1) begin
   compared=compared+1;
   if(actual_complete[p] !== reference_complete[p] || (^actual_complete[p])===1'bx) begin
    errors=errors+1;
    if(errors<13) $display("FAIL differential div=%0d gamma=%0d pattern=%0d xy=%0d,%0d actual=%06x reference=%06x",div,gamma_en,pattern,p%(WIDTH*2),p/(WIDTH*2),actual_complete[p],reference_complete[p]);
   end
  end
  $display("CASE differential div=%0d gamma=%0d pattern=%0d pixels=%0d errors=%0d",div,gamma_en,pattern,PIXELS,errors-start_errors);
 end
endtask
integer address;
initial begin
 // Nonidentity per-channel gamma, programmed through both real interfaces.
 for(address=0;address<768;address=address+1) begin
  @(negedge clk);gamma_wr=1;gamma_addr=address;
  if(address<256) gamma_value=255-address;
  else if(address<512) gamma_value=((address%256)*(address%256))/255;
  else gamma_value=(address%256)^8'h55;
 end
 @(negedge clk);gamma_wr=0;reset=0;status[93]=1;
 test_case(4,0,0,0);test_case(5,1,0,1);test_case(7,2,0,2);
 test_case(4,0,1,1);test_case(5,1,1,2);test_case(7,2,1,0);
 $display("RESULT differential_errors=%0d compared_pixels=%0d",errors,compared);
 if(errors) $fatal(1,"HQ2x standard-video-mixer differential validation failed");
 $display("PASS HQ2X arbitrary-pattern frames match standard MiSTer video_mixer");
 $finish;
end
endmodule
