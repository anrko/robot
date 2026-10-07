# OV5640 720p CAM2 → RGMII/UDP

## 2026-10-02 联调修正

- OV5640 必须输出 RGB565（寄存器 `0x4300=0x61`、`0x501f=0x01`）。此前的 RAW8 设置会让 1280 字节的传感器行被错误地当成 2560 字节 RGB565 行，导致 UDP 包跨行、行号出现在包中间并造成花屏。
- RGB565 输出还必须配套使用官方 720p 的裁剪、抽样、HTS/VTS 与 PCLK 分频参数；不能只在 RAW8 时序上修改输出格式，否则 I2C 初始化虽然完成，但 DVP/FIFO 无法形成可发送的完整 RGB565 行。
- RK3588 接收器只在收满 720 行后提交一帧，并在提交后清空行状态。正常日志中 `displayed_frames` 应约等于 `RX packets / 720`，不能接近 `RX packets`。
- 本次修正需要同时重新烧录 `release/camera720_cam2_720p.fs`，并替换 RK3588 上的 `release/recv_rgb565_wayland`。
- 接收器会把启动后收到的第一帧自动转换并保存为 `/root/camera_capture.bmp`，用于检查 RGB565 字节序、颜色通道与行同步；每次重新启动程序会覆盖该文件。
- 实机 BMP 验证确认 FPGA UDP 载荷已经是 RK3588 `RGB16` 所需的小端 RGB565 字节序，接收器不得再次交换每个像素的两个字节；重复交换会产生高频彩虹伪色。

## 当前交付

- Gowin 工程：`camera720.gprj`
- 可通过 Gowin Programmer 加载的配置文件：`release/camera720_cam2_720p.fs`
- 目标器件：GW5AT-LV60PG484AC1/I0（GW5AT-60B）
- 视频模式：1280×720，RGB565，逐行 UDP；未使用 DDR
- 画面左上角在发送前叠加轻透的飞行仪表风格 HUD：`IMU / ATTITUDE` 标题、`ROLL / PITCH / YAW` 占位读数，初始均为 `+000.0°`；青色标签、浅色数字与橙色角度单位，暗色面板保留底层画面可见，OSD 使用纯 Verilog 字符点阵
- UDP 目的地址/端口：192.168.0.3:6102
- FPGA 源地址：192.168.0.2
- RK3588 ARM64 接收显示程序：`release/recv_rgb565_wayland`

## 必须按此连接

1. 使用 MES-FMC-LPC-IO 转接卡；OV5640 双 DVP 子卡插在转接卡的 J2（40 针）上。
2. 摄像头必须接双 DVP 子卡 **CAM2/J5**，不要接 CAM1/J4。此工程相机总线按 CAM2 的引脚表约束。
3. CAM2 XCLK 由 FPGA 输出到转接卡 J2-13，对应 ACG138 FMC P16 的 LA15_N / FPGA H15。最终 P&R 报告确认 `cam_xclk` 在 H15。
4. 摄像头 DVP IO 为 3.3 V；接线前断电，将 ACG138 FMC 的 VADJ（P20）设置为 3.3 V，并确认转接卡及摄像头模块电源符合手册要求。不可带电插拔 FMC/摄像头子卡。
5. RGMII 引脚仍接开发板已有 RK3588 FPGA-RGMII 通路；RK3588 接收端使用 192.168.0.3，监听 UDP 6102。

## 烧录

在 Windows 打开 Gowin Programmer，连接开发板调试/下载接口，扫描器件后选择 `release/camera720_cam2_720p.fs`，执行 FPGA 配置。先使用 JTAG 临时加载验证；若要断电后仍保留，需要在 Programmer 中按开发板的配置 Flash 类型执行 Flash 编程，不能把 RK3588 的 `update.img` 当作 FPGA 位流。

## RK3588 上接收并显示

这个 RK 接收程序已由离线 BSP 的 AArch64 Buildroot 工具链交叉编译，接收 1282 字节摄像头行包（2 字节小端行号 + 1280×2 像素字节），按行号重组图像，再通过 GStreamer `appsrc -> videoconvert -> waylandsink` 显示；不需要 `rawvideoparse`、`videoparse` 或 Python/Pillow。也保留旧彩条 2560 字节行包的兼容接收。

1. 将 `release/recv_rgb565_wayland` 复制到 U 盘，在 RK3588 串口终端挂载后复制：

   ```sh
   cp /udisk/recv_rgb565_wayland /root/
   chmod +x /root/recv_rgb565_wayland
   ```

2. 设置 FPGA 直连网口（此前确认对应 `eth0` / `fe1c0000.ethernet`）：

   ```sh
   ip link set eth0 down
   ip link set eth0 mtu 4000
   ip addr replace 192.168.0.3/32 dev eth0
   ip link set eth0 up
   ip route replace 192.168.0.2/32 dev eth0
   cat /sys/class/net/eth0/carrier
   ```

   `carrier` 应为 `1`。先确认 `gst-inspect-1.0 appsrc` 与 `gst-inspect-1.0 waylandsink` 可用，并确保 HDMI 桌面已启动。

3. 接好 CAM2、上电并先启动接收器，再通过 Gowin Programmer 配置 FPGA：

   ```sh
   XDG_RUNTIME_DIR=/run WAYLAND_DISPLAY=wayland-0 /root/recv_rgb565_wayland
   ```

   程序每秒打印 `RX packets`、`bad_length` 和 `displayed_frames`。正常时包数和显示帧数应增加、`bad_length=0`，HDMI 上出现摄像头画面。Ctrl+C 退出。

若 `gst-inspect-1.0 appsrc` 找不到，说明当前 rootfs 缺少 GStreamer app 插件；这个 BSP 的 SDK 运行库和当前板上 rootfs 版本需要一致。若 `waylandsink` 报错，先确认 RK3588 的 Wayland/Weston 桌面已经运行。

## 构建与验证状态

用 Gowin V1.9.12.03 完成综合、布局布线、时序分析和 `.fs` 生成。2026-10-07 的构建已加入纯 Verilog 姿态 OSD，占位显示 `ROLL / PITCH / YAW` 与 `+000.0°`；美化版 HUD 采用透底暗色面板、青色标签、浅色读数和橙色单位。最新资源报告为逻辑 1336（1239 LUT、73 ALU）、寄存器 566、BSRAM 4。UDP `data_length` 端口的 32→16 位不匹配已修正；RGMII ODDR 的常量端口位宽警告也已修正。

仍有两类事项须上板确认：

- P&R 报告仍有 PR1014：`clk50m_d` 使用普通布线资源作时钟，工具提示可能增加延迟/偏斜。构建完成不等于已在硬件上验证时序。
- OSD 已通过 Icarus Verilog 仿真并完成 Gowin 综合布局布线；当前姿态是固定占位值，BMI088 与软核接口尚未接入。摄像头字符叠加效果仍需上板确认。
- 本位流和接收程序尚未在真实 CAM2 接线上端到端验证。需确认上电后相机初始化成功、CAM2 PCLK/HREF/VSYNC 正常、RK3588 收到完整 720 行图像；如果未收到，先看 LED、I2C ACK、PCLK 和 UDP 包计数，不要先改 DDR。

摄像头测试发现原工程的 UDP 行长度少乘了 RGB565 每像素 2 字节，旧位流发 1282 字节/行，只包含 1280 字节图像数据。已修正 FIFO 门限与 UDP 长度，当前新位流发送 2562 字节/行（2 字节行号 + 2560 字节 RGB565），接收器与之匹配。**请重新烧录此更新版 `.fs`，只替换 RK 接收程序而不更新 FPGA 位流仍会继续收到 1282 字节包。**

本 `.fs` 和 ARM64 接收程序的 SHA-256 见同目录 `SHA256SUMS.txt`。彩条基线保存在 Git 标签 `colorbar-ok-720p-rgb565`；摄像头工程版本另有 `camera720-cam2-720p-rgb565` 标签。
