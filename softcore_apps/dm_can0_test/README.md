# DM4310 CAN0 只读检测程序

本应用通过 CAN0 依次向 DM4310 ID 1、2、3、4 发送寄存器 `0x08 (ESC_ID)` 读取请求，并在 USB_DEBUG UART 输出发送 ACK/失败计数、反馈 CAN ID、8 字节原始反馈和累计响应数。程序不发送使能、失能或运动控制帧；上电默认关闭 CAN0 TX，只有发起只读参数询问时短暂开闸。CAN1 不被应用操作，原有 C620 测试程序仍单独保留。

## 目标 FPGA 工程

使用根目录的 `camera720_imu_softcore_can2.gprj` 综合本目录对应的新版 DM 测试 bitstream。当前已生成 `release/camera720_imu_softcore_can2_dm_feedback.fs`。该版本修改了 CAN0：TX 固定为标准 ID `0x7FF`，RX 过滤为 Master ID `0x000`，新增 DM 响应原始帧/ID/计数与 TX ACK/失败计数 MMIO。CAN1 的 `0x200` 发送、C620 `0x201/0x202` 接收逻辑保持不变。**旧的 C620 bitstream 不支持这里新增的 CAN0 寄存器，不能只烧本应用镜像。**

CAN0 FPGA 引脚仍是 `V15` TX / `T15` RX（开发板 P7 GPIO0/GPIO2），连接 3.3 V 逻辑 CAN 收发器 TXD/RXD。收发器 CANH/CANL 接 DM 总线。DM 电源独立按电机要求供电，控制器与收发器按硬件要求共地。终端电阻只开总线物理两端两个 120 Ω。

## 构建 CPU 镜像

在工程根目录 PowerShell 执行：

```powershell
python .\softcore_apps\dm_can0_test\build_dm_test.py
```

生成的 `softcore_apps\dm_can0_test\build\dm_can0_test_frame.bin` 是 SecureCRT bootloader 要发送的镜像（不要发送裸 `.bin` 或 `.elf`）。

## 测试步骤

1. 先用 Gowin 烧录新综合的 DM CAN0 bitstream；USB_DEBUG UART 设为 `115200, 8-N-1, no flow control`。
2. DM4310 设置为经典 CAN、1 Mbps、标准帧；四个接收 ID 为 1/2/3/4，Master ID 为 0。机械部分卸载或固定，保持全部电机失能。
3. CAN0 与总线接线正确后，在 SecureCRT 的 **Transfer -> Send Binary File...** 发送上面生成的 `_frame.bin`。
4. 期望每个约 100 ms 的轮询打印 `ACK+1`、`FAIL+0`，并收到反馈 CAN ID `0x000`；返回数据首字节低 8 位应对应被询问电机 ID，寄存器值应是 `01/02/03/04`。打印的完整 64 位数据按 CAN 字节序显示。若 ACK 有而 replies 不增长，重点检查 Master ID 是否真为 0、反馈 ID/过滤和总线连接。
5. 不要在本只读测试阶段使能电机。USB-CAN 监听可并接观察 `0x7FF` 查询和 ID `0` 回包；需要避免 USB-CAN 适配器周期性自动查询造成额外流量。

## 代码与构建脚本

`main.c` 是软核应用，`murax.h` 中的 CAN0 DM 寄存器地址必须与 `src/softcore/RobotApb.v` 一致。修改 C 代码仅需重建 `_frame.bin`；修改 CAN 过滤器、数据通路或寄存器映射则必须重新综合 FPGA bitstream。构建器复用本目录下的 Zig RISC-V 工具链和 CRC32 framed bootloader 格式。


