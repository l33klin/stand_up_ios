# StandUp ESP32-C2 / ESP32-C3 固件

ESP-IDF **v5.4.2**、NimBLE、VL53L1X I²C 测距。首版默认打开模拟传感器，可先验证 BLE，再接入真实传感器。协议见 [BLE v1](../docs/ble-protocol.md)。

**当前已连接的开发板实际识别为 ESP32-C3（revision v0.4）、40 MHz 晶振、4 MB Flash。** 这块板请使用 `esp32c3`，最初文档中的 `esp32c2` 对应另一种芯片。两者使用相同 BLE 协议，iPhone App 无需更改。

## 编译和烧录

`idf.py`、`install.sh` 和 `export.sh` 都是 **Espressif 的 ESP-IDF SDK 自带脚本**，不在本仓库的 `firmware/` 或 `scripts/` 中。先安装 SDK，再在当前终端加载环境；USB 插上开发板不会自动提供这些命令。以下适用于 macOS 的 zsh/bash。

### 1. 安装并加载 ESP-IDF

首次安装可按 [Espressif v5.4.2 安装指南](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32c2/get-started/index.html) 准备系统依赖，再执行：

```sh
mkdir -p "$HOME/esp"
git clone --branch v5.4.2 --recursive https://github.com/espressif/esp-idf.git "$HOME/esp/esp-idf"
(cd "$HOME/esp/esp-idf" && ./install.sh esp32c2,esp32c3)
source "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

已经安装过则跳过 clone/install，用实际 SDK 路径执行 `source /实际路径/esp-idf/export.sh`。**每次新开终端都要加载一次环境**；成功后 `idf.py --version` 应显示 v5.4.2。`export.sh` 要用 `source` 加载，不能只作为独立程序运行。

本项目此前在当前 Mac 上做交叉编译时，临时环境装在 `/tmp/`。若这些目录仍在，可以直接使用，无需重新下载：

```sh
export IDF_TOOLS_PATH=/tmp/standup-idf-tools
source /tmp/standup-esp-idf/export.sh
idf.py --version
```

这两行路径必须配套使用：SDK 与编译器/Python 环境分开放在上述两个目录。`/tmp` 可能被系统清理，长期使用建议按前面的步骤安装到 `$HOME/esp/esp-idf`。使用新安装的默认工具目录时，先 `unset IDF_TOOLS_PATH`，避免继续指向旧的临时工具目录。

### 2. 找到开发板串口

```sh
ls /dev/cu.*
```

插入前后对比，选择新增的 USB 串口，例如 `/dev/cu.usbserial-*`、`/dev/cu.wchusbserial*`、`/dev/cu.SLAB_USBtoUART` 或 `/dev/cu.usbmodem*`。不要选择蓝牙耳机或 `Bluetooth-Incoming-Port`。

如果没有新增端口，先换支持数据传输的 USB 线并直连 Mac；若 macOS 弹出配件连接提示则允许。仍没有端口时，在“系统信息 → USB”确认是否能看到开发板，并按开发板厂商说明核对 USB 转串口芯片与驱动。未识别到串口时无法烧录，但不影响先编译。

### 3. 编译与烧录

**回到本仓库根目录**后执行下面的命令。下例使用当前识别到的 C3 和串口；设备重新插拔后请再次确认端口。

```sh
cd firmware
idf.py set-target esp32c3
idf.py menuconfig
idf.py build
idf.py -p /dev/cu.usbmodem5CFF0545021 -b 115200 flash monitor
```

如果实际购买的是 C2，则使用 `idf.py set-target esp32c2`。`set-target` 会重新生成配置，并将原 `sdkconfig` 保存到 `sdkconfig.old`，自定义传感器模式/引脚需重新确认。切换目标后必须重新编译，不能把 C2 二进制强制烧到 C3。

若烧录末尾只有 `ninja failed with exit code 1`，向前找第一条 `A fatal error occurred`，或读取提示的 `build/log/idf_py_stdout_output_*`。例如 `This chip is ESP32-C3, not ESP32-C2` 表示串口已经连通，应修改编译目标；这是芯片型号检查失败，不是 CMake 脚本丢失。

`sdkconfig.defaults.esp32c3` 为当前 C3 提供 4 MB Flash 和 **UART0 控制台**配置。当前 USB 设备识别为 `1A86:55D3 / USB Single Serial`，使用外置 USB-UART 桥接；不能仅凭 `/dev/cu.usbmodem*` 名称判断为 ESP32 原生 USB。如果已有配置选了 USB Serial/JTAG，在 `menuconfig → Component config → ESP System Settings → Channel for console output` 改为 `Default: UART0` 并重新编译烧录。真正使用 ESP32 原生 USB 接口的其他板子才选 USB Serial/JTAG，参考 [乐鑫控制台配置说明](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-guides/stdio.html)。

看到 `Hash of data verified` 和 `Done` 表示镜像已写入并校验；还需要确认程序启动。若监视器没有输出，松开 BOOT 后按一次 RESET/RST，或断电重插，再观察：

```sh
idf.py -p /dev/cu.usbmodem5CFF0545021 monitor
```

默认模拟固件应出现 `StandUp-XXXX ready (1.0.0;MOCK)`。串口退出快捷键为 **Ctrl+]**；监视器退出后再运行烧录命令，避免占用同一串口。2026-10-24 已完成当前 C3 的编译、烧录校验与 UART0 启动日志检查：NimBLE 发起广播，设备名为 **`StandUp-3D3E`**，日志为 `StandUp-3D3E ready (1.0.0;MOCK)`。用户随后已在 iPhone 上确认可以连接该设备并看到模拟数据；随后按文档接线并切换到真实模式，已在串口验证 VL53L1X 初始化、有效测距和手机连接后的连续通知，详见[实机记录](../docs/testing.md#vl53l1x-实机验收)。模拟数据不计入每日目标和历史累计。

`menuconfig → StandUp sensor`：

- 勾选 `Use simulated distance instead of VL53L1X`：无需接传感器，10 cm / 45 cm 每 15 秒切换，带少量抖动；所有读数标为模拟。
- 取消勾选：启用 VL53L1X。确认 SDA / SCL 引脚与开发板实际引脚一致。默认 SDA GPIO4、SCL GPIO5，当前用户按此接线后已通过初始化与串口测距检查；换板仍需核对实际 GPIO。

默认配置只在首次生成 `sdkconfig` 时加载。已有配置用 menuconfig 修改；`sdkconfig` 不提交仓库。默认只连接一台手机，不启用 Wi-Fi。

C2 的初始默认板级参数为 **40 MHz 晶振、2 MB Flash**；当前 C3 实测为 **40 MHz、4 MB Flash**。其他开发板仍需按原理图、厂商说明或烧录工具检测结果确认，尤其 C2 可能使用不同晶振。在 menuconfig 按 `/` 搜索 `XTAL_FREQ` 和 `ESPTOOLPY_FLASHSIZE`，按实际规格设置；容量变化时同时检查分区表。当前 GPIO4 / GPIO5 已完成一次实际接线、初始化和有效测距检查；模块供电规格与其他开发板引脚仍需各自核对。

## VL53L1X 接线与安装

以下针对支持 3.3 V 供电与逻辑电平的 **VL53L1X 转接模块**，裸芯片不可直接套用模块供电方式。先核对所购模块的丝印、电路和供电规格。

| ESP32-C2 / C3 | VL53L1X 模块 |
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
- 真实模式初始化成功后打印 `VL53L1X ready (SDA=4, SCL=5, address=0x29)`（引脚随配置变化），并约每 5 秒打印一次毫米读数或无效状态，方便串口排查。状态 1 表示质量/范围无效，2 表示初始化或通信失败，3 表示等待测量超时；BLE 通知仍约每 250 ms 更新。

此驱动仅包含本项目需要的固定测量流程，不是完整 ST SDK。盖板、外壳导致的串扰、偏移和安装方向需要硬件到手后实际校验；App 两点校准是坐站分界校准，不替代传感器光学校准。

## 无开发板的协议检查

```sh
clang -std=c11 -Wall -Wextra -Werror -Imain main/distance_protocol.c tests/protocol_test.c -o /tmp/standup-protocol-test
/tmp/standup-protocol-test
```

这项检查验证帧编码，不验证 ESP32 无线、引脚和真实光学测量。硬件到手后的验收步骤见 [测试清单](../docs/testing.md)。
