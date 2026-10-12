# DM4310 运行反馈探测

## 失能状态下确认关节方向

新版输入 `r` 会依次给 ID1..4 发送失能命令，并打印每台收到的新反馈；不会发送使能命令。先支撑住机身和腿部，再输入 `r` 记录初始姿态。小幅移动一个关节后再输入 `r`，记录位置变化及实际运动方向。闭链机构可能让同侧两个关节一起变化，不要强行扳动。

先核实四台电机的 PMAX、VMAX、TMAX，当前换算假定分别为 12.5、30、10；若不一致，需改换算参数后重编译，不要为匹配程序盲目改电机配置。`s` 只显示缓存，不触发新查询。不要在手动移动关节时输入 `p`。

这个应用不会在上电时使能电机。USB_DEBUG 串口中输入 `p` 后，程序按 ID1、2、3、4 逐个执行：

1. 发送一帧使能命令：目标 ID，数据 `FF FF FF FF FF FF FF FC`；
2. 等待 Master ID `0` 的反馈并解析位置、速度、力矩、状态和温度；
3. 发送失能命令：目标 ID，数据 `FF FF FF FF FF FF FF FD`；
4. 再打印一次失能后的反馈。

在机械未固定、急停不可用或控制模式没有确认前，不要输入 `p`。先把机器人架空/固定，并把电机电源限制在安全范围。这个探测程序不发送 MIT 位置/速度/力矩控制帧，但“使能”本身可能产生保持力。

输出的 `state` 来自反馈 D0 高四位：`1` 为使能，`0` 为失能；D0 低四位应为对应电机 ID。位置单位 rad，速度单位 rad/s，力矩单位 Nm。`raw` 是完整八字节反馈，便于和 USB-CAN 抓包比较。

## 构建

在工程根目录执行：

```powershell
python .\softcore_apps\dm_runtime_probe\build_runtime_probe.py
```

通过 SecureCRT 的 `Transfer -> Send Binary File...` 发送生成的：

```text
softcore_apps\dm_runtime_probe\build\dm_runtime_probe_frame.bin
```

FPGA 必须先烧录支持 CAN0 动态 TX ID 和 DM ID1..4 分类寄存器的 `release/camera720_imu_softcore_can2_dm_feedback.fs`。
