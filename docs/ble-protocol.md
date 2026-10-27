# StandUp BLE v1

适用设备：ESP32-C2 / ESP32-C3 + VL53L1X。iPhone 为 Central，开发板为 Peripheral。测量对象是**升降台与固定台面的间距**；距离大表示站立高度，距离小表示坐姿高度。桌台高度不能证明使用者实际在桌前或采取何种姿势。C2 与 C3 使用同一组 UUID 和测距帧，固件编译目标必须匹配实际芯片。

## 广播与连接

- Local Name：`StandUp-XXXX`，后缀来自 BLE 地址末两字节。
- 使用 legacy connectable advertising，ADV 包放 Flags 与完整 128-bit Service UUID；名称放 Scan Response，避免超过 31 字节。
- 同时连接一台手机；断开后重新广播。App 首次手动连接与订阅总超时 12 秒；监测过程中意外断连会向同一设备提交等待重连的请求，无轮询定时器。用户主动断开会取消等待重连。
- App 默认按服务扫描；“显示所有 BLE 设备”用于扫描测试，未广播本服务的设备不会出现连接按钮。
- 原型固件无需配对，不要求加密；只提供只读测距数据，无写入控制接口。

## GATT

| 对象 | UUID | 属性 | 内容 |
| --- | --- | --- | --- |
| Service | `A3C90001-8E64-4B6B-9C21-42B72A103A10` | Primary | StandUp 测距服务 |
| Measurement | `A3C90002-8E64-4B6B-9C21-42B72A103A10` | Read / Notify | 12 字节 v1 测距帧 |
| Device Info | `A3C90003-8E64-4B6B-9C21-42B72A103A10` | Read | UTF-8，如 `1.0.0;VL53L1X` 或 `1.0.0;MOCK` |

订阅 Measurement 的 CCCD 后，固件约每 250 ms 通知最新快照。正常采样也约 250 ms 一次；I²C 超时或传感器重新初始化时会变慢。通知重复的快照保持同一序号，App 不把重复通知视为新数据。12 字节可在默认 ATT MTU 23 下完整发送，**不分包、不需要换行符**。

## 测距帧

多字节字段均为 **little endian**，距离单位为 **毫米**。I²C 传感器寄存器采用 big endian，由驱动转换；不要与 BLE 字节序混淆。

| 偏移 | 长度 | 字段 | 规则 |
| --- | --- | --- | --- |
| 0 | 1 | version | 固定 `0x01` |
| 1 | 1 | flags | bit 0：有效；bit 1：模拟数据；其他位必须为 0 |
| 2 | 2 | sequence | 每次采样递增，65535 后回到 0 |
| 4 | 4 | uptime_ms | 开发板启动以来的毫秒，约 49.7 天回绕 |
| 8 | 2 | distance_mm | 有效：40–4000；无效：`0xFFFF` |
| 10 | 1 | sensor_status | 见下表 |
| 11 | 1 | reserved | 固定 `0x00` |

| sensor_status | 意义 |
| --- | --- |
| 0 | 有效测距，flags bit 0 必须为 1 |
| 1 | 测量质量不合格或超出允许范围 |
| 2 | 传感器初始化、I²C 通信或型号检查失败 |
| 3 | 数据就绪超时，或尚未完成首次测量 |

无效帧必须同时满足：valid = 0、distance = `0xFFFF`、status ≠ 0。未来版本可新增非零状态值；App 将其作为无效测距。未知协议版本、保留位非零、长度错误或字段矛盾都会停止当前识别并显示协议错误。

跨端测试样例：真实有效距离 450 mm，序号 `0x1234`，uptime `0x12345678`。

```text
01 01 34 12 78 56 34 12 C2 01 00 00
```

模拟无效样例：序号 0、uptime 1、status 2。

```text
01 02 00 00 01 00 00 00 FF FF 02 00
```

App 使用 `(new - last) mod 65536` 接受差值 1–32767 的序号，忽略重复及倒序帧；新连接、状态恢复或超过 2 秒的数据空档后重新开始序号跟踪。单纯锁屏/解锁不重置新鲜数据。开发板重启会断开 BLE，重连后重新识别。

## 识别与设置

1. 手机按本机单调时钟记录接收时间。相邻接收间隔和开发板 uptime 差值都必须大于 0 且不超过 2 秒；计时时取两者较短值。uptime 用 UInt32 模减处理正常回绕；停滞、重启或长空档打断连续性并重新识别。界面定时刷新不增加累计时间。
2. 最近最多 5 次有效读数取中位数。
3. 未确定状态时按分界距离选择候选。默认 300 mm，大于等于分界为站立候选。
4. 已为坐姿时，须超过 `threshold + hysteresis` 才转为站立候选；已为站姿时，须低于 `threshold - hysteresis` 才转为坐姿候选。反向安装时镜像判断。
5. 候选连续稳定默认 1.5 秒后切换。中位数窗口还会引入少量切换延迟。
6. 无效数据立即清空识别；超过 2 秒无新有效数据，显示未知。断连、设置修改、状态恢复或数据连续性中断后重新等待稳定数据。锁屏保留真实 BLE 监测，手机演示暂停。

阈值 50–3950 mm；滞回半宽 0–100 mm，并约束在有效测距范围内；稳定时间 0.5–5 秒。两点校准取坐姿与站姿记录的中点，并自动确定方向。两点至少相差 40 mm。阈值与校准数据仅保存在 iPhone 的 UserDefaults，**不写入开发板**；固件只负责测距。

App 收到连续有效、前后识别姿态相同且已稳定的测距通知后统计这两次通知之间的会话时长，前台与后台规则一致。每日目标与历史记录额外要求 BLE 连接和订阅已就绪、测距帧不带模拟标记；手机演示与开发板模拟固件都不计入每日数据。有效站立时间计入目标，坐姿时间单独保存。每日数据保留含今天在内的最近 30 个本地日历日，跨零点拆分；过去日期保留当时目标。阈值、目标与每日记录都在手机本地管理，本次功能不改变 BLE 帧或开发板固件。

App 声明 `UIBackgroundModes: bluetooth-central`，用稳定的 CoreBluetooth 恢复标识保存连接与订阅；蓝牙唤醒启动时通过 AppDelegate 提前重建管理器，无需先显示界面。后台计时由通知驱动，停用 UI/演示定时器，不补算未观测的时间。锁屏不等于手动强退：手动划掉 App 后需重新打开并检查连接。后台仍受 iOS 调度影响，延迟或丢失数据会保守少算；不做离桌判断。

清零本次会话不会删除每日累计。默认每日目标 60 分钟，可设置 5–480 分钟。前台累计按秒提交本地保存，后台每次有效累计后保存，进入后台、断连等状态切换时也保存；异常强制终止可能丢失最近一次保存后的少量增量。

## 官方参考

- [Espressif：ESP32-C2 Bluetooth API](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32c2/api-reference/bluetooth/index.html)
- [Espressif：v5.4.2 NimBLE peripheral 示例](https://github.com/espressif/esp-idf/tree/v5.4.2/examples/bluetooth/nimble/bleprph)
- [Espressif：ESP32-C2 I²C master 驱动](https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32c2/api-reference/peripherals/i2c.html)
- [Apple：Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple：Core Bluetooth 后台处理与状态恢复](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- [Apple：后台状态恢复的重新启动条件](https://developer.apple.com/library/archive/qa/qa1962/_index.html)
- [ST：VL53L1X Ultra Lite Driver](https://www.st.com/en/embedded-software/stsw-img009.html)
- [ST：ULD 使用手册 UM2510](https://www.st.com/resource/en/user_manual/um2510-a-guide-to-using-the-vl53l1x-ultra-lite-driver-stmicroelectronics.pdf)
