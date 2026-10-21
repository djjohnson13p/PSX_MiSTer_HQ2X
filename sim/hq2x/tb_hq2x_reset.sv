`timescale 1ps / 1ps
module tb;
reg clk=0, core_clk=0;
integer video_half_period=9312;
always #(video_half_period) clk=~clk;
// Existing clk_1x reset register: 33.87 MHz, one cycle = 29.524 ns.
always #14762 core_clk=~core_clk;
reg ce=0, reset=1;
reg hs=0,vs=0,hb=1,vb=1;
reg [23:0] rgb=0;
reg [127:0] status=0;
wire oce,ohs,ovs,ode,ofield,active;
wire [7:0] outr,outg,outb;
integer x=0,y=0,phase=0,errors=0,pulses=0;
integer video_edges=0;
always @(posedge clk) video_edges=video_edges+1;

psx_hq2x_under_test dut (
 .CLK_VIDEO(clk),.ce_pix(ce),.reset(reset),.video_highres(1'b0),
 .video_hResMode(3'd0),.video_isPal(1'b0),.FB_EN(1'b0),.hack_480p(1'b0),
 .fast_forward(1'b0),.DIRECT_VIDEO(1'b0),
 .PadPortGunCon1(1'b0),.PadPortGunCon2(1'b0),.PadPortJustif1(1'b0),.PadPortJustif2(1'b0),
 .snacPort1(1'b0),.snacPort2(1'b0),.status(status),
 .in_r(rgb[23:16]),.in_g(rgb[15:8]),.in_b(rgb[7:0]),
 .in_hs(hs),.in_vs(vs),.in_hb(hb),.in_vb(vb),.native_field(1'b0),
 .CE_PIXEL(oce),.VGA_R(outr),.VGA_G(outg),.VGA_B(outb),
 .VGA_HS(ohs),.VGA_VS(ovs),.VGA_DE(ode),.VGA_F1(ofield),.active(active)
);
always @(posedge clk) begin
 ce<=(phase==0);
 if(phase==0) begin
  hs<=(x<32);vs<=(y>=21);
  hb<=!(x>=128 && x<256);vb<=!(y>=4 && y<12);
  rgb<={x[7:0],y[7:0],8'hb5};
 end
 if(phase==3) phase<=0;else phase<=phase+1;
 if(x==511) begin x<=0;if(y==23)y<=0;else y<=y+1;end
 else x<=x+1;
end
task fail(input [8*100-1:0] message);
 begin errors=errors+1;$display("FAIL reset %0s at video edge %0d",message,video_edges);end
endtask
always @(negedge clk) begin
 if(!active && {oce,outr,outg,outb,ohs,ovs,ode,ofield} !==
               {ce,rgb[23:16],rgb[15:8],rgb[7:0],hs,vs,!(hb|vb),1'b0})
  fail("native bypass changed");
end

integer test_number;
initial begin
 status[93]=1;
 repeat(3) @(posedge core_clk);
 reset<=0;
 for(test_number=0;test_number<12;test_number=test_number+1) begin
  wait(active);
  wait(!hb && !vb);
  @(negedge clk);
  // Runtime NTSC, slightly slower PAL, and unchanged SDC 85.9 MHz target.
  case(test_number/4)
   0: video_half_period=9312;
   1: video_half_period=9400;
   2: video_half_period=5820;
  endcase
  repeat(test_number%5) @(posedge core_clk);
  @(posedge core_clk);
  $display("CASE reset pulse=%0d video_period_ps=%0d core_pulse_ps=29524 video_edge=%0d",
           test_number+1,2*video_half_period,video_edges);
  reset<=1;
  fork
   begin
    // Bound the synchronizer and output response to three sampled edges.
    repeat(3) @(posedge clk);
    #1;
    if(active) fail("minimum core reset pulse was not captured within three video edges");
   end
   begin @(posedge core_clk);reset<=0;end
  join
  pulses=pulses+1;
  @(negedge clk);
  if(active) fail("stale filtered frame survived reset");
  // No stale ready/pending selection may re-enable before one whole stable
  // progressive frame has elapsed from the first to the second native VS.
  @(posedge vs);
  @(negedge clk);
  if(active) fail("first post-reset VS reused old frame readiness");
  @(negedge vs);
  while(!vs) begin
   @(negedge clk);
   if(active) fail("HQ2x re-enabled before a whole stable post-reset frame");
  end
  @(negedge vs);
  @(negedge vb);
  @(negedge clk);
  if(!active) fail("HQ2x did not re-enable by the next active picture after priming");
 end
 $display("RESULT reset_errors=%0d minimum_core_pulses=%0d",errors,pulses);
 if(errors) $fatal(1,"HQ2x reset-domain validation failed");
 $display("PASS HQ2X minimum core reset pulses, asynchronous phase and fresh-frame rearming");
 $finish;
end
initial begin #(64'd20000000000);$fatal(1,"Reset-domain bench timed out");end
endmodule
