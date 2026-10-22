# StandUp BLE v1

适用设备：ESP32-C2 + VL53L1X。iPhone 为 Central，开发板为 Peripheral。测量对象是**升降台与固定台面的间距**；距离大表示站立高度，距离小表示坐姿高度。桌台高度不能证明使用者实际在桌前或采取何种姿势。

## 广播与连接

- Local Name：`StandUp-XXXX`，后缀来自 BLE 地址末两字节。
- 使用 legacy connectable advertising，ADV 包放 Flags 与完整 128-bit Service UUID；名称放 Scan Response，避免超过 31 字节。
- 同时连接一台手机；断开后重新广播。App 手动重连，连接与订阅总超时 12 秒。
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

App 使用 `(new - last) mod 65536` 接受差值 1–32767 的序号，忽略重复及倒序帧；新连接与前台恢复时重新开始序号跟踪。开发板重启会断开 BLE，重连后重新识别。

## 识别与设置

1. 手机按本机单调时钟记录收到数据的时间，不依赖开发板 uptime 进行计时。
2. 最近最多 5 次有效读数取中位数。
3. 未确定状态时按分界距离选择候选。默认 300 mm，大于等于分界为站立候选。
4. 已为坐姿时，须超过 `threshold + hysteresis` 才转为站立候选；已为站姿时，须低于 `threshold - hysteresis` 才转为坐姿候选。反向安装时镜像判断。
5. 候选连续稳定默认 1.5 秒后切换。中位数窗口还会引入少量切换延迟。
6. 无效数据立即清空识别；超过 2 秒无新有效数据，显示未知。断连、设置修改、前后台切换也重新等待稳定数据。

阈值 50–3950 mm；滞回半宽 0–100 mm，并约束在有效测距范围内；稳定时间 0.5–5 秒。两点校准取坐姿与站姿记录的中点，并自动确定方向。两点至少相差 40 mm。阈值与校准数据仅保存在 iPhone 的 UserDefaults，**不写入开发板**；固件只负责测距。

首版仅统计当前会话中 App 在前台且识别稳定的时长。锁屏或后台暂停统计；不做全天后台监测、离桌判断和历史日统计。

## 官方参考

- [Espressif：ESP32-C2 Bluetooth API](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32c2/api-reference/bluetooth/index.html)
- [Espressif：v5.4.2 NimBLE peripheral 示例](https://github.com/espressif/esp-idf/tree/v5.4.2/examples/bluetooth/nimble/bleprph)
- [Espressif：ESP32-C2 I²C master 驱动](https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32c2/api-reference/peripherals/i2c.html)
- [Apple：Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [ST：VL53L1X Ultra Lite Driver](https://www.st.com/en/embedded-software/stsw-img009.html)
- [ST：ULD 使用手册 UM2510](https://www.st.com/resource/en/user_manual/um2510-a-guide-to-using-the-vl53l1x-ultra-lite-driver-stmicroelectronics.pdf)
