# 纯 FPGA 六轴姿态解算

`IMU sample → madgwick_imu → quaternion_euler → angle_bcd → osd_attitude_cdc → camera OSD`

不需要软核 CPU、STM32 或厂商浮点 IP。原 MQFU 的数学流程保留，但定点数据通路已经重写；原快照在 `vendor/mqfu/`，不参与综合。

## 输入、输出约定

- 所有加速度、角速度和四元数使用 **signed 32-bit Q8.24**，数值 = 有符号整数 / 2²⁴；总共 8 个整数位包括符号位。
- 加速度输入建议单位 g，范围按 BMI088 量程换算。角速度必须是 **rad/s**，不能直接输入 °/s 或寄存器原始值。
- `dt_q24` 为每组采样之间的实际时间，单位秒、24 位小数，按无符号输入接入；本版面向正值小周期，内部只使用 signed 正数范围。500 Hz 示例为 33554 / 2²⁴ s。
- 四元数为 Hamilton `(w,x,y,z)`，表示 body-to-world。单位姿态下静止加速度为 `(0,0,+1g)`。安装方向不同时在驱动层变换坐标。
- `roll_d10/pitch_d10/yaw_d10` 单位 0.1°；Roll、Yaw 包装到约 ±180°，Pitch 约 ±90°。±90° 附近 Euler 的 Roll/Yaw 存在奇异性，控制算法可直接使用四元数。
- `attitude_payload = {roll_negative,roll_bcd,pitch_negative,pitch_bcd,yaw_negative,yaw_bcd}` 共 51 bit。每个 BCD 是 `{百位,十位,个位,十分位}`。
- 只有 `valid && ready` 的时钟沿接收输入或取走输出；接收后输入可立即变化。输出被阻塞时保持稳定。
- `rst_n` 清除所有事务并恢复单位四元数。归一化后的加速度为零时仅积分角速度；零梯度不修正。梯度整数模长 ≤128（约 7.63×10⁻⁶）时跳过该步修正。

默认 `beta=1677722/2²⁴≈0.1`。24 位小数、中间 64/66 bit 不是“绝对无误差”；乘法/累加结果截取目标位宽，传感器输入须在物理量程内。当前未加入大运动加速度拒绝、在线零偏估计或磁力计融合。

## 模块

| 文件 | 功能 |
|---|---|
| `madgwick_imu.v` | 单个共享 32×32 乘法器执行六轴 Madgwick 运算 |
| `normalize_q24.v` | 四分量归一化，共享平方乘法器、整数开方和串行除法 |
| `isqrt_u66.v` | 66 bit 整数平方根，33 次迭代 |
| `quaternion_euler.v` | 四元数转 ZYX Euler 角 |
| `atan2_cordic.v` | CORDIC atan2，23 次迭代 |
| `angle_bcd.v` | 角度转四位 BCD 和符号 |
| `attitude_pipeline.v` | 采样到三路 OSD 字段的完整解算链 |
| `osd_attitude_cdc.v` | 握手邮箱跨时钟域传输，并在帧边界更新显示 |
| `imu_demo_source.v` | 模拟采样 ROM 驱动，供无 BMI088 时联调 |
| `spi_byte_engine.v` | BMI088 SPI mode-0 字节收发器 |
| `bmi088_spi.v` | BMI088 双片选初始化和 100 Hz 原始数据轮询 |
| `bmi088_q24.v` | BMI088 原始计数到 Q8.24 的量程换算 |
| `bmi088_telemetry_uart.v` | 每个解算样本经 USB_DEBUG 的 FPGA 串口发送原始值和角度 |

## 验证与使用

在工程根目录运行：

```powershell
python tools/imu/validate_all.py
```

依赖 Python、NumPy、Matplotlib、Icarus Verilog 和 vvp；当前环境已具备，未另行安装。结果自动写入被 Git 忽略的 `sim/imu/results/`，包含逐样本 CSV、JSON 总结和误差曲线。归档结果及说明见 `docs/imu/`。

`camera720.gprj` 默认保持占位值；`camera720_imu_demo.gprj` 使用模拟采样驱动真实解算 RTL，画面标题 **IMU / DEMO**。100 Hz、1024 组 ROM 样本按周期运动循环，输入数据由 `tools/imu/generate_demo.py` 生成，并非绕过解算直接让显示数字变化。

`camera720.gprj` 已将 BMI088 SPI 驱动接入 `attitude_pipeline`；`camera720_imu_demo.gprj` 继续使用 `imu_demo_source`。上板前还需要按安装方向补充坐标轴变换和静止零偏标定，不能把 demo 数据当作真实姿态。

六轴不能确定绝对航向，Yaw 随陀螺仪零偏漂移；静态倾斜测试只验收 Roll/Pitch 的收敛，不能用生成数据中的 Yaw 当作可观测真值。当前验证也不能证明轮腿机器人可稳定运行一小时。

## 通过 USB_DEBUG 记录实测数据

实时 `camera720.gprj` 配置会把 BMI088 原始六轴计数和对应的 FPGA Roll/Pitch/Yaw 一起通过板载 CH340E FPGA 串口发送。USB_DEBUG 接电脑后，在设备管理器中选择 **FPGA 的 CH340E COM 口**，不要选 RK3588 的 CH9102F 控制台。串口参数为 115200、8-N-1、无流控。工程使用 FPGA_UART_TX 网络，封装脚 C13；该网络由底板连到 CH340E，无需额外飞线。

每帧 26 字节：`A5 5A`、32 位小端样本序号、`ax ay az gx gy gz` 六个有符号 16 位原始计数、Roll/Pitch/Yaw 三个有符号 16 位 0.1° 值，以及覆盖前 24 字节的 CRC-16/CCITT-FALSE（小端）。USB_DEBUG 的 FPGA COM 口可用：

```powershell
python -m pip install pyserial
python tools/imu/read_uart.py --port COM7 --output sim/imu/live_capture.csv
```

把 `COM7` 换成设备管理器中 CH340E 的实际端口。脚本校验帧头和 CRC，将原始值、FPGA 角度、同一批采样逐步运行的 Python 浮点 Madgwick 结果及角度差写入 CSV。记录开始时应复位 FPGA，使 FPGA 与 Python 都从单位四元数起算；若板子中途复位，需重新开始一份记录。每帧对应解算器接收的最新 BMI088 样本，100 Hz 下串口占用约 23% 带宽。

数学参考：用户提供的 MQFU RTL objective/Jacobian，以及 [经典 Madgwick IMU 方程参考实现](https://github.com/PaulStoffregen/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp)。Python 使用独立浮点 Hamilton 乘法、Jacobian 和 `math.sqrt`；没有照搬原仓库的定点 Python 模型。
