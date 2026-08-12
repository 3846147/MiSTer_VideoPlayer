// SPDX-License-Identifier: GPL-3.0-or-later
// 640x480 active timing from the stock 20 MHz Template_MiSTer PLL.
// 672 x 496 total pixels gives ~60.004 Hz frame rate and ~29.762 kHz H rate.
module video_timing_640x480
(
    input  wire clk,
    input  wire reset,
    output wire ce_pix,
    output wire hs,
    output wire vs,
    output wire de
);
localparam H_ACTIVE = 640;
localparam H_FP     = 8;
localparam H_SYNC   = 16;
localparam H_BP     = 8;
localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP; // 672

localparam V_ACTIVE = 480;
localparam V_FP     = 3;
localparam V_SYNC   = 2;
localparam V_BP     = 11;
localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP; // 496

reg [9:0] h = 0;
reg [9:0] v = 0;

assign ce_pix = 1'b1;

always @(posedge clk) begin
    if(reset) begin
        h <= 0;
        v <= 0;
    end else begin
        if(h == H_TOTAL-1) begin
            h <= 0;
            if(v == V_TOTAL-1) v <= 0;
            else v <= v + 1'd1;
        end else h <= h + 1'd1;
    end
end

assign de = (h < H_ACTIVE) && (v < V_ACTIVE);
assign hs = ~((h >= H_ACTIVE + H_FP) && (h < H_ACTIVE + H_FP + H_SYNC));
assign vs = ~((v >= V_ACTIVE + V_FP) && (v < V_ACTIVE + V_FP + V_SYNC));
endmodule
