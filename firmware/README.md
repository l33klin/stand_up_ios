# StandUp ESP32-C2 固件

ESP-IDF **v5.4.2**、NimBLE、VL53L1X I²C 测距。首版默认打开模拟传感器，可先验证 BLE，再接入真实传感器。协议见 [BLE v1](../docs/ble-protocol.md)。

## 编译和烧录

先按 [Espressif 安装指南](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32c2/get-started/index.html) 安装 v5.4.2，并加载环境。以下命令从仓库根目录开始；串口名称用开发板的实际端口替换。

```sh
cd firmware
idf.py set-target esp32c2
idf.py menuconfig
idf.py build
idf.py -p /dev/cu.usbserial-XXXX flash monitor
```

`menuconfig → StandUp sensor`：

- 勾选 `Use simulated distance instead of VL53L1X`：无需接传感器，10 cm / 45 cm 每 15 秒切换，带少量抖动；所有读数标为模拟。
- 取消勾选：启用 VL53L1X。确认 SDA / SCL 引脚与开发板实际引脚一致。默认 SDA GPIO4、SCL GPIO5，**不是已经确认的板级接线**。

默认配置只在首次生成 `sdkconfig` 时加载。已有配置用 menuconfig 修改；`sdkconfig` 不提交仓库。默认只连接一台手机，不启用 Wi-Fi。

当前 ESP-IDF 默认板级参数为 **40 MHz 晶振、2 MB Flash**。开发板到货后需要按原理图或厂商说明确认，尤其 ESP32-C2 板可能使用不同晶振。在 menuconfig 按 `/` 搜索 `XTAL_FREQ` 和 `ESPTOOLPY_FLASHSIZE`，按实际规格设置；容量变化时同时检查分区表。GPIO 与这些参数尚未经过你的开发板验证。

## VL53L1X 接线与安装

以下针对支持 3.3 V 供电与逻辑电平的 **VL53L1X 转接模块**，裸芯片不可直接套用模块供电方式。先核对所购模块的丝印、电路和供电规格。

| ESP32-C2 | VL53L1X 模块 |
| --- | --- |
| 3V3 | VIN / VCC（模块须支持 3.3 V） |
| GND | GND |
| GPIO4（可配置） | SDA |
| GPIO5（可配置） | SCL |

I²C 7-bit 地址固定 `0x29`，100 kHz；使用模块已有上拉，若模块没有上拉则补到 3.3 V。代码开启内部弱上拉辅助，不应替代长线外部上拉。XSHUT 需要保持高电平，具有默认上拉的模块可悬空；GPIO1 中断脚不接，代码轮询数据就绪。避开开发板占用或启动配置引脚。若最低档实际间距小于 4 cm，需要改变安装位置或增加固定安装偏移。

把传感器固定在升降平台上，朝向不会随升降移动的台面，使读数随平台升高而增大。避免支架、线缆或人体进入视场；按 [ST 数据手册](https://www.st.com/resource/en/datasheet/vl53l1x.pdf) 的 4 cm 最小测距要求留出间距，且两种高度均应在可靠测量范围内。移除光学窗口上的运输保护膜。装好后在 App 分别记录坐姿、站姿高度。默认 30 cm 分界只是初始值，不代表你的实际桌台尺寸。

## 驱动行为

- 驱动在 `components/vl53l1x/`；初始化表和固定长距离配置移植自 ST，来源与许可见该目录 `NOTICE.md`、`default_configuration.h`。
- 型号 ID 校验 `0xEACC`；长距离模式；100 ms 测量预算、200 ms 内部测量周期，App 约每 250 ms 收到快照。
- 所有 I²C 操作和等待就绪均有超时，避免传感器掉线卡死 BLE。
- 只接受 ST raw range status 9（ULD 有效状态 0），其他质量状态上报无效，不能用 `65535` 参与坐站判断。
- 初始化失败每 5 秒重试；连续 3 次通信错误或就绪超时后重新初始化。测量质量不佳仍继续读取，不用模拟数据掩盖真实故障。
- 采样任务通过长度为 1 的 FreeRTOS 队列向 NimBLE host 传递完整快照；GATT 与连接状态均由 host 任务访问。

此驱动仅包含本项目需要的固定测量流程，不是完整 ST SDK。盖板、外壳导致的串扰、偏移和安装方向需要硬件到手后实际校验；App 两点校准是坐站分界校准，不替代传感器光学校准。

## 无开发板的协议检查

```sh
clang -std=c11 -Wall -Wextra -Werror -Imain main/distance_protocol.c tests/protocol_test.c -o /tmp/standup-protocol-test
/tmp/standup-protocol-test
```

这项检查验证帧编码，不验证 ESP32 无线、引脚和真实光学测量。硬件到手后的验收步骤见 [测试清单](../docs/testing.md)。
