# MiSTer VideoPlayer

MiSTer Hybrid VideoPlayer Core RC source.

## 最简单的编译方法

仓库上传完成后：

1. 打开 GitHub 仓库。
2. 点击 `Actions`。
3. 点击 `Build MiSTer VideoPlayer`。
4. 点击 `Run workflow`。
5. 等待构建结束。
6. 成功后在该次运行页面底部下载 `COPY_TO_TF` artifact。
7. 解压后，把里面内容复制到 MiSTer TF 卡根目录。

工作流会自动：
- 获取 MiSTer Template `sys/`
- 构建 ARM/FFmpeg 播放引擎
- 使用 Quartus 17 MiSTer Docker 镜像综合 FPGA
- 生成 `VideoPlayer.rbf`
- 打包 TF 卡目录

## 当前状态

这是 RC 工程。第一次 GitHub Actions 的真实 Quartus 日志用于发现并修正 FPGA/HPS 接口、QSF、时序等问题。
不要把“工作流启动成功”等同于“实机已经验证成功”。

## 首次视频测试格式

- AVI
- XVID / MPEG-4 Part 2
- 640x480
- 30fps
- MP3
