# ACG138 摄像头 + BMI088 + Murax + 双 CAN

这是第一阶段的同片集成工程，顶层为 `top_camera720_imu_softcore_can2`，工程文件为仓库根目录的 `camera720_imu_softcore_can2.gprj`。

## 已集成模块

- OV5640 720p 采集、RGB565 姿态信息 OSD 和 UDP/RGMII 视频发送。
- BMI088 SPI 采集与 FPGA Madgwick 姿态解算；OSD 接入真实传感器计算结果。
- Murax/VexRiscv RV32IM 软核及其 BRAM/bootloader，USB_DEBUG 串口用于 CPU 控制台和下载应用镜像。
- 两个独立的 CAN 控制器实例。DM 查询测试位流使用 CAN0 标准 `0x7FF` 查询、接收 Master ID `0x000`；平衡控制接口开发中，CAN0 增加了 MMIO 可选 TX ID 和按反馈数据 D0[3:0] 分流的 DM ID `1..4` 捕获寄存器（DM 反馈 CAN ID 均为 Master ID `0x000`），默认 TX ID 仍为 `0x7FF`，TX 仍默认关闭。CAN1 继续接收 C620 反馈 ID `0x201/0x202` 并保留 `0x200` 发送路径。

软核通过 RobotApb MMIO 读取 BMI088 姿态、CAN0 DM 响应及 CAN1 C620 状态；CAN TX 默认关闭。当前发布的 `release/camera720_imu_softcore_can2_dm_feedback.fs` 已包含 CAN0 可变 TX ID 与按 D0[3:0] 分类的 DM ID1..4 反馈寄存器，但配套应用仍是只读通信验证程序：DM 测试应用只发送参数读取帧，C620 应用仅提供一次全零组命令。尚无平衡控制程序；旧 bitstream 不能与新增 MMIO 应用混用。

## 构建和烧录

使用 Gowin IDE 打开 `camera720_imu_softcore_can2.gprj`，或运行：

```powershell
$env:PATH = 'C:\Users\HP\AppData\Local\Programs\Python\Python312;' + (($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'WindowsApps' }) -join ';')
& 'F:\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' 'C:\Users\HP\Desktop\gowin\gowin\gowin\tools\build_camera720_imu_softcore_can2.tcl'
```

成功生成的原始配置文件为 `impl/pnr/camera720_imu_softcore_can2.fs`。用于 DM4310 CAN0 测试的发布副本为 `release/camera720_imu_softcore_can2_dm4310.fs`。烧录后，USB_DEBUG 的 COM 口仍接到 FPGA UART：C13 为 FPGA TX、B13 为 FPGA RX。软核启动后通过相同 UART 进入 bootloader；使用 `softcore_apps/dm_can0_test/build/dm_can0_test_frame.bin` 启动 DM 只读查询应用。

## 接口与指示灯

| 信号 | FPGA 管脚 | 说明 |
|---|---|---|
| BMI088 SCLK / MOSI / MISO | H13 / G13 / M13 | SPI |
| BMI088 CSB1 / CSB2 | L13 / U20 | 加速度计 / 陀螺仪片选 |
| USB_DEBUG TX / RX | C13 / B13 | 软核 UART；BMI088 telemetry UART 已从此脚释放 |
| CAN0 TX / RX | V15 / T15 | P7 GPIO0 / GPIO2 |
| CAN1 TX / RX | U16 / N15 | P7 GPIO4 / GPIO5 |

CAN 引脚是 FPGA 逻辑电平，必须先接外部 CAN 收发器，再接 CANH/CANL；不能把 FPGA 引脚直接连接到 CANH/CANL。首次验证时不要连接已使能的电机，也不要把此位流当作电机控制固件。

- LED0：摄像头初始化完成。
- LED1：BMI088 初始化完成。
- LED5 / LED6：CAN0 / CAN1 收到通过过滤的帧后锁存点亮。
- LED7：系统时钟心跳。

## 验证状态与限制

独立 Murax 软核已在板上运行过 SDK v1.1 自检和 1 kHz 中断测试。融合工程已在本机完成 Gowin 综合、布局布线、时序分析和 bitstream 生成，但仍需要上板逐项确认视频、BMI088 OSD、软核 UART 和 CAN 接收。

当前布局布线报告资源约为 Logic 20%、Register 9%、BSRAM 38%、DSP 25%。工具报告 `clk50m_d` 使用通用布线资源作为时钟（PR1014），且 BMI088 的 INT1/INT3 未使用；首次上板后应检查功能和时钟稳定性。若后续增加软核 MMIO 桥，需要重新综合、布局布线并测试，不能沿用本报告的资源或时序结论。

