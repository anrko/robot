# ACG138 FPGA 720p RGB565 -> RK3588 RGMII 验证教程

本文记录从 FPGA 彩条、BSP 设备树、Docker 编译、Rockchip 烧录，到 RK3588 HDMI 显示的完整过程。

## 1. 最终链路

    FPGA 1280x720 RGB565 彩条
      -> 板内 RGMII
      -> RK3588 gmac1 / Linux eth0
      -> UDP 6102
      -> ARM64 接收程序
      -> GStreamer appsrc -> Wayland -> HDMI

本次最终验证成功：

- FPGA 工程成功综合、布局布线并生成 .fs；
- RK3588 设备树切换到 FPGA 直连的 gmac1；
- eth0 固定链路 carrier=1；
- RGMII RX 统计持续增加，RX errors=0、RX dropped=0；
- ARM64 接收程序成功显示 1280x720 RGB565 彩条；
- 不需要电脑网口、Python、板端 GCC 或 videoparse 插件。

## 2. 先认清两个网口

本板最终实测：

    eth0 -> fe1c0000.ethernet -> RK3588 gmac1 -> FPGA 板内 RGMII
    eth1 -> fe1b0000.ethernet -> RK3588 gmac0 -> 板载 PHY -> RJ45

因此 FPGA-RK3588 测试：

- 不需要电脑网口；
- 不需要插网线；
- eth1 没有网线时 NO-CARRIER 是正常的；
- 真正要配置和观察的是 eth0。

设备树中使用固定链路：

    &gmac1 {
        phy-mode = "rgmii";
        fixed-link {
            speed = <1000>;
            full-duplex;
        };
    };

carrier=1 只表示 Linux 接受了 fixed-link，最终还要比较 RX 包计数。

## 3. FPGA 调试发送协议

本次调试工程不使用 DDR 和大 FIFO，在 125 MHz GMII 域直接产生彩条。

    分辨率：1280x720
    格式：RGB565，2 字节/像素
    每行：1280x2 = 2560 字节
    UDP 目的端口：6102
    FPGA 源 IP：192.168.0.2
    RK3588 目的 IP：192.168.0.3
    目的 MAC：FF:FF:FF:FF:FF:FF

当前每个 UDP 包就是一行，且每行彩条内容相同。因此调试接收器可以将一条合法行复制 720 次组成一帧。真实视频协议应增加行号、帧号、丢包和超时处理。

RGB565 红色 16'hf800 在 FPGA 中发送为低字节在前：

    00 f8 00 f8 ...

ARM64 小端系统配合 GStreamer RGB16 可正确解释。

## 4. FPGA 端曾遇到的错误

复制例程加密 FIFO 后出现：

    ERROR (RP0007) : There is no SSRAM resource in current device

原因是 FIFO 无法映射到当前器件可用的 SSRAM。改为行为级大 FIFO 后又出现：

    ERROR (PR0003) : Failed to place with '654 REG(s) unPlaced'

原因是大 FIFO 被综合成大量寄存器，导致布局失败。为先验证 RGMII，调试版本去掉 FIFO/DDR，直接生成固定彩条。真实摄像头跨时钟和复杂处理仍可能需要 FIFO 或 DDR。

## 5. 为什么要编译 BSP

Buildroot BSP 不是 Ubuntu 软件包系统，通常没有 apt、Python、GCC，也不能把 .dtsi 当作普通配置文件直接复制到板端。

设备树必须经过：

    .dts/.dtsi -> DTB -> boot.img -> update.img -> eMMC

BSP 包含 U-Boot、Linux、设备树、Buildroot rootfs、启动固件和打包工具。修改设备树后必须重新生成并烧录 update.img。

## 6. WSL 中修改设备树

使用的片段：

    C:\Users\HP\Desktop\gowin\gowin\14_FPGA_摄像头1080p\project\board\acg138\kernel\dts\rk3588-acg138-fpga-rgmii.dtsi

WSL 中解压 BSP 到 Linux 文件系统，不要在 /mnt/c 或 /mnt/f 编译：

    mkdir -p ~/acg138-build
    tar -xzpf "/mnt/f/aaa比赛/小梅哥ACG138-RK3588 + FPGA 多核异构开发板/06_源码与补丁/ACG138-Offline-BSP-20260923-r4.tar.gz" -C ~/acg138-build
    cd ~/acg138-build/ACG138-Offline-BSP-20260923-r4

复制片段：

    cp "/mnt/c/Users/HP/Desktop/gowin/gowin/14_FPGA_摄像头1080p/project/board/acg138/kernel/dts/rk3588-acg138-fpga-rgmii.dtsi" sdk/yy3588_linux/arch/arm64/boot/dts/rockchip/

编辑主设备树：

    nano sdk/yy3588_linux/arch/arm64/boot/dts/rockchip/rk3588-acg138.dts

加入：

    #include "rk3588-acg138-fpga-rgmii.dtsi"

## 7. Docker 离线编译

前置检查：

    uname -m
    df -h /
    docker version

要求 x86_64、约 100 GB 可用空间，以及 Docker Client 和 Server。

加载编译镜像：

    export OFFLINE_ROOT="$PWD"
    bash bsp/scripts/load_offline_environment.sh

曾经出现：

    No such image: sha256:...
    Recorded builder is not installed.

这是交付包记录的 Docker 镜像 ID 与 Docker Desktop 导入后的 ID 不同。只要镜像标签已经加载，可将 bsp/scripts/offline_docker_image.sh 改为：

    OFFLINE_IMAGE=yy3588-sdk-build:ubuntu22.04
    docker image inspect "$OFFLINE_IMAGE" >/dev/null 2>&1 || return 1
    export OFFLINE_IMAGE

然后重新加载环境。

开始编译：

    bash bsp/scripts/build_offline_all.sh --modified-sources

阶段顺序：

    U-Boot -> Linux/设备树 -> Buildroot rootfs -> Recovery -> update.img

查看进度：

    tail -f logs/kernel-clean.log
    tail -f logs/rootfs-clean.log
    ls -lh logs

成功标志：

    UBOOT_CLEAN_EXIT=0
    KERNEL_CLEAN_EXIT=0
    ROOTFS_CLEAN_EXIT=0
    RECOVERY_CLEAN_EXIT=0
    FIRMWARE_PACK_EXIT=0
    Build complete: .../work/update.img

校验：

    cd work
    sha256sum -c SHA256SUMS

## 8. Windows 烧录

将镜像复制到 Windows：

    cp work/update.img "/mnt/c/Users/HP/Desktop/acg138-fpga-rgmii-update.img"

Get-FileHash 只能在 Windows PowerShell 执行，不能在 WSL 执行：

    Get-FileHash -Algorithm SHA256 -LiteralPath "C:\Users\HP\Desktop\acg138-fpga-rgmii-update.img"

串口中执行：

    sync
    reboot loader

## 9. J2、USB0/USB1 与 RockUSB

J2 / USB_Debug 内部是 USB Hub，提供 RK3588 串口、FPGA 串口和 FPGA USB-JTAG。它不应简单等同为 RK3588 RockUSB 烧录口。

推荐保持：

    J2 -> 串口
    USB0 或 USB1 -> 另一根数据线连接 Windows，用于 RK3588 烧录

没有设备时先安装 DriverAssitant_v5.13.zip，并优先尝试 USB-A 到 Type-C 数据线。

PowerShell：

    Expand-Archive -LiteralPath "F:\aaa比赛\小梅哥ACG138-RK3588 + FPGA 多核异构开发板\05_开发工具\upgrade_tool_v2.36.zip" -DestinationPath "C:\Users\HP\Desktop\UpgradeTool-v2.36" -Force
    $tool = "C:\Users\HP\Desktop\UpgradeTool-v2.36\upgrade_tool_v2.36\upgrade_tool.exe"
    $image = "C:\Users\HP\Desktop\acg138-fpga-rgmii-update.img"
    & $tool LD

第一次可能得到 connected(0)，通常是工具变量、驱动、数据线或 Type-C 口问题。

如果得到 Mode=Maskrom：

    List of rockusb connected(1)
    Mode=Maskrom

先把本次构建的 Loader 复制到 Windows：

    cp work/firmware/MiniLoaderAll.bin "/mnt/c/Users/HP/Desktop/acg138-MiniLoaderAll.bin"

PowerShell 中：

    $loader = "C:\Users\HP\Desktop\acg138-MiniLoaderAll.bin"
    & $tool DB $loader
    & $tool LD
    & $tool SFI $image
    & $tool UF $image

DB 是临时下载 Loader 到 RAM。只有 LD 显示 Mode=Loader、SFI 确认 RK3588 Update Firmware 后才执行 UF。不要执行 EF。

## 10. 烧录后配置 FPGA 接口

确认接口身份：

    ip -br link
    readlink -f /sys/class/net/eth0/device
    readlink -f /sys/class/net/eth1/device

本次实测：

    eth0 -> /sys/devices/platform/fe1c0000.ethernet
    eth1 -> /sys/devices/platform/fe1b0000.ethernet

配置 FPGA 直连接口：

    ip link set eth0 down
    ip link set eth0 mtu 4000
    ip addr replace 192.168.0.3/32 dev eth0
    ip link set eth0 up
    ip route replace 192.168.0.2/32 dev eth0

检查：

    ip -br addr show eth0
    cat /sys/class/net/eth0/carrier

期望地址为 192.168.0.3/32、carrier=1。720p RGB565 IP 包约 2588 字节，MTU=1500 不够，本次使用 4000。

## 11. ARM64 接收显示程序

板端没有 Python、GCC、nc，也没有 rawvideoparse/videoparse。因此在 WSL 使用 BSP 工具链交叉编译：

    tools/recv_rgb565_wayland.c
    tools/build_recv_rgb565_wayland.sh

编译：

    chmod +x tools/build_recv_rgb565_wayland.sh
    tools/build_recv_rgb565_wayland.sh ~/acg138-build/ACG138-Offline-BSP-20260923-r4 /mnt/c/Users/HP/Desktop/recv_rgb565_wayland

把生成的 ARM64 文件通过 U 盘复制到板端：

    cp /mnt/udisk/recv_rgb565_wayland /root/
    chmod +x /root/recv_rgb565_wayland

检查插件：

    gst-inspect-1.0 appsrc
    gst-inspect-1.0 videoconvert
    gst-inspect-1.0 waylandsink

运行：

    XDG_RUNTIME_DIR=/run WAYLAND_DISPLAY=wayland-0 /root/recv_rgb565_wayland

程序内部流程：

    UDP 6102 -> 接收 2560 字节行 -> 复制 720 行 -> appsrc
    -> videoconvert -> waylandsink

## 12. 判断 RGMII 是否正确

执行两次，间隔几秒：

    ip -s link show eth0

本次实测：

    第一次：RX bytes 2821327784，RX packets 1084292，errors 0，dropped 0
    第二次：RX bytes 4328182412，RX packets 1663406，errors 0，dropped 0

平均每包约 2602 字节：

    14 Ethernet + 20 IPv4 + 8 UDP + 2560 RGB565 = 2602

这证明 FPGA 正在发送、RGMII 已进入 RK3588 MAC、包长度正确且没有明显接收错误。carrier=1 单独不能达到这个结论。

## 13. 常见错误速查

| 现象 | 处理 |
|---|---|
| rawvideoparse 不存在 | 使用自定义 appsrc 接收器 |
| videoparse 不存在 | 同上 |
| Get-FileHash: command not found | PowerShell 命令误输入 WSL |
| Docker No such image: sha256 | 使用已导入的 yy3588-sdk-build:ubuntu22.04 标签 |
| connected(0) | 确认 $tool、驱动、数据线和 USB0/USB1 |
| Mode=Maskrom | 用 MiniLoaderAll.bin 执行 DB，再 LD |
| carrier Invalid argument | 网卡仍 DOWN，先 ip link set eth0 up |
| eth1 NO-CARRIER | eth1 是外部 RJ45，不是 FPGA 直连口 |
| PCIe Link Fail | 没有加载 PCIe Endpoint 工程时通常与本测试无关 |
| FIFO RP0007/PR0003 | 当前器件资源不足，调试版本先去掉大 FIFO |

## 14. 下次复现最短流程

    1. 下载 FPGA 彩条位流
    2. BSP 加入 gmac1 fixed-link 设备树
    3. Docker 编译 update.img
    4. 校验并复制镜像到 Windows
    5. 串口 reboot loader
    6. J2 接串口，USB0/USB1 接 RockUSB
    7. LD；Maskrom 时 DB MiniLoaderAll.bin
    8. LD -> Loader，SFI -> UF
    9. 启动后确认 eth0 -> fe1c0000
    10. 设置 eth0 MTU=4000、IP=192.168.0.3
    11. 运行 recv_rgb565_wayland
    12. 对比 ip -s link 的 RX packets/bytes/errors

核心原则：先验证 FPGA 发送，再验证设备树和 MAC，再验证 UDP 统计，最后验证图像显示。


执行 
ip link set eth0 down
ip link set eth0 mtu 4000
ip addr replace 192.168.0.3/32 dev eth0
ip link set eth0 up
ip route replace 192.168.0.2/32 dev eth0
确认：
cat /sys/class/net/eth0/carrier
应输出：
1
3. 启动彩条接收显示程序
如果程序已经保存在 /root，直接运行：
XDG_RUNTIME_DIR=/run WAYLAND_DISPLAY=wayland-0 /root/recv_rgb565_wayland
看到类似输出就表示正在接收：
Listening on UDP 6102...
RX packets=... bad_length=0 displayed_frames=...
然后 HDMI 屏幕应显示 1280×720 彩条。
注意：接收程序要先启动，再下载/运行 FPGA 彩条，避免 FPGA 一开始发送的数据丢失。
停止程序：
Ctrl+C
4. 如果程序不在 /root
通过 U 盘复制一次：
cp /mnt/udisk/recv_rgb565_wayland /root/
chmod +x /root/recv_rgb565_wayland
以后只要没有重新烧录整个系统，程序会一直保留在 /root。
5. 快速确认是否真的收到数据
另开一个串口终端执行：
ip -s link show eth0
等待几秒再执行一次：
ip -s link show eth0
应该看到：
- RX packets 增加；
- RX bytes 增加；
- errors=0；
- dropped=0。
这就是以后每次运行彩条测试的完整流程。