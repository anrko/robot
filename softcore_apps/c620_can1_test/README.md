# DJI C620 / M3508 CAN1 检测程序

这个程序在 USB_DEBUG 串口输出两台电机的反馈，并在输入 `z` 时仅发送一次全零电流组命令。上电后不会自动发 CAN 帧，也不会驱动 CAN0。

## 功能和报文

- CAN1 接收标准帧 `0x201`（电机 ID 1）和 `0x202`（电机 ID 2），输出累计帧数、编码器角度、转速、电机实际电流原始值和温度。
- `s` 立即打印当前数据；默认每 500 ms 打印一次。
- `z` 使 CAN1 发送一帧标准帧 `ID=0x200, DLC=8, data=00 00 00 00 00 00 00 00`，即四个电机组电流命令均为零。串口会显示 CAN ACK/fail 计数变化。
- RX 的角度单位是编码器计数（0..8191），转速是 RPM，温度是摄氏度；实际电流保留原始有符号值，协议比例与正负号映射以 C620 手册/你的电机设置为准。

`0x200` 是 C620 对 1..4 号电机的组命令 ID；电机 1、2 的反馈 ID 分别为 `0x201`、`0x202`。因此 CAN1 总线上有两台电调时，它们共用一条 CAN 总线，靠不同反馈 ID 区分。

## CAN 接线和上电顺序

本版使用开发板 P7 的 CAN1 GPIO 对：FPGA `U16` 为 CAN1_TX，FPGA `N15` 为 CAN1_RX，连接到外部 CAN 收发器的 TXD/RXD。收发器 CANH/CANL 接到两台 C620 的 CANH/CANL 和 USB-CAN 的 CANH/CANL，所有设备共地。C620 两台电调的 CAN 接口并接在同一总线上即可。

终端电阻只保留总线物理两端的两个 120 Ω 终端；断电后在 CANH 与 CANL 间测量应约 60 Ω。CAN 总线速率设为经典 CAN、1 Mbps、标准 11-bit ID。FPGA 的 3.3 V 仅供逻辑收发器使用，不要从它给 C620/M3508 电机供电。

首次上板先让电机机械部分保持安全、轮子悬空或卸下负载；验证接收时不需要输入 `z`。验证发送前最好先断开电机动力电源，只保留电调逻辑/CAN 条件允许的测试接线，并用 USB-CAN 确认 `0x200` 和 8 个零字节。这个程序不会发非零电流命令。

## 在 Windows 上改 C 并生成镜像

1. 用 VS Code 或任意文本编辑器修改本目录的 `main.c`。寄存器和 UART 小函数在同目录 `murax.h`，启动和运行库在 `crt0.S`、`sdk.c`。每次修改后重新构建。
2. 在工程根目录 `C:\Users\HP\Desktop\gowin\gowin\gowin` 打开 PowerShell，运行：

   ```powershell
   python .\softcore_apps\c620_can1_test\build_c620_test.py
   ```

   工程已带 Zig 0.13 RISC-V 交叉编译器，无需另外安装 RISC-V GCC。也需要 Python 3。若使用自己安装的 Zig，可加参数 `--zig C:\path\to\zig.exe`。
3. 编译脚本生成 ELF、裸 `.bin` 和带 `AA56 + 长度 + payload + CRC32` 的串口 bootloader 镜像：

   ```text
   softcore_apps\c620_can1_test\build\c620_can1_test.elf
   softcore_apps\c620_can1_test\build\c620_can1_test.bin
   softcore_apps\c620_can1_test\build\c620_can1_test_frame.bin
   ```

   串口传输必须选择 `c620_can1_test_frame.bin`，不要选择裸 `.bin` 或 `.elf`。镜像 payload 必须小于等于 40 KiB，脚本会检查并打印 SHA-256。
4. 已生成的新版 bitstream 是 `release\\camera720_imu_softcore_can2_c620.fs`，SHA-256 保存在同目录的 `.sha256` 文件中。它包含当前 `RobotApb.v` 反馈寄存器映射；烧录这个文件后，USB_DEBUG 接电脑，串口设 `115200, 8 data bits, no parity, 1 stop bit, no flow control`。如果你之后修改 RTL，再用 `camera720_imu_softcore_can2.gprj` 重新综合。
5. 等待 bootloader 的 `boot>` 提示，在 SecureCRT 选择 **Transfer -> Send Binary File...** 发送 `c620_can1_test_frame.bin`。应出现 `received ... CRC32=...` 和 `jumping to 0x80002000`，随后显示 `DJI C620 / M3508 CAN1 test`。
6. 先观察自动状态行：两台电调正常上电并接入时，`ID1_count`、`ID2_count` 应持续增长，角度/转速/电流/温度应有数据。输入 `s` 可以立即查看；输入 `z` 才请求单次零电流帧。CAN ACK 增长说明总线上至少有一个 CAN 节点对发送帧作了 ACK；用 USB-CAN 看见 ID `0x200` 才能同时确认其收到的报文 ID 和 payload。

## 新建自己的 C 应用

复制 `c620_can1_test` 目录到新目录，修改 Python 脚本里的应用名/输出名，再编辑 `main.c`。本软核是 RV32IM、没有硬件浮点；优先使用整数或 `murax.h` 的 Q16.16。MMIO 地址必须和目标 FPGA 工程的 `RobotApb.v` 一致。C 程序只会改变 CPU 应用镜像；若要增加新的 FPGA 寄存器、CAN 数据通路或引脚，需同时改 RTL、Gowin 工程并重新生成 FPGA `.fs`。

编译/下载关系如下：

```text
main.c + crt0.S + sdk.c + app.ld
          │ build_c620_test.py / Zig
          ▼
c620_can1_test_frame.bin ──UART bootloader──► 已烧录的 FPGA bitstream 中运行
```

此目录源码和构建脚本可独立保存；`build/` 是可重建产物。当前 CAN1 接收数据通路依赖集成工程中的 `RobotApb.v` 寄存器，因此请使用对应的新 bitstream。
