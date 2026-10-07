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

## 验证与使用

在工程根目录运行：

```powershell
python tools/imu/validate_all.py
```

依赖 Python、NumPy、Matplotlib、Icarus Verilog 和 vvp；当前环境已具备，未另行安装。结果自动写入被 Git 忽略的 `sim/imu/results/`，包含逐样本 CSV、JSON 总结和误差曲线。归档结果及说明见 `docs/imu/`。

`camera720.gprj` 默认保持占位值；`camera720_imu_demo.gprj` 使用模拟采样驱动真实解算 RTL，画面标题 **IMU / DEMO**。100 Hz、1024 组 ROM 样本按周期运动循环，输入数据由 `tools/imu/generate_demo.py` 生成，并非绕过解算直接让显示数字变化。

BMI088 到货后替换 `imu_demo_source`：读取原始寄存器 → 量程换算 → 静止零偏标定 → 安装坐标变换 → 同步采样/时间戳 → `attitude_pipeline`。尚未添加 BMI088 总线驱动和物理引脚，不能把 demo 数据当作真实姿态。

六轴不能确定绝对航向，Yaw 随陀螺仪零偏漂移；静态倾斜测试只验收 Roll/Pitch 的收敛，不能用生成数据中的 Yaw 当作可观测真值。当前验证也不能证明轮腿机器人可稳定运行一小时。

数学参考：用户提供的 MQFU RTL objective/Jacobian，以及 [经典 Madgwick IMU 方程参考实现](https://github.com/PaulStoffregen/MadgwickAHRS/blob/master/src/MadgwickAHRS.cpp)。Python 使用独立浮点 Hamilton 乘法、Jacobian 和 `math.sqrt`；没有照搬原仓库的定点 Python 模型。
