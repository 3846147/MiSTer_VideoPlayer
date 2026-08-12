// SPDX-License-Identifier: GPL-3.0-or-later
// 640x480p ~59.94/60 Hz timing from 50 MHz with a 25 MHz pixel enable.
module video_timing_640x480
(
    input  wire clk,
    input  wire reset,
    output reg  ce_pix = 0,
    output wire hs,
    output wire vs,
    output wire de
);
reg pixdiv = 0;
reg [9:0] h = 0;
reg [9:0] v = 0;

always @(posedge clk) begin
    pixdiv <= ~pixdiv;
    ce_pix <= pixdiv;
    if(reset) begin
        h <= 0;
        v <= 0;
    end else if(pixdiv) begin
        if(h == 10'd799) begin
            h <= 0;
            if(v == 10'd524) v <= 0;
            else v <= v + 1'd1;
        end else h <= h + 1'd1;
    end
end

assign de = (h < 640) && (v < 480);
assign hs = ~((h >= 656) && (h < 752));
assign vs = ~((v >= 490) && (v < 492));
endmodule
