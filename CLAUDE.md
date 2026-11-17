# HyperGO 项目说明（给 Claude 看的背景）

## 用户与需求
- 用户不太懂编程和终端，请用简单中文沟通，尽量自己完成操作，少让用户手动敲命令。
- 用户在**加拿大**使用（坐标无偏移问题，Google 地图可正常使用，公制单位）。
- 没有付费 Apple 开发者账号：用免费 Apple ID（Personal Team）签名，装到自己的 iPhone，7 天需重新签名一次。不要使用需要付费账号的能力（iCloud/CloudKit、推送等）。

## App 功能
iOS 上的「快捷导航」App：
1. **地点**（首页）：记录自定义地点，可自定义名称、图标（SF Symbol 或 emoji）、颜色；点一下用 Google 地图导航。
2. **地图**：MapKit 显示所有地点和当前位置，查看直线距离/预计用时。
3. **路线**：多选地点（最多 10 个），自动算最短访问顺序（≤12 点 Held-Karp 精确解，更多点用最近邻 + 2-opt），再交给 Google 地图多站导航。
- 导航本身交给 Google 地图（`comgooglemaps://`，未安装时用 `https://www.google.com/maps/dir/?api=1` 网页版）。

## 技术栈
- SwiftUI + SwiftData + MapKit，最低 iOS 17，Swift 5 语言模式。
- 工程用 **XcodeGen** 生成：`project.yml` → `xcodegen` → `HyperGO.xcodeproj`（`.xcodeproj` 不入库）。
- 代码在 `HyperGO/`：`Models/`、`Services/`（定位、Google 地图跳转、路线算法）、`Views/`。

## 当前状态 / 下一步
- 2026-11-17：已在本机（Xcode 27.2）用 iPhone 18 Pro 模拟器（iOS 27.2）编译通过，无需改代码，App 能正常启动（首页「地点」+ 地图/路线标签，定位权限提示正常）。
- 本机没有 Homebrew：xcodegen 2.47.0 是从 GitHub 官方发布页下载的，路径 `~/.local/xcodegen-dl/xcodegen/bin/xcodegen`。`HyperGO/Info.plist` 由 xcodegen 生成，不入库。
- 编译命令：`xcodebuild -project HyperGO.xcodeproj -scheme HyperGO -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build`
- 下一步：帮用户装到真机：Xcode 登录 Apple ID、Team 选 Personal Team、Bundle ID 改为唯一值（如 `com.dehaohuang.hypergo`）、iPhone 开启开发者模式并信任证书。
- 以后可能加的功能：桌面小组件、Siri 快捷指令、地点分组。
