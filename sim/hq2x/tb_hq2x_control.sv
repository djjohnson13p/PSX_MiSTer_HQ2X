`timescale 1ns / 1ps
module tb;
reg clk = 0;
always #5 clk = ~clk;
reg ce = 0, reset = 1, highres = 0, ispal = 0, fb = 0, field = 0;
reg [2:0] hres = 0;
reg [127:0] status = 0;
reg hs = 0, vs = 0, hb = 1, vb = 1;
wire oce, ohs, ovs, ode, ofield, active;
wire [7:0] outr, outg, outb;
integer x = 0, y = 0, frames = 0, errors = 0;
psx_hq2x_under_test dut (
 .CLK_VIDEO(clk), .ce_pix(ce), .reset(reset), .video_highres(highres),
 .video_hResMode(hres), .video_isPal(ispal), .FB_EN(fb), .hack_480p(1'b0),
 .fast_forward(1'b0), .DIRECT_VIDEO(1'b0),
 .PadPortGunCon1(1'b0), .PadPortGunCon2(1'b0), .PadPortJustif1(1'b0), .PadPortJustif2(1'b0),
 .snacPort1(1'b0), .snacPort2(1'b0), .status(status),
 .in_r(8'h38), .in_g(8'h68), .in_b(8'ha8),
 .in_hs(hs), .in_vs(vs), .in_hb(hb), .in_vb(vb), .native_field(field),
 .CE_PIXEL(oce), .VGA_R(outr), .VGA_G(outg), .VGA_B(outb),
 .VGA_HS(ohs), .VGA_VS(ovs), .VGA_DE(ode), .VGA_F1(ofield), .active(active)
);
task fail(input [1023:0] message);
 begin errors=errors+1; $display("FAIL t=%0t frame=%0d y=%0d %s",$time,frames,y,message); end
endtask
always @(posedge clk) begin
 ce <= (x % 4 == 0);
 if(x % 4 == 0) begin
  hs <= (x < 32);
  vs <= (y >= 20 && y < 23);
  hb <= !(x >= 64 && x < 320);
  vb <= !(y >= 4 && y < 12);
 end
 if(x == 511) begin
  x <= 0;
  if(y == 23) begin y<=0; frames<=frames+1; end
  else y<=y+1;
 end else x<=x+1;
end
always @(negedge clk) begin
 #1; // Sample after the test driver and combinational bypass mux settle.
 if(!active && {oce,outr,outg,outb,ohs,ovs,ode,ofield} !==
    {ce,24'h3868a8,hs,vs,~(vb|hb),(status[14] ? 1'b0 : field)})
  fail("bypass changed native stream");
 if(frames > 20) $fatal(1,"Control test timed out");
end
task next_vsync;
 begin
  wait(!vs); wait(vs); repeat(8) @(negedge clk);
 end
endtask
task next_safe_blank;
 begin
  next_vsync();
  wait(!vs); wait(!dut.hq2x_vs);
  wait(!hs && !dut.hq2x_hs);
  repeat(8) @(negedge clk);
 end
endtask
initial begin
 repeat(20) @(negedge clk);
 reset=0; status[93]=1;
 wait(active);
 wait(y==8 && x==100); @(negedge clk);
 status[93]=0;
 repeat(80) begin @(negedge clk); if(!active) fail("menu off changed output during active picture"); end
 next_safe_blank();
 if(active) fail("menu off did not apply during vertical blank");
 wait(y==8 && x==100); @(negedge clk);
 status[93]=1;
 repeat(80) begin @(negedge clk); if(active) fail("menu on changed output during active picture"); end
 next_safe_blank();
 if(!active) fail("menu on did not apply during vertical blank");
 wait(y==8 && x==100); @(negedge clk);
 highres=1; field=1;
 repeat(8) @(negedge clk);
 if(active) fail("highres mode did not bypass after synchronizer latency");
 field=0;
 repeat(80) begin @(negedge clk); if(active) fail("even highres field enabled HQ2x"); end
 next_safe_blank(); highres=0;
 next_safe_blank();
 if(active) fail("highres exit skipped stable-frame priming");
 next_safe_blank();
 if(!active) fail("progressive mode did not rearm after stable frame");
 wait(y==8 && x==100); @(negedge clk);
 fb=1; #1;
 if(active) fail("framebuffer enable did not bypass immediately");
 repeat(8) @(negedge clk); fb=0;
 next_safe_blank(); next_safe_blank();
 if(!active) fail("framebuffer exit did not rearm");
 wait(y==8 && x==100); @(negedge clk);
 ispal=1; #1;
 if(active) fail("region switch did not bypass immediately");
 next_safe_blank();
 if(active) fail("region switch skipped stable-frame priming");
 next_safe_blank();
 if(!active) fail("region switch did not rearm after stable frame");
 $display("RESULT control_errors=%0d frames=%0d",errors,frames);
 if(errors) $fatal(1,"HQ2x control validation failed");
 $display("PASS HQ2X mid-picture toggles, field and region transitions");
 $finish;
end
endmodule
