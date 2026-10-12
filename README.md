# FPGA 轮腿机器人工程导航

这是 ACG138（RK3588 + GW5AT-60K）摄像头、BMI088、软核与 CAN 电机控制工程。仓库同时保存源代码、Gowin 工程/实现结果、可烧录位流、软核程序、资料和验证记录。请先根据本 README 找到与当前硬件版本匹配的文件；`.fs`、裸 `.bin` 和带帧头的 `*_frame.bin` 不能互相替代。

## 当前可验证的工作状态

- OV5640 摄像头经 FPGA/RGMII 输出 1280×720 RGB565 行包；RK3588 接收显示链路已有实测记录。
- BMI088 使用 SPI；FPGA Madgwick 六轴解算与同源样本的 Python 参考实现已有约 131 秒对照记录。该结果验证算法数值一致性，不等于绝对姿态精度或闭环平衡验收。
- CAN0 已验证 DM4310 ID 1–4 的参数读回、运行反馈分类以及短暂使能/失能反馈。
- CAN1 已验证两台 C620/M3508 的反馈和 `0x200` 组电流命令；软核有界轮转测试观察到轮子运动。
- 完整轮腿自平衡尚未完成。IMU 安装/零偏、关节几何和符号、DM 失联保护、整机参数与闭环增益仍需实测。

详细数据见 [`docs/硬件实测数据与当前结论.md`](docs/硬件实测数据与当前结论.md)、[`docs/balance/fpga_balance_bringup.md`](docs/balance/fpga_balance_bringup.md) 和 [`docs/imu/本次对话总结与实测分析.md`](docs/imu/本次对话总结与实测分析.md)。

## 顶层目录

| 路径 | 内容与用途 |
|---|---|
| `src/` | FPGA RTL。摄像头显示/OSD 在 `camera720/`，BMI088 与 Madgwick 在 `imu/`，CAN 在 `can_motor/`，软核/APB 在 `softcore/`，摄像头+IMU+软核+双 CAN 集成顶层在 `integrated/`。`_unused_legacy/` 与 `.before_*` 是旧实现/对照文件，未确认前不要删。各目录细节见相应 `README.md`。 |
| `camera720_*.gprj`、`can_motor.gprj` | Gowin IDE 工程入口。当前综合集成工程优先看 `camera720_imu_softcore_can2.gprj`；其它工程是单独阶段的相机、IMU demo 或 CAN 验证工程。`.gprj.user` 是本机 IDE 状态。 |
| `impl/` | Gowin 综合、布局布线、报告和临时实现输出；内容可很大，可再生成，但现存结果有调试/追溯价值，当前保留。不要把这里的任意 `.bin` 当软核程序。 |
| `release/` | 已导出的 FPGA `.fs`、对应 SHA-256、打包工程 ZIP，以及少量软核 framed BIN 与 RK 接收程序。文件名包含功能阶段；选择时查看对应软核应用 README 与 `SHA256SUMS.txt`。 |
| `softcore_apps/` | RISC-V 软核 C 程序及构建脚本：`actuator_diag/` 执行器诊断、`dm_runtime_probe/` DM 反馈探测、`c620_wheel_spin/` C620 有界转动、`balance_control/` 平衡控制框架和 `can_mmio_test/` MMIO 测试。`toolchain/` 含可用 Zig 工具链。各应用 README 说明键位、安全门槛和 framed BIN 用法。 |
| `softcore_standalone_v11/` | 曾独立验证的 Murax/VexRiscv SDK 1.1 烧录文件、bootloader 与构建记录；与当前集成软核应用分开放置。 |
| `sim/` | 仿真 testbench、IMU/CAN 采集记录。`sim/imu/live_capture.csv` 是用户实测串口采样；不要覆盖。仿真生成物可重新构建。 |
| `tools/` | 验证、构建和串口工具。`imu/` 是姿态解算校验/采集，`c620_diag/` 是 USB-CAN 诊断及配套 SDK 文件，根部 `build_*.tcl` 为 Gowin 构建脚本。 |
| `docs/` | IMU 验证、引脚核查、平衡准备、执行器/几何记录和烧录说明。这里是当前知识与实测结论的索引。 |
| `引脚约束以及资料/` | 开发板原理图、手册、BMI088/C620/M3508/DM4310/CAN 和摄像头资料。属于重要原始参考资料，请保留。 |
| `【重点】720P上位机与无线转发/` | RK3588 视频接收、无线转发和电脑显示工具，内含自己的 README。 |
| `archive(彩条测试)/` | 早期彩条/摄像头测试项目归档，保留历史验证用途。 |
| `tmp/` | FreeCAD/OCP 几何读取依赖、PDF 引脚审计数据和中间分析材料。虽然目录名为 `tmp`，现有内容不全是垃圾；在确认分析可复现前保留。 |
| `tmp_dm_device_sdk/` | DM 官方/配套 Device SDK 的独立副本，含多语言示例和库文件。与 `tools/c620_diag/` 的运行时文件用途不同，暂保留。 |
| `_整理待确认/` | 本次集中放置的缓存和资料提取中间产物，均未永久删除。说明与恢复方式见该目录 `归档说明.md`。 |

## 常用构建入口

### FPGA 位流

Gowin IDE 可打开相应 `.gprj` 并执行综合与布局布线。仓库也有 Tcl 构建入口，例如：

```powershell
gw_sh.exe .\tools\build_camera720_imu_softcore_can2.tcl
```

需在已配置好 Gowin 命令行环境时运行。构建工程/顶层与要烧录的 `.fs` 必须匹配。位流烧录后验证 FPGA 逻辑和引脚功能。

### 软核应用镜像

在工程根目录运行目标应用自己的 Python 构建脚本，例如：

```powershell
python .\softcore_apps\c620_wheel_spin\build_c620_wheel_spin.py
```

该脚本生成应用裸 `.bin` 和带 bootloader 帧头/CRC 的 `*_frame.bin`。串口 bootloader 要发送 framed BIN（SecureCRT 发送文件）；PuTTY/串口控制台不能把 FPGA `.fs` 当作 CPU 程序发送。具体应用目录 README 是命令和串口按键的准确信息来源。

### 烧录文件类型速查

| 文件 | 设备/用途 |
|---|---|
| `.fs` | Gowin FPGA 配置位流，通过 Gowin Programmer 下载到 FPGA 配置存储/器件。 |
| `*.bin` | 软核应用裸二进制，通常用于构建、封装或调试。bootloader 通常不直接接收它。 |
| `*_frame.bin` | 软核 bootloader 接收格式，包含帧头、长度与校验；通过 `USB_DEBUG` 的 FPGA UART bootloader 发送。 |
| `.gprj` | Gowin IDE 工程描述文件，不是烧录文件。 |

软核通常运行在 FPGA BRAM 中，重上电后需按对应 bootloader 流程重新加载；`.fs` 和 framed BIN 分属 FPGA 配置与 CPU 程序两个阶段。

## 维护约定

- 永久删除前先检查 Git 状态和文件来源；重要资料/数据优先移入 `_整理待确认/` 并写明用途。
- 不覆盖 `sim/imu/live_capture.csv`、已实测位流和用户尚未提交的修改。
- `_unused_legacy`、`impl/`、`release/`、CAD/PDF 原件与工具链都可能用于复现或回退，未确认前保留。
- 新测试请记录测试日期、镜像名及 SHA-256、接线、供电/安全状态、原始串口输出和单位；不要只记录计算后的结论。



