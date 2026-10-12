# 【重点】720P 上位机与无线转发

这个文件夹把当前已经验证过的 720P 接收程序和下一步的 Wi-Fi 转发链路集中放在一起，避免和 FPGA 工程、旧彩条测试混在一起。

## 当前已经有的程序

| 文件 | 作用 | 运行位置 |
|---|---|---|
| `01_现有程序_已验证/recv_rgb565_wayland_RK3588原有显示程序.c` | 接收 FPGA 的 UDP 行包，重组 1280×720 RGB565，通过 GStreamer/Wayland 显示 | RK3588 |
| `01_现有程序_已验证/recv_rgb565_wayland_RK3588原有显示程序` | 上述程序已经编译好的 ARM64 可执行文件 | RK3588 |
| `01_现有程序_已验证/recv_rgb565_udp_旧版单帧保存.py` | 旧的电脑端单帧保存程序，只接受 2560 字节旧彩条包 | 电脑 |
| `03_电脑接收显示/wifi_rgb565_receiver.py` | 新的电脑端 Wi-Fi 接收显示程序，支持当前 2562 字节摄像头行包和旧 2560 字节彩条包 | Windows/Linux 电脑 |

当前 FPGA 工程的目的地址仍然是 `192.168.0.3:6102`，不需要因为转发改 FPGA 位流。

## 推荐链路

```text
OV5640 -> FPGA RGB565 -> RGMII -> RK3588 eth0:192.168.0.3:6102
                                      |
                                      | rk3588_udp_wifi_relay
                                      v
                              RK3588 wlan0 -> Wi-Fi AP
                                                   |
                                                   v
                                           电脑:6102 -> 显示窗口
```

可以实现。第一阶段只转发原始 RGB565 UDP，不改图像格式，最容易验证；第二阶段再考虑在 RK3588 上编码 H.264/H.265，以降低无线带宽。

如果你的目标只是“把视频送到电脑”，不必一定购买 AX210。更简单的方案是使用板上已有的外部千兆网口 `eth1`，连接一个支持**无线网桥/客户端模式**的 5 GHz 路由器或旅行路由器：

```text
FPGA -> RK3588 eth0 -> RK3588 转发程序 -> eth1 网线
                                             |
                                      无线网桥/旅行路由器
                                             )) Wi-Fi ((
                                             |
                                            电脑
```

这个方案中无线网卡在外部路由器里，RK3588 只看到普通以太网，不需要 AX210、PCIe 转接卡或 AX210 固件。电脑和无线网桥加入同一个局域网即可。转发器运行时把最后一个参数从 `wlan0` 改为 `eth1`：

```sh
/root/rk3588_udp_wifi_relay 192.168.1.100 6102 6102 eth1
```

这里 `192.168.1.100` 是电脑在该无线局域网中的地址。开发板的 `eth1` 地址可以由无线网桥的 DHCP 分配，也可以手工设置静态地址。

可选方案才是在 J4 安装 AX210，让 RK3588 自己加入 Wi-Fi；它适合不想使用外部无线网桥的情况，但需要额外硬件、固件和无线驱动验证。

## 其他更小的转发方案

### 方案 A：RK3588 接 USB 5GHz Wi-Fi 网卡

这是体积最小的网络方案。USB 网卡插在开发板的 USB Host 口，RK3588 通过 `wlan0` 连接电脑热点或家用路由器，转发程序仍然使用：

```sh
/root/rk3588_udp_wifi_relay 电脑IP 6102 6102 wlan0
```

缺点是 Buildroot 必须包含该 USB 网卡芯片的内核驱动和固件；不能只看“USB 网卡插上有灯”就认为可用。先检查：

```sh
lsusb
iw dev
dmesg | grep -iE 'wlan|firmware|rtl|8812|8822|8852'
```

USB 网卡还要考虑吞吐。当前原始 RGB565 720P30 约 442 Mb/s，普通 USB2/2.4GHz 小网卡大概率不够稳定；如果采用这个方案，建议同时把视频改为 RK3588 硬件 H.264/H.265 编码。

### 方案 B：电脑开 5GHz 热点，开发板 USB 网卡直接连接

这比增加无线网桥更小：电脑负责开热点，开发板只需要 USB Wi-Fi 网卡。电脑热点应使用 5GHz、较近距离和固定非 DFS 信道。这个方案仍受 USB 网卡驱动和无线吞吐限制。

### 方案 C：专用无线视频发射器

这类设备可以直接传 HDMI/UVC 视频，10 米范围内通常比原始 UDP 稳定，但它不复用当前 FPGA 的 UDP 协议，需要增加 HDMI 输出或视频采集转换硬件，整体成本和改动反而可能更高。

### 方案 D：直接网线验证

开发板 `eth1` 直接接电脑，用静态 IP 验证转发程序。它不满足最终无线需求，但最适合先确认 FPGA→RK3588→电脑的软件链路没有问题。

蓝牙、普通 2.4GHz 低速无线模块和 ESP 类串口无线模块不适合承载当前原始 720P30 数据；它们需要先压缩视频，不能直接替换 UDP 转发链路。

## 1. 准备无线网卡和网络（AX210方案，可选）

BSP 资料已经确认 ACG138 的 J4 是 PCIe 扩展路径，资料中有 AX210 固件安装脚本和历史 2.4GHz 联网短测记录。AX210 要在断电状态安装并接天线。启动 RK3588 后先确认枚举和驱动：

```sh
lspci -nn
ip link
iw dev
dmesg | grep -iE 'iwlwifi|firmware'
```

`iw dev` 输出的接口名以现场结果为准，下面假设它叫 `wlan0`。不要把 SSID 或密码写入脚本和 Git；建立权限为 600 的配置文件：

```sh
cat >/root/wpa_supplicant.conf <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=0
country=CN
network={
    ssid="填写自己的WiFi名称"
    psk="填写自己的WiFi密码"
    key_mgmt=WPA-PSK
}
EOF
chmod 600 /root/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /root/wpa_supplicant.conf
udhcpc -i wlan0 -n -q
ip -4 addr show dev wlan0
```

如果系统已有 NetworkManager 或其他网络管理服务，不要再启动第二个 `wpa_supplicant`；先用该服务连接无线网。记下 RK3588 的无线地址和电脑的无线地址，例如 `192.168.1.20` 与 `192.168.1.100`。

## 2. 保持 FPGA 到 eth0 的现有配置

这组命令仍然按现有 720P 教程执行：

```sh
ip link set eth0 down
ip link set eth0 mtu 4000
ip addr replace 192.168.0.3/32 dev eth0
ip link set eth0 up
ip route replace 192.168.0.2/32 dev eth0
cat /sys/class/net/eth0/carrier
```

`carrier` 应为 `1`。确认无线出口路由正确：

```sh
ip route get 192.168.1.100
```

结果应选择 `wlan0`。把示例地址替换成电脑实际地址。

## 3. 在 RK3588 启动转发

优先使用 C 版本，因为当前 Buildroot 镜像不一定带 Python。使用 BSP 的 AArch64 交叉工具链编译：

```sh
./02_RK3588无线转发/build_rk3588_udp_wifi_relay.sh \
  /path/to/ACG138-BSP /tmp/rk3588_udp_wifi_relay
```

脚本使用 BSP 的 `work/buildroot/host/bin/aarch64-buildroot-linux-gnu-gcc`。也可以直接调用该交叉编译器：

```sh
aarch64-linux-gnu-gcc -O2 -Wall -Wextra \
  rk3588_udp_wifi_relay.c -o rk3588_udp_wifi_relay
```

把可执行文件复制到板端后运行：

```sh
chmod +x /root/rk3588_udp_wifi_relay
/root/rk3588_udp_wifi_relay 192.168.1.100 6102 6102 wlan0
```

参数依次是：电脑 IP、电脑端口、RK 监听端口、无线接口名。程序每秒打印 `RX/forward packets`。如果板端确实收到 FPGA 行包，计数会持续增加。

目录中也保留了 Python 参考实现 `02_RK3588无线转发/rk3588_udp_wifi_relay.py`，只有在板端确认存在 Python 3 时才使用：

```sh
python3 rk3588_udp_wifi_relay.py --target 192.168.1.100 --bind-device wlan0
```

## 4. 在电脑接收和观看

先安装 Pillow：

```powershell
py -m pip install pillow
```

允许 Windows 防火墙接收 UDP 6102，然后运行：

```powershell
py .\03_电脑接收显示\wifi_rgb565_receiver.py --bind 0.0.0.0 --port 6102 --save-dir .\captures --save-every 30
```

程序默认打开 1280×720 窗口。按 `Ctrl+C` 停止；`--headless` 可用于只接收/保存的测试。电脑端如果没有收到数据，依次检查 Windows 防火墙、电脑无线地址、板端 `RX/forward packets` 和电脑端口监听。

## 5. 带宽和可行性边界

原始 RGB565 的理论像素数据量为：

```text
1280 × 720 × 2 × 30 = 55.3 MB/s ≈ 442 Mb/s
```

再加 UDP/IP/802.11 开销，实际无线链路最好有 500 Mb/s 以上的稳定有效吞吐。5GHz/802.11ac 或 Wi-Fi 6、近距离、信号良好时可以先做验证；2.4GHz 拥塞环境可能丢包、卡顿。这个转发方案不会纠正 UDP 丢包，只会原样转发。

如果原始流在目标环境中带宽不够，下一步应改成：

```text
FPGA/RK3588 收到 RGB565 -> RK3588 硬件 H.264/H.265 编码 -> Wi-Fi RTP/UDP -> 电脑解码显示
```

这一步能把带宽从约 442 Mb/s 降到几十 Mb/s，适合长期稳定使用，但需要在 BSP 中启用 RK3588 V4L2 MPP/GStreamer 编码器，并重新验证延迟和丢包恢复。

## 6. 验证顺序

1. `lspci`、`iw dev`、`dmesg` 确认 AX210 已枚举并加载固件。
2. `wlan0` 获取地址，电脑与 RK3588 可以互相 `ping`。
3. 保持 FPGA `192.168.0.3:6102` 不变，启动 C 转发器。
4. 电脑启动 `wifi_rgb565_receiver.py`。
5. 观察板端转发计数、电脑端 `packets/displayed_frames`，再看窗口画面。
6. 用 `tcpdump -ni wlan0 udp port 6102` 或 Wireshark 检查无线侧是否有行包。
7. 最后再测 30 秒稳定性和丢包率，决定是否进入 H.264/H.265 优化。

