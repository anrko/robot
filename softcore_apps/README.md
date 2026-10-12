# 软核应用程序

这里保存运行在融合 bitstream 中 Murax/VexRiscv 软核上的应用程序，和原始 SDK 分开，便于后续增加 IMU、CAN 和控制程序。

## `balance_control`

这是轮腿机器人平衡控制的安全框架。它包含 1 kHz 控制入口、四个 DM4310 和两个 C620 的反馈解析、CAN 帧打包以及 SAFE/ARMING/ACTIVE/DISARMING 状态机；当前 BMI088 使用占位输入且控制输出关闭，不能直接驱动机器人。详细缺失参数和后续步骤见 [balance_control/README.md](balance_control/README.md)。

## `imu_mmio_test`

这是只读的 IMU MMIO 验证程序。它每 200 ms 从 `0xF0030000` 读取：

- BMI088 初始化和采样状态；
- Roll、Pitch、Yaw（0.1°）；
- 加速度、陀螺仪原始值；
- 采样计数和采样年龄。

CAN 发送没有被打开，程序不会给电机发送帧。

在工程根目录运行：

```powershell
python .\softcore_apps\imu_mmio_test\build_mmio_test.py
```

脚本会生成：

```text
softcore_apps\imu_mmio_test\build\imu_mmio_test_frame.bin
```

这个 `_frame.bin` 才能通过 SecureCRT 的 **Transfer -> Send Binary File...** 发送给 bootloader。不要发送裸的 `.bin` 文件。

## 上板验证顺序

1. 先烧录 `release\camera720_imu_softcore_can2_mmio.fs`。
2. 打开 USB_DEBUG 对应的 COM 口，115200-8-N-1、无流控。
3. 按回车确认出现 `SDK 1.1 trap-ABI-v2 CRC32 (AA56)`。
4. SecureCRT 选择 **Transfer -> Send Binary File...**，发送 `imu_mmio_test_frame.bin`。
5. 预期串口每约 200 ms 出现一行，`init=1`，`samples` 持续增加；姿态角应与 OSD 基本一致，移动 BMI088 时 Roll/Pitch 应变化。
6. 用 ESC 可退出测试程序回到 bootloader；如果只想停止打印，可以复位 FPGA。

如果仍看到旧的模拟倒立摆自检输出，说明发送的是旧 `main_frame_v11.bin`，不能用来验证 MMIO。

## `can_mmio_test`

CAN 收发验证程序及接线说明见 [can_mmio_test/README.md](can_mmio_test/README.md)。默认不发帧；串口按 `0`/`1` 才各请求一路发送一帧全零测试数据。

## `c620_can1_test`

这是当前两台 DJI C620/M3508（反馈 ID `0x201`、`0x202`）的 CAN1 专用检测程序。它持续读取两台电机的反馈计数和 8 字节原始数据，串口输入 `s` 可立即打印，输入 `z` 才发送一次 `ID=0x200` 的全零电流帧。详细接线、烧录和 C 程序构建步骤见 [c620_can1_test/README.md](c620_can1_test/README.md)。

## `c620_wheel_spin`

单轮架空旋转采集程序。每次只向一台 C620 发送约 `0.488 A` 电流，按反馈编码器累计至 3 圈轮胎目标后发零电流；同时有 10 秒、550 rpm、50 ms 反馈过期和按键停止保护。它不会向 DM4310 发送使能或力矩命令。构建、按键与上板条件见 [c620_wheel_spin/README.md](c620_wheel_spin/README.md)。

## `dm_can0_test`

DM4310 的 CAN0 只读测试程序按 1/2/3/4 轮询寄存器 `ESC_ID`，打印 CAN ACK、Master ID 回复和完整数据；不会使能或驱动电机。它需要新位流 `release/camera720_imu_softcore_can2_dm4310.fs`，构建命令、接线和上板步骤见 [dm_can0_test/README.md](dm_can0_test/README.md)。
