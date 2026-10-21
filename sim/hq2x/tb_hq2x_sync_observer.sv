`timescale 1ns / 1ps
// Compile alongside tb_hq2x_control.sv. Observe the same rising-edge samples
// consumed by the framework; a legitimate VS pulse is several complete lines.
module hq2x_sync_observer;
integer pulse_clocks=0;
integer checked_pulses=0, min_pulse_clocks=2147483647;
reg old_vs=0;
always @(posedge tb.clk) begin
 if(tb.ovs) pulse_clocks=pulse_clocks+1;
 if(old_vs && !tb.ovs && !tb.reset) begin
  checked_pulses=checked_pulses+1;
  if(pulse_clocks<min_pulse_clocks) min_pulse_clocks=pulse_clocks;
  if(pulse_clocks<64) begin
   $display("FAIL short output VS pulse: clocks=%0d source_frame=%0d y=%0d active=%0d",pulse_clocks,tb.frames,tb.y,tb.active);
   $fatal(1,"HQ2x source selection emitted a runt vertical-sync pulse");
  end
  pulse_clocks=0;
 end
 old_vs=tb.ovs;
end
final $display("RESULT sync_pulses=%0d shortest_pulse_clocks=%0d",checked_pulses,min_pulse_clocks);
endmodule
