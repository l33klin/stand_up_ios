# StandUp

一个原生 iOS App，通过 BLE 连接 **ESP32-C2 + VL53L1X**，读取升降台与固定台面的间距，推断当前桌台处于坐姿还是站立高度。**距离大为站立、距离小为坐姿**，支持手动设置与两点校准。

首版包括蓝牙扫描、连接与订阅、实时距离、60 秒曲线、阈值与防抖设置、前台会话计时，以及不依赖开发板的手机演示。没有第三方 iOS 依赖，无账户或服务器。

界面预览：[初始页面](docs/previews/dashboard.png)、[演示页面](docs/previews/demo.png)。这些是临时 Mac Catalyst 构建的进程内渲染，不是 iPhone 真机截图。

## 在 iPhone 上运行

1. 用 Xcode 打开 [`ios/StandUp.xcodeproj`](ios/StandUp.xcodeproj)。App 最低 iOS 17；Xcode 需要安装 iOS 平台，并支持手机的系统版本。版本与 macOS 要求可查 [Apple Xcode 支持表](https://developer.apple.com/xcode/system-requirements/)。
2. Xcode → Settings → Accounts 添加你的 Apple ID。
3. 选中 StandUp target → Signing & Capabilities → Team，选择你的 Personal Team 或开发者团队，保持 Automatically manage signing。若 Bundle Identifier 冲突，把 `com.l33klin.StandUp` 改为你自己的唯一标识。
4. USB 连接、解锁 iPhone，并信任电脑。手机“设置 → 隐私与安全性 → 开发者模式”打开后，按系统提示重启并确认。
5. Xcode 顶部选择 `StandUp` scheme 和你的 iPhone，按 **⌘R**。若系统要求信任开发者，在手机设置中按提示处理。免费 Personal Team 的签名有有效期，过期需重新运行安装。

2026-10-22 重新检查本机环境：macOS 14.7.7、Xcode 15.4；iPhone 12 Pro Max（iOS 26.3）已连接，开发者模式已开启。当前 `xcodebuild -showdestinations` 明确报告 `iOS 17.5 is not installed`，因此应先在 Xcode → Settings → Platforms 安装当前 Xcode 对应的 iOS 17.5 组件，完成后重启 Xcode 并检查 Window → Devices and Simulators。组件安装参考 [Apple 官方说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。SDK 版本与手机系统版本不必完全相同；若补齐组件后仍明确提示设备系统不受支持，再按 Apple 支持表选择升级方案。安装 App 还需要配置 Apple ID 与开发签名。本仓库未包含签名证书或可直接安装的签名 IPA。

## 开发板未到时怎么测试

- **监测 → 开始演示**：拖动演示距离，或点“坐姿高度 / 站立高度”。默认分界 30 cm，超过分界并稳定约 1.5 秒后切换；中位数滤波会再增加少量延迟。
- **设置 → 两点校准**：在演示中设为 10 cm，记录坐姿高度；再设为 45 cm，记录站姿高度。两次记录会自动生成约 27.5 cm 分界。
- 关闭“模拟传感器读数有效”：距离消失、状态回到等待识别，计时停止。
- **设备 → 显示所有 BLE 设备 → 扫描蓝牙设备**：在 iPhone 真机验证权限请求与附近 BLE 广播。只广播 StandUp 服务的设备能连接；普通耳机、其他手机不保证持续广播或出现在列表中。

手机演示不请求蓝牙权限、不代表蓝牙链路已经测试通过。真实 BLE 扫描与连接请用 iPhone；iOS 模拟器用于界面和演示逻辑。

## 开发板到货后

按 [`firmware/README.md`](firmware/README.md) 配置 ESP-IDF v5.4.2 并烧录。可先保持默认模拟固件，确认 App 能发现 `StandUp-XXXX`、连接并收到带模拟标记的数据；接好 VL53L1X 后关闭模拟配置，重新烧录并进行两点校准。

第一版只根据桌台高度推断状态，不能检测人在不在桌前。只有 App 在前台且读数有效、识别稳定时累计当前会话时长；不含后台全天统计、久坐提醒或历史日报。阈值与校准记录自动保存在手机，曲线和本次会话时长不持久化。

## 工程结构与验证

```text
ios/StandUp.xcodeproj       可直接打开的 Xcode 工程与共享 scheme
ios/StandUp/Core/           跨平台协议解析、滤波与坐站分类
ios/StandUp/Bluetooth/      CoreBluetooth 扫描、连接与订阅
ios/StandUp/Views/          SwiftUI 监测、设备、设置页面
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
