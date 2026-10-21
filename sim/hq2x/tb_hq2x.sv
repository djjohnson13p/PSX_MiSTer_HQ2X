`timescale 1ns / 1ps
module tb;
reg clk = 0;
always #5 clk = ~clk;
reg ce = 0, reset = 1, highres = 0, ispal = 0;
reg [2:0] hres = 0;
reg fb = 0, hack = 0, ff = 0, direct = 0, gun = 0, snac = 0;
reg [127:0] status = 0;
reg [7:0] r = 0, g = 0, b = 0;
reg hs = 0, vs = 0, hb = 1, vb = 1, field = 0;
wire oce, ohs, ovs, ode, ofield, active;
wire [7:0] outr, outg, outb;
psx_hq2x_under_test dut (
 .CLK_VIDEO(clk), .ce_pix(ce), .reset(reset), .video_highres(highres),
 .video_hResMode(hres), .video_isPal(ispal), .FB_EN(fb), .hack_480p(hack),
 .fast_forward(ff), .DIRECT_VIDEO(direct),
 .PadPortGunCon1(gun), .PadPortGunCon2(1'b0), .PadPortJustif1(1'b0), .PadPortJustif2(1'b0),
 .snacPort1(snac), .snacPort2(1'b0), .status(status),
 .in_r(r), .in_g(g), .in_b(b), .in_hs(hs), .in_vs(vs), .in_hb(hb), .in_vb(vb),
 .native_field(field), .CE_PIXEL(oce), .VGA_R(outr), .VGA_G(outg), .VGA_B(outb),
 .VGA_HS(ohs), .VGA_VS(ovs), .VGA_DE(ode), .VGA_F1(ofield), .active(active)
);
integer errors = 0, clocks = 0, rows = 0, rowpixels = 0;
integer checked_rows = 0, checked_pixels = 0, expected_width = 0;
integer current_div = 4, current_width = 640, source_frame = 0;
reg old_de = 0, old_active = 0;
reg checking = 0;
reg expect_disable_before_picture = 0;
task fail(input [1023:0] why);
 begin
  errors = errors + 1;
  if(errors < 16) $display("FAIL t=%0t div=%0d frame=%0d %s", $time, current_div, source_frame, why);
 end
endtask

always @(negedge clk) begin
 clocks = clocks + 1;
 if (!active) begin
  if ({oce,outr,outg,outb,ohs,ovs,ode,ofield} !==
      {ce,r,g,b,hs,vs,~(vb|hb),(status[14] ? 1'b0 : field)})
    fail("bypass changed native pixel/sync/field data");
 end
 if (active && !old_active && !vb) fail("HQ2x enabled outside native vertical blanking");
 if (active && ofield !== 1'b0) fail("HQ2x output marked interlaced");
 if (fb && active) fail("HQ2x remained enabled with direct framebuffer");
 if ((hack || ff || direct || gun || snac || reset) && active) fail("HQ2x remained enabled in bypass mode");
 if (oce) begin
  if (ode && !old_de) begin
   rowpixels = 0;
   rows = rows + 1;
  end
  if (ode) begin
   rowpixels = rowpixels + 1;
   // Interior of a constant-color region must remain that exact color. Skip
   // edge pixels and the first/last filtered lines where interpolation occurs.
   if (checking && active && rows > 4 && rows < 13 && rowpixels > 12 && rowpixels < expected_width-12) begin
    checked_pixels = checked_pixels + 1;
    if ({outr,outg,outb} !== 24'h3868a8) fail("interior color preservation changed");
   end
  end
  if (!ode && old_de && checking && active) begin
   checked_rows = checked_rows + 1;
   if (rowpixels != expected_width) begin
    if(errors < 16) $display("WIDTH got=%0d expected=%0d",rowpixels,expected_width);
    fail("active row width did not double");
   end
  end
  old_de = ode;
 end
 if (vs) rows = 0;
 old_active = active;
end

// Real PSX master-clock horizontal period (NTSC=3413), not an integer number
// of pixels for several modes. Changes are delivered on native pixel enables.
task frame(input integer div, input integer width);
 integer y, c, cnt;
 begin
  current_div = div;
  current_width = width;
  cnt = 0;
  for(y=0;y<24;y=y+1) begin
   for(c=0;c<3413;c=c+1) begin
    @(posedge clk);
    if(y==4 && c==0 && expect_disable_before_picture) begin
     if(active) fail("OSD off did not commit before the next active picture");
     expect_disable_before_picture=0;
    end
    ce <= (cnt == 0);
    if(cnt == 0) begin
     hs <= (c < 160);
     vs <= (y >= 20 && y < 23);
     hb <= !(c >= 320 && c < 320 + width*div);
     vb <= !(y >= 4 && y < 12);
     r <= 8'h38; g <= 8'h68; b <= 8'ha8;
    end
    cnt = cnt + 1;
    if(cnt == div) cnt = 0;
   end
   cnt = 0;
  end
  source_frame = source_frame + 1;
 end
endtask

task mode(input integer div, input integer width, input [2:0] modecode);
 integer f, start_rows;
 begin
  checking = 0;
  hres = modecode;
  expected_width = width*2;
  for(f=0;f<4;f=f+1) frame(div,width);
  if(!active) fail("HQ2x did not enable after stable progressive frames");
  checking = 1;
  start_rows = checked_rows;
  for(f=0;f<2;f=f+1) frame(div,width);
  checking = 0;
  if(checked_rows-start_rows != 32) fail("filtered active row count did not double to32");
  $display("CASE div=%0d source_width=%0d output_rows=%0d checked_pixels=%0d",div,width,checked_rows-start_rows,checked_pixels);
 end
endtask

initial begin
 if ($test$plusargs("vcd")) begin $dumpfile("dump.vcd"); $dumpvars(1,tb); end
 repeat(20) @(posedge clk);
 reset = 0;
 status[93] = 1;
 mode(4,640,0);
 mode(5,512,1);
 mode(7,368,2);
 mode(8,320,3);
 mode(10,256,4);
 // A highres mode remains bypassed even when its field bit alternates to zero.
 highres = 1;
 field = 1;
 frame(4,640);
 if(active) fail("480i odd field enabled HQ2x");
 field = 0;
 frame(4,640);
 if(active) fail("480i even field enabled HQ2x");
 highres = 0;
 mode(4,640,0);
 fb = 1; #1; if(active) fail("framebuffer bypass not immediate");
 frame(4,640); fb = 0;
 mode(4,640,0);
 hack = 1; frame(4,640); hack = 0;
 ff = 1; frame(4,640); ff = 0;
 direct = 1; frame(4,640); direct = 0;
 gun = 1; frame(4,640); gun = 0;
 snac = 1; frame(4,640); snac = 0;
 mode(4,640,0);
 // Toggle between frames. The separate control bench tests mid-picture changes.
 status[93] = 0;
 frame(4,640);
 // The filtered VS trails the raw frame boundary. Require Off by the next
 // active picture, allowing the common blank after that trailing VS ends.
 expect_disable_before_picture=1;
 frame(4,640);
 if(expect_disable_before_picture) fail("OSD-off deadline check was not exercised");
 status[93] = 1;
 mode(4,640,0);
 if (checked_pixels < 10000) fail("insufficient interior pixel coverage");
 $display("RESULT errors=%0d checked_rows=%0d checked_pixels=%0d clocks=%0d",errors,checked_rows,checked_pixels,clocks);
 if(errors) $fatal(1,"HQ2x waveform validation failed");
 $display("PASS HQ2X waveform and bypass checks");
 $finish;
end
endmodule
