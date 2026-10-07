# `src` 源码目录说明

当前默认工程是根目录的 `camera720.gprj`，顶层模块为 `top_camera720`。它实现：

`OV5640 CAM2/J5 DVP → RGB565 → 行 FIFO → UDP/RGMII → RK3588`

视频行进入 FIFO 前由 `attitude_osd_rgb565.v` 叠加轻透的飞行仪表风格 HUD：标题、`ROLL`、`PITCH`、`YAW`，青色标签、浅色角度数字和橙色单位。摄像头图像会透过暗色面板保留可见细节。当前三路数值固定显示为 `+000.0°`，使用纯 Verilog 5×7 字符点阵，不依赖厂商 RAM/IP；后续将占位 BCD/符号输入替换为姿态解算输出；纯 FPGA 演示接入见下文。OSD 已通过 Icarus Verilog 仿真和 Gowin P&R，尚未上板验证。

## 当前 720p 工程：`src/camera720`

新增独立的纯 FPGA 六轴 Madgwick 验证与接入链路，见 `src/imu/README.md` 和 `docs/imu/验证与烧录说明.md`。`camera720.gprj` 默认仍显示占位角度；`camera720_imu_demo.gprj` 将模拟 IMU 采样经过实际解算核心后送入 OSD，标题为 `IMU / DEMO`。模拟模式不代表已经连接 BMI088。

| 路径 | 用途 | 当前状态 |
|---|---|---|
| `top_camera720.v` | 顶层端口、LED、摄像头与 UDP 模块例化 | 已使用 |
| `ov5640_udp_rgmii.v` | PLL、摄像头采集、行号插入、发送链路连接 | 已使用 |
| `ov5640_init_table_raw.v` | OV5640 1280×720 RGB565 I²C 配置表 | 已使用；文件名沿用历史名称 |
| `camera720.cst` | GW5AT-60K、CAM2/FMC、RGMII 引脚和 IO 电平约束 | 已使用 |
| `camera720.sdc` | 时钟约束 | 已使用 |
| `camera_single/DVP_Capture` | DVP 8-bit 两字节拼接、HREF/VSYNC、行列计数 | 已使用 |
| `camera_single/camera_init` | I²C 初始化控制器及可选 OV5640/OV7725 配置表 | `camera_init.v`、I²C 两个文件已使用；JPEG/OV7725 表为保留备选 |
| `camera_single/eth_tx_ctrl` | 跨摄像头 PCLK 与 125 MHz 以太网时钟域的 FIFO 发送控制 | 已使用 |
| `camera_single/eth_tx_fifo` | Gowin FIFO IP 生成的双时钟 FIFO | 已使用；不要手工编辑加密区 |
| `camera_single/eth_udp_gmii` | UDP/IP/CRC 发送 | 已使用 |
| `camera_single/gmii_rgmii_gmii` | GMII 转 RGMII DDR 输出 | 已使用 |
| `camera_single/gowin_pll`、`pll_init.v` | 24 MHz XCLK、125 MHz 网口时钟等 PLL | 已使用 |
| `camera_single/mdio` | PHY MDIO 配置接口 | 当前工程保留例化，但综合可能优化掉；不影响构建 |
| `camera_common/camera_diag.v` | 诊断串口采样模块 | 未例化，保留作调试参考 |
| `camera_common/ov5640_af_loader.v`、`ov5640_af.hex` | OV5640 自动对焦固件加载器 | 当前禁用，保留作后续自动对焦功能 |

## `src/_unused_legacy`

这里放与当前摄像头 720p 工程无关的历史工程源码，例如 DDR3/VFB、彩条 RGMII 调试工程、旧的通用 PLL、串口调试模块和旧顶层文件。它们不在 `camera720.gprj` 的文件列表中，不能直接参与当前综合。

修改当前工程时只需打开 `camera720.gprj`，不要把 `_unused_legacy` 下的文件重新加入工程。

## 历史工程归档

根目录旧的彩条工程 `gowin.gprj` 已移动到 `archive/legacy_colorbar/`，其中还保留旧的接收脚本、调试脚本和仿真测试文件。需要回看旧实现时，从该目录取用即可；它们不会被 `camera720.gprj` 自动加载。

## 构建与运行相关文件

- `tools/build_camera720.tcl`：调用 Gowin `run all`，生成 `impl/pnr/camera720.fs`。
- `tools/recv_rgb565_wayland.c`：RK3588 接收 UDP、Wayland 显示并保存第一帧 BMP。
- `tools/build_recv_rgb565_wayland.sh`：使用 BSP AArch64 工具链交叉编译接收程序。
- `release/`：当前可烧录位流、RK 可执行文件、校验文件和完整压缩包。

`impl/` 是 Gowin 的综合/布局布线输出，属于可再生构建产物。原来的 `tmp/` 仅包含参考资料和临时实验副本，已删除，因为不是当前工程输入。
