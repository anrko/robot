# OV5640 720p CAM2 → RGMII/UDP

## 当前交付

- Gowin 工程：`camera720.gprj`
- 可通过 Gowin Programmer 加载的配置文件：`release/camera720_cam2_720p.fs`
- 目标器件：GW5AT-LV60PG484AC1/I0（GW5AT-60B）
- 视频模式：1280×720，RGB565，逐行 UDP；未使用 DDR
- UDP 目的地址/端口：192.168.0.3:6102
- FPGA 源地址：192.168.0.2

## 必须按此连接

1. 使用 MES-FMC-LPC-IO 转接卡；OV5640 双 DVP 子卡插在转接卡的 J2（40 针）上。
2. 摄像头必须接双 DVP 子卡 **CAM2/J5**，不要接 CAM1/J4。此工程相机总线按 CAM2 的引脚表约束。
3. CAM2 XCLK 由 FPGA 输出到转接卡 J2-13，对应 ACG138 FMC P16 的 LA15_N / FPGA H15。最终 P&R 报告确认 `cam_xclk` 在 H15。
4. 摄像头 DVP IO 为 3.3 V；接线前断电，将 ACG138 FMC 的 VADJ（P20）设置为 3.3 V，并确认转接卡及摄像头模块电源符合手册要求。不可带电插拔 FMC/摄像头子卡。
5. RGMII 引脚仍接开发板已有 RK3588 FPGA-RGMII 通路；RK3588 接收端使用 192.168.0.3，监听 UDP 6102。

## 烧录

在 Windows 打开 Gowin Programmer，连接开发板调试/下载接口，扫描器件后选择 `release/camera720_cam2_720p.fs`，执行 FPGA 配置。先使用 JTAG 临时加载验证；若要断电后仍保留，需要在 Programmer 中按开发板的配置 Flash 类型执行 Flash 编程，不能把 RK3588 的 `update.img` 当作 FPGA 位流。

## 构建与验证状态

用 Gowin V1.9.12.03 完成综合、布局布线、时序分析和 `.fs` 生成。最后一次构建时间为 2026-10-02 17:45。资源报告：逻辑 944、寄存器 554、BSRAM 8（其中 FIFO 由 Gowin BSRAM 实现）。UDP `data_length` 端口的 32→16 位不匹配已修正；RGMII ODDR 的常量端口位宽警告也已修正。

仍有两类事项须上板确认：

- P&R 报告有 PR1014：`clk50m_d` 使用普通布线资源作时钟，工具提示可能增加延迟/偏斜。构建完成不等于已在硬件上验证时序。
- 本位流尚未接 CAM2 实际采集验证。需确认上电后相机初始化成功、CAM2 PCLK/HREF/VSYNC 正常、RK3588 收到完整 720 行图像；如果未收到，先看 LED、I2C ACK、PCLK 和 UDP 包计数，不要先改 DDR。

本 `.fs` 的 SHA-256 见同目录 `SHA256SUMS.txt`。彩条基线保存在 Git 标签 `colorbar-ok-720p-rgb565`；本工程版本另有 `camera720-cam2-720p-rgb565` 标签。
