// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer VideoPlayer hybrid core - HDMI-first
module emu
(
`include "sys/emu_ports.vh"
);

///////// Defaults for unused ports /////////
assign ADC_BUS = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH,
        SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign LED_POWER = 0;
assign LED_DISK = 0;

`include "build_id.v"

localparam CONF_STR = {
    "Video Player;;",
    "SC0,AVI MP4 MKV MOV MPG M4V,Load Video;",
    "-;",
    "O[3:2],Aspect,Original,4:3,16:9,Full Screen;",
    "O[5:4],Scale,Fit,Fill,1:1,Custom;",
    "O[7:6],Seek Step,5 sec,10 sec,30 sec,60 sec;",
    "O[9:8],Auto Next,Off,On,Loop One,Loop All;",
    "-;",
    "T[32],Play/Pause;",
    "T[33],Previous Video;",
    "T[34],Next Video;",
    "T[35],Rewind;",
    "T[36],Forward;",
    "-;",
    "J1,Pause,Vol-,Vol+,Size-,Size+,OSD,Previous,Next;",
    "-;",
    "V,v",`BUILD_DATE
};

// MiSTer framework requires the core's video clock to be PLL-derived.
// The official Template_MiSTer PLL is copied into rtl/ by GitHub Actions.
// Its stock output is 20 MHz; this keeps the first bring-up deterministic.
wire clk_sys;
wire pll_locked;
pll pll
(
    .refclk(CLK_50M),
    .rst(1'b0),
    .outclk_0(clk_sys),
    .locked(pll_locked)
);

wire core_reset = RESET | ~pll_locked;
wire [1:0] buttons;
wire [127:0] status;
wire [31:0] joystick_0;
wire [31:0] joystick_1;
wire [0:0] img_mounted;
wire [63:0] img_size;

assign BUTTONS = {1'b0, joystick_0[9]};

hps_io #(.CONF_STR(CONF_STR), .VDNUM(1)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .EXT_BUS(),
    .gamma_bus(),
    .buttons(buttons),
    .status(status),
    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .img_mounted(img_mounted),
    .img_size(img_size)
);

// 20 MHz PLL clock, 672x496 total => ~60.004 Hz.
wire ce_pix;
wire hs, vs, de;
video_timing_640x480 timing
(
    .clk(clk_sys),
    .reset(core_reset),
    .ce_pix(ce_pix),
    .hs(hs),
    .vs(vs),
    .de(de)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_HS    = hs;
assign VGA_VS    = vs;
assign VGA_DE    = de;
assign VGA_R     = 8'h00;
assign VGA_G     = 8'h00;
assign VGA_B     = 8'h00;
assign VGA_SCALER = 1'b0;

localparam [31:0] FB0_BASE = 32'h3A10_0000;
localparam [31:0] FB1_BASE = 32'h3A19_6000;

wire [63:0] arm_control;
wire [31:0] heartbeat;

ddr_ctrl_bridge #(.CLK_HZ(20_000_000)) bridge
(
    .clk(clk_sys),
    .reset(core_reset),
    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .status(status),
    .img_mounted(img_mounted[0]),
    .arm_control(arm_control),
    .heartbeat(heartbeat),

    .DDRAM_CLK(DDRAM_CLK),
    .DDRAM_BUSY(DDRAM_BUSY),
    .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT),
    .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN),
    .DDRAM_BE(DDRAM_BE),
    .DDRAM_WE(DDRAM_WE)
);

reg fb_sel = 0;
reg fb_vbl_d = 0;
always @(posedge clk_sys) begin
    fb_vbl_d <= FB_VBL;
    if(!fb_vbl_d && FB_VBL) fb_sel <= arm_control[0];
end

assign FB_EN          = 1'b1;
assign FB_FORMAT      = 5'b0_0_100;
assign FB_WIDTH       = 12'd640;
assign FB_HEIGHT      = 12'd480;
assign FB_BASE        = fb_sel ? FB1_BASE : FB0_BASE;
assign FB_STRIDE      = 14'd1280;
assign FB_FORCE_BLANK = ~arm_control[1];

wire [1:0] aspect = status[3:2];
assign VIDEO_ARX = (aspect == 2) ? 13'd16 : (aspect == 3) ? 13'd0 : 13'd4;
assign VIDEO_ARY = (aspect == 2) ? 13'd9  : (aspect == 3) ? 13'd0 : 13'd3;

assign AUDIO_S = 1'b1;
assign AUDIO_L = 16'sd0;
assign AUDIO_R = 16'sd0;
assign AUDIO_MIX = 2'b00;

assign LED_USER = heartbeat[23];

endmodule
