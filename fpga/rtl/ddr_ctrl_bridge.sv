// SPDX-License-Identifier: GPL-3.0-or-later
// Small HPS<->FPGA control bridge using MiSTer's high-latency DDR interface.
// DDRAM_ADDR is a 64-bit/qword address.
module ddr_ctrl_bridge
(
    input  wire         clk,
    input  wire         reset,
    input  wire [31:0]  joystick_0,
    input  wire [31:0]  joystick_1,
    input  wire [127:0] status,
    input  wire         img_mounted,
    output reg  [63:0]  arm_control = 0,
    output reg  [31:0]  heartbeat = 0,

    output wire         DDRAM_CLK,
    input  wire         DDRAM_BUSY,
    output reg  [7:0]   DDRAM_BURSTCNT = 1,
    output reg  [28:0]  DDRAM_ADDR = 0,
    input  wire [63:0]  DDRAM_DOUT,
    input  wire         DDRAM_DOUT_READY,
    output reg          DDRAM_RD = 0,
    output reg  [63:0]  DDRAM_DIN = 0,
    output reg  [7:0]   DDRAM_BE = 8'hFF,
    output reg          DDRAM_WE = 0
);
assign DDRAM_CLK = clk;

// Physical base 0x3A000000 / 8.
localparam [28:0] QBASE       = 29'h07400000;
localparam [28:0] Q_CONTROL   = QBASE + 0; // ARM -> FPGA
localparam [28:0] Q_JOY       = QBASE + 1; // FPGA -> ARM: joy1:joy0
localparam [28:0] Q_STATUS0   = QBASE + 2; // status[63:0]
localparam [28:0] Q_HEART     = QBASE + 3; // magic + counter
localparam [28:0] Q_STATUS1   = QBASE + 4; // status[127:64]
localparam [28:0] Q_MOUNT     = QBASE + 5; // img mount edge/count

reg [15:0] div = 0;
reg tick = 0;
reg mount_d = 0;
reg [31:0] mount_count = 0;

always @(posedge clk) begin
    if(reset) begin
        div <= 0;
        tick <= 0;
        mount_d <= 0;
        mount_count <= 0;
        heartbeat <= 0;
    end else begin
        tick <= 0;
        if(div == 16'd49999) begin // about 1 ms at 50 MHz
            div <= 0;
            tick <= 1;
            heartbeat <= heartbeat + 1'd1;
        end else div <= div + 1'd1;

        mount_d <= img_mounted;
        if(img_mounted != mount_d) mount_count <= mount_count + 1'd1;
    end
end

localparam S_IDLE=0, S_RCTRL_REQ=1, S_RCTRL_WAIT=2,
           S_WJOY=3, S_WST0=4, S_WST1=5, S_WHEART=6, S_WMOUNT=7;
reg [3:0] state = S_IDLE;

always @(posedge clk) begin
    DDRAM_RD <= 0;
    DDRAM_WE <= 0;
    DDRAM_BURSTCNT <= 1;
    DDRAM_BE <= 8'hFF;

    if(reset) begin
        state <= S_IDLE;
        arm_control <= 0;
    end else begin
        case(state)
            S_IDLE: if(tick) state <= S_RCTRL_REQ;

            S_RCTRL_REQ: if(!DDRAM_BUSY) begin
                DDRAM_ADDR <= Q_CONTROL;
                DDRAM_RD <= 1;
                state <= S_RCTRL_WAIT;
            end

            S_RCTRL_WAIT: if(DDRAM_DOUT_READY) begin
                arm_control <= DDRAM_DOUT;
                state <= S_WJOY;
            end

            S_WJOY: if(!DDRAM_BUSY) begin
                DDRAM_ADDR <= Q_JOY;
                DDRAM_DIN <= {joystick_1, joystick_0};
                DDRAM_WE <= 1;
                state <= S_WST0;
            end

            S_WST0: if(!DDRAM_BUSY) begin
                DDRAM_ADDR <= Q_STATUS0;
                DDRAM_DIN <= status[63:0];
                DDRAM_WE <= 1;
                state <= S_WST1;
            end

            S_WST1: if(!DDRAM_BUSY) begin
                DDRAM_ADDR <= Q_STATUS1;
                DDRAM_DIN <= status[127:64];
                DDRAM_WE <= 1;
                state <= S_WHEART;
            end

            S_WHEART: if(!DDRAM_BUSY) begin
                DDRAM_ADDR <= Q_HEART;
                DDRAM_DIN <= {32'h56504C59, heartbeat}; // "VPLY"
                DDRAM_WE <= 1;
                state <= S_WMOUNT;
            end

            S_WMOUNT: if(!DDRAM_BUSY) begin
                DDRAM_ADDR <= Q_MOUNT;
                DDRAM_DIN <= {32'd0, mount_count};
                DDRAM_WE <= 1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end
endmodule
