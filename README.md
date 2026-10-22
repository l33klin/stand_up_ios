# StandUp

一个原生 iOS App，通过 BLE 连接 **ESP32-C2 + VL53L1X**，读取升降台与固定台面的间距，推断当前桌台处于坐姿还是站立高度。**距离大为站立、距离小为坐姿**，支持手动设置与两点校准。

包括蓝牙扫描、连接与订阅、实时距离、60 秒曲线、阈值与防抖设置、每日站立目标、最近 30 天的历史记录、蓝牙锁屏监测与会话计时，以及不依赖开发板的手机演示。没有第三方 iOS 依赖，无账户或服务器。

界面采用冷白底与蓝色点缀：今天突出目标进度环和台面间距，历史按日汇总，校准与防抖收进设置二级页面。设计记录见 [design.md](design.md)。

界面预览：[今天](docs/previews/dashboard.png)、[手机演示](docs/previews/demo.png)、[历史空状态](docs/previews/history.png)、[目标设置](docs/previews/settings.png)、[设备扫描](docs/previews/devices.png)、[样例历史](docs/previews/history-sample.png)。这些是临时 Mac Catalyst 构建的进程内渲染，不是 iPhone 真机截图；样例历史仅用于展示布局，没有写入用户记录。

## 在 iPhone 上运行

1. 用 Xcode 打开 [`ios/StandUp.xcodeproj`](ios/StandUp.xcodeproj)。App 最低 iOS 17；Xcode 需要安装 iOS 平台，并支持手机的系统版本。版本与 macOS 要求可查 [Apple Xcode 支持表](https://developer.apple.com/xcode/system-requirements/)。
2. Xcode → Settings → Accounts 添加你的 Apple ID。
3. 选中 StandUp target → Signing & Capabilities → Team，选择你的 Personal Team 或开发者团队，保持 Automatically manage signing。若 Bundle Identifier 冲突，把 `com.l33klin.StandUp` 改为你自己的唯一标识。
4. USB 连接、解锁 iPhone，并信任电脑。手机“设置 → 隐私与安全性 → 开发者模式”打开后，按系统提示重启并确认。
5. Xcode 顶部选择 `StandUp` scheme 和你的 iPhone，按 **⌘R**。若系统要求信任开发者，在手机设置中按提示处理。免费 Personal Team 的签名有有效期，过期需重新运行安装。

2026-10-22 重新检查本机环境：macOS 14.7.7、Xcode 15.4；iPhone 12 Pro Max（iOS 26.3）已连接，开发者模式已开启。当前 `xcodebuild -showdestinations` 明确报告 `iOS 17.5 is not installed`，因此应先在 Xcode → Settings → Platforms 安装当前 Xcode 对应的 iOS 17.5 组件，完成后重启 Xcode 并检查 Window → Devices and Simulators。组件安装参考 [Apple 官方说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。SDK 版本与手机系统版本不必完全相同；若补齐组件后仍明确提示设备系统不受支持，再按 Apple 支持表选择升级方案。安装 App 还需要配置 Apple ID 与开发签名。本仓库未包含签名证书或可直接安装的签名 IPA。

## 开发板未到时怎么测试

- **今天 → 体验演示**：拖动演示距离，或点“坐姿高度 / 站立高度”。默认分界 30 cm，超过分界并稳定约 1.5 秒后切换；中位数滤波会再增加少量延迟。
- **设置 → 高度校准**：在演示中设为 10 cm，记录坐姿高度；再设为 45 cm，记录站姿高度。两次记录会自动生成约 27.5 cm 分界。
- 关闭“读数有效”：距离消失、状态回到等待识别，计时停止。
- **设备 → 包括其他蓝牙设备 → 扫描附近设备**：在 iPhone 真机验证权限请求与附近 BLE 广播。只广播 StandUp 服务的设备能连接；普通耳机、其他手机不保证持续广播或出现在列表中。

手机演示不请求蓝牙权限、不代表蓝牙链路已经测试通过。真实 BLE 扫描与连接请用 iPhone；iOS 模拟器用于界面和演示逻辑。

## 开发板到货后

按 [`firmware/README.md`](firmware/README.md) 配置 ESP-IDF v5.4.2 并烧录。可先保持默认模拟固件，确认 App 能发现 `StandUp-XXXX`、连接并收到带模拟标记的数据；接好 VL53L1X 后关闭模拟配置，重新烧录并进行两点校准。

## 每日目标与最近一个月的记录

- **设置 → 每日目标**：默认 60 分钟，可在 5–480 分钟之间调整，分多次站立也能累计完成。今天页显示今日站立、进度与剩余时长。
- 只有 **BLE 已连接并订阅成功、真实传感器读数连续有效、稳定识别为站立高度** 的时段才计入目标，包括锁屏或切到其他 App 时收到的数据。手机演示和开发板模拟固件不增加每日目标或历史时长。
- **历史**页显示最近 7 天站立趋势，以及最近 **30 个本地日历日（含今天）** 的每日站立、坐姿、目标和完成情况。点开日期可看详情；没有数据的日期不补记时长，超过保存期限的记录自动清理。
- 目标与每日数据保存在本机，前台累计时按秒保存，后台每次有效累计后提交保存；断连、进入后台、修改目标或清零本次会话时也提交保存。重开 App 继续累计当天已保存的数据，不补算未收到通知或断开的时间。
- 修改目标影响今天及之后，历史日期保留当时的目标。跨零点的有效时段拆分到对应日期。**清零本次会话不影响每日累计。**

App 只根据桌台高度推断状态，不能检测人在不在桌前。不含久坐提醒。阈值与校准记录自动保存在手机，距离曲线和本次会话时长不持久化。

## 锁屏与后台监测

1. 在前台连接开发板，收到真实测距后可以锁屏。已声明 `bluetooth-central`，由测距通知唤醒处理，不依赖后台定时器；手机演示在后台暂停。扫描仍只在前台进行。
2. 只有相邻两次有效且姿态稳定的测距才确认一段时长；同时检查手机单调时钟与开发板 `uptime_ms`，均须递增且间隔不超过 2 秒，取较短间隔。重复、倒序、传感器时钟停滞、批量延迟和长空档不会被补算。此保守策略可能少算系统延迟期间的站立时间。
3. 意外断连后停止累计，并向同一设备提交等待重连的请求；回到范围或开发板重启后恢复服务发现与订阅，重新等待稳定读数。在设备页点 **断开连接** 可取消监测与重连。关闭系统蓝牙或撤销权限后需重新打开 App 检查并连接。
4. 已实现 CoreBluetooth 状态恢复：系统因蓝牙事件重新启动 App 时，在创建界面前用原标识重建管理器，恢复外设代理、未完成的连接/服务发现/订阅。只恢复已保存的每日累计，进程退出期间不凭墙上时钟补记。
5. 后台接收受 iOS 调度和连接状态影响，不保证全天无中断。**手动从多任务界面划掉 App 后，不应期待后台继续接收**；需重新打开并检查连接。手机重启后先解锁一次。参见 [Apple 后台 BLE 指南](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html) 与 [状态恢复条件](https://developer.apple.com/library/archive/qa/qa1962/_index.html)。

锁屏计时逻辑有自动化测试；真实手机上的通知唤醒、断连重连和系统终止后的恢复仍待开发板到货后按 [验收清单](docs/testing.md) 测试。现有 BLE v1 帧已包含所需时间戳，无需为此修改固件协议。

## 工程结构与验证

```text
ios/StandUp.xcodeproj       可直接打开的 Xcode 工程与共享 scheme
ios/StandUp/Core/           跨平台协议解析、滤波与坐站分类
ios/StandUp/Bluetooth/      CoreBluetooth 扫描、连接与订阅
ios/StandUp/Views/          SwiftUI 今天、历史、设备、设置页面
firmware/                  ESP-IDF 工程、NimBLE 服务、VL53L1X 驱动
docs/ble-protocol.md        帧定义、UUID、错误状态与判断规则
docs/testing.md             验证结果与手工验收步骤
tests/                     Swift 核心逻辑与演示集成测试
```

仓库根目录运行：

```sh
swift test
clang -std=c11 -Wall -Wextra -Werror -Ifirmware/main firmware/main/distance_protocol.c firmware/tests/protocol_test.c -o /tmp/standup-protocol-test
/tmp/standup-protocol-test
xcodebuild -project ios/StandUp.xcodeproj -scheme StandUp -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

完整 App 构建需要可用的 Xcode iOS 平台。添加 Swift 文件后可运行 `python3 scripts/generate_project.py` 更新工程；生成器会重写工程的构建设置，已在 Xcode 修改过签名或 Bundle Identifier 时，先保留相应配置，再重新应用。常规打开与运行不需要执行生成器。
