# MiSTer VideoPlayer Core — HDMI-first RC1

这是一个真正按 **MiSTer Hybrid Core** 思路组织的播放器工程，不依赖 `.MiSTer_SAM`。

## 目标体验

1. MiSTer 菜单加载 `_Other/VideoPlayer_YYMMDD.rbf`。
2. 按 MiSTer OSD/Menu 键。
3. `Load Video` 使用 MiSTer 自己的文件浏览器选择 AVI/MP4/MKV/MOV/MPG/M4V。
4. OSD 可调 Aspect / Scale / Seek Step / Auto Next，并提供 Pause / Previous / Next / Seek 动作。
5. 手柄走 MiSTer `hps_io` 标准输入，不再使用 Linux `/dev/input/js0` 作为播放器输入，所以可以用 MiSTer 的正常手柄映射体系。
6. ARM 负责解码；FPGA 负责 MiSTer OSD、手柄桥、双缓冲 framebuffer 切换。

## 架构

```
MiSTer Main / OSD
       │ hps_io
       ▼
VideoPlayer.rbf ── joystick/status/heartbeat ──► DDR control page
       │                                      ▲
       │ MISTER_FB RGB565                     │ /dev/mem
       ▼                                      │
MiSTer scaler ◄── DDR FB0/FB1 ◄──────── ARM VideoPlayer engine
                                              │
                                              └── FFmpeg decode + ALSA audio
```

### DDR 内存图

- `0x3A000000` ARM control qword：bit0 active FB，bit1 video-valid。
- `0x3A000008` joystick P1/P2。
- `0x3A000010` status[63:0]。
- `0x3A000018` heartbeat：`VPLY + counter`。
- `0x3A000020` status[127:64]。
- `0x3A000028` file-mount counter。
- `0x3A100000` FB0，RGB565 640×480。
- `0x3A196000` FB1，RGB565 640×480。

FPGA 每约 1ms 把手柄和 OSD 状态写进 DDR；ARM 把完整新画面写进后台 buffer，再切 control bit。FPGA只在 `FB_VBL` 边界切换 `FB_BASE`，目标是避免撕裂。

## 手柄逻辑

`CONF_STR` 定义：

`Pause, Vol-, Vol+, Size-, Size+, Info, Previous, Next`

ARM 收到的标准 MiSTer joystick：

- D-pad 左/右：快退/快进，秒数由 OSD `Seek Step` 决定。
- D-pad 上/下：上一视频/下一视频。
- Pause：暂停/继续。
- Vol-/Vol+：音量。
- Size-/Size+：画面缩放。
- Previous/Next：上一/下一视频备用键。

按键由 MiSTer 的输入映射体系分配，不再绑定某一只 M30 的 Linux button number。

## OSD 文件加载

`SC0,...,Load Video;` 使用 MiSTer 原生 file browser。选中的真实路径由 MiSTer 写入：

`/media/fat/config/VideoPlayer.s0`

常驻 ARM engine 读取这个路径并打开视频。

## 首先验证的稳定视频规格

为了减少变量，第一轮硬件验证请先用已经在你的勤谋 MiSTer 上验证过的：

- AVI
- XVID / MPEG-4 Part 2
- 640×480
- 30fps
- MP3 44.1kHz stereo

ARM build 同时启用了 MPEG-1/2、H.264、AAC、MP3，以及 AVI/MOV(MP4)/MKV/MPEG 容器；但更高分辨率 H.264 的流畅程度取决于 Cortex-A9 软件解码能力。

## 编译 FPGA

要求 Intel Quartus Prime Standard/Lite **17.0.2**，与 MiSTer Template 的推荐版本一致。

```bash
cd fpga
./bootstrap_sys.sh
./build_fpga.sh
```

`bootstrap_sys.sh` 会从官方 `MiSTer-devel/Template_MiSTer` 取当前 `sys/`；不要自行修改 `sys/`。

## 编译 ARM engine

电脑安装 Docker：

```bash
cd arm
./build_arm.sh
```

Docker 会交叉编译 ARMv7 静态 FFmpeg/engine，输出：

`release/games/VideoPlayer/VideoPlayer`

## 生成 SD 卡目录

```bash
./tools/assemble_sd.sh
```

最终：

```
release/
├── _Other/VideoPlayer_YYMMDD.rbf
├── games/VideoPlayer/VideoPlayer
├── Scripts/Install_VideoPlayer.sh
└── video/
```

把 `release/` **里面的内容**复制到 TF 卡根目录，运行一次：

`Scripts -> Install_VideoPlayer`

然后重启一次。daemon 会通过 `/media/fat/linux/user-startup.sh` 常驻；不加载 VideoPlayer core 时它只看 heartbeat，不解码、不占用视频输出。

## HDMI / CRT 状态

### RC1：HDMI 优先

本版本把 framebuffer 固定为 640×480 RGB565，并交给 MiSTer framework scaler；这是当前勤谋 MiSTer + HDMI 液晶最适合先做硬件验收的路径。

### Sony S32 RGBS

**本 RC1 不启用 15kHz RGBS native timing。** 原因是消费级 CRT 的 15kHz 时序/CSYNC 电平必须和具体 Sony S32 型号及你的 RGBS 改装方式一起验收。不能为了“功能看起来完整”就让一个未验证的 31kHz/错误同步信号进入消费 CRT。

CRT 版下一阶段会把 FPGA video path 改为 native 240p DDR reader（类似成熟 hybrid core 的 native CRT 路径），同时保留 HDMI scaler profile。源代码目录已经把 ARM 解码和输入/OSD与输出层解耦，所以不需要重写播放器逻辑。

## 可靠性声明

这个包是**源码完整的 RC1**，不是我在这里假装已经上你的勤谋硬件验收过的最终 RBF：当前运行环境没有 Quartus 17.0.2，也没有你的 MiSTer，因此我不能诚实地把未综合、未上板的东西称为“100%硬件验证”。

我刻意把 RC1 控制在可验证范围：

- 官方 MiSTer Template + `hps_io` + `CONF_STR`。
- 官方 `MISTER_FB` framebuffer 接口。
- ARM/FPGA 双缓冲切换。
- MiSTer 原生 OSD file browser。
- MiSTer 标准 controller mapping。
- HDMI 640×480 第一目标。
- CRT 暂不发送未验证 timing。

第一次综合/上板如果出现编译或接口差异，应该只需要针对当前 Template API 修正很小的接口层，而不是推翻整个播放器架构。
