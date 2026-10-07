# MQFU 原始快照

此目录复制用户提供的 `Madgwick_Quaternion_Filter_Unit-main/Madgwick_Quaternion_Filter_Unit-main` 中独立 RTL 核心及 Apache-2.0 LICENSE。资料包未提供可确认的 upstream Git commit，故不编造版本号。

文件来自 `rtl/mqf/{madgwick.sv,madgwickDefines.vh}` 和 `rtl/fast_inv_sqrt/`。保留原文件，**不加入 Gowin 综合工程**。`tools/imu/validate_upstream.py` 可重现默认参数下输入非零 Z 轴角速度、输出四元数仍停在单位姿态的问题。

生产实现为上两级目录中的 `madgwick_imu.v`。沿用 MQFU 的 gyro derivative、gravity objective、Jacobian gradient、beta correction 数学流程，重整定点格式、共享乘法器、精确整数开方/串行除法归一化和输入输出握手。没有把算法换成 Mahony。

Apache-2.0 原许可证见 LICENSE；原快照与改写文件分开保存以便审阅。
