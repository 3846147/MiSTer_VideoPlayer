// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer VideoPlayer hybrid core - HDMI-first RC1
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

// OSD status layout (read by ARM through the DDR bridge):
// [3:2]  aspect     0=Original/4:3 canvas, 1=4:3, 2=16:9, 3=Full
// [5:4]  scale      0=Fit, 1=Fill, 2=1:1, 3=Custom
// [7:6]  seek step  0=5s, 1=10s, 2=30s, 3=60s
// [9:8]  auto next  0=Off, 1=On, 2=Loop one, 3=Loop all
// [32+]  action triggers
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

wire [1:0] buttons;
wire [127:0] status;
wire [31:0] joystick_0;
wire [31:0] joystick_1;
wire [0:0] img_mounted;
wire [63:0] img_size;

// J1 button #5 (joystick bit 9) may also open the framework OSD.
// Physical MiSTer Menu/Guide continues to work normally.
assign BUTTONS = {1'b0, joystick_0[9]};

hps_io #(.CONF_STR(CONF_STR), .VDNUM(1)) hps_io
(
    .clk_sys(CLK_50M),
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

// 640x480 native timing gives the MiSTer framework a stable base timing.
wire ce_pix;
wire hs, vs, de;
video_timing_640x480 timing
(
    .clk(CLK_50M),
    .reset(RESET),
    .ce_pix(ce_pix),
    .hs(hs),
    .vs(vs),
    .de(de)
);

assign CLK_VIDEO = CLK_50M;
assign CE_PIXEL  = ce_pix;
assign VGA_HS    = hs;
assign VGA_VS    = vs;
assign VGA_DE    = de;
assign VGA_R     = 8'h00;
assign VGA_G     = 8'h00;
assign VGA_B     = 8'h00;
assign VGA_SCALER = 1'b0;

// Framework framebuffer: ARM renders RGB565 into one of two DDR buffers.
// A DDR control word chooses the next buffer. Switching is latched on FB_VBL.
localparam [31:0] FB0_BASE = 32'h3A10_0000;
localparam [31:0] FB1_BASE = 32'h3A19_6000; // + 640*480*2 = 0x96000

wire [63:0] arm_control;
wire [31:0] heartbeat;

ddr_ctrl_bridge bridge
(
    .clk(CLK_50M),
    .reset(RESET),
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
always @(posedge CLK_50M) begin
    fb_vbl_d <= FB_VBL;
    if(!fb_vbl_d && FB_VBL) fb_sel <= arm_control[0];
end

assign FB_EN          = 1'b1;
assign FB_FORMAT      = 5'b0_0_100; // RGB565
assign FB_WIDTH       = 12'd640;
assign FB_HEIGHT      = 12'd480;
assign FB_BASE        = fb_sel ? FB1_BASE : FB0_BASE;
assign FB_STRIDE      = 14'd1280;
assign FB_FORCE_BLANK = ~arm_control[1]; // ARM sets video-valid only after first frame.

// Aspect is handled twice: the ARM compositor performs Fit/Fill/crop, while this
// tells the MiSTer scaler the intended display shape.
wire [1:0] aspect = status[3:2];
assign VIDEO_ARX = (aspect == 2) ? 13'd16 : (aspect == 3) ? 13'd0 : 13'd4;
assign VIDEO_ARY = (aspect == 2) ? 13'd9  : (aspect == 3) ? 13'd0 : 13'd3;

// Audio is produced by the ARM decoder through MiSTer's ALSA path. Keep core
// audio silent so the framework can mix/route HPS ALSA without double audio.
assign AUDIO_S = 1'b1;
assign AUDIO_L = 16'sd0;
assign AUDIO_R = 16'sd0;
assign AUDIO_MIX = 2'b00;

assign LED_USER = heartbeat[23];

endmodule
