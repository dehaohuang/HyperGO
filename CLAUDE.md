# HyperGO 项目说明（给 Claude 看的背景）

## 用户与需求
- 用户不太懂编程和终端，请用简单中文沟通，尽量自己完成操作，少让用户手动敲命令。
- 用户在**加拿大**使用（坐标无偏移问题，Google 地图可正常使用，公制单位）。
- 没有付费 Apple 开发者账号：用免费 Apple ID（Personal Team）签名，装到自己的 iPhone，7 天需重新签名一次。不要使用需要付费账号的能力（iCloud/CloudKit、推送等）。

## App 功能
iOS 上的「快捷导航」App（只支持驾车）：
1. **地点**（首页）：分组显示成文件夹大图标（可自定义名称、图案、颜色，默认显示组内 4 个地点预览），未分组的地点放在外面；一排 4 个图标，图标下显示最短道路距离；点地点用 Google 地图导航；拖动排序（实时让位）、拖到文件夹上归组、长按菜单、多选批量操作、批量导入。
2. **地图**：MapKit 显示地点（名称自绘、按屏幕避让），可隐藏地图兴趣点文字；分组筛选可多选，和路线页互相独立。
3. **路线**：分组多选筛选，不限数量选地点，算最短访问顺序（≤12 点 Held-Karp 精确解，更多点多起点最近邻 + 2-opt + Or-opt），按 Google 地图 10 站上限自动分段导航。
- 设置：字体大小（只影响首页图标文字和地图地点名称）。
- 数据：SwiftData，`Place`（groupName 关联分组名）+ `PlaceGroup`（name/icon/colorHex/sortIndex）。
- 导航交给 Google 地图（`comgooglemaps://`，未安装时用网页版）。

## 技术栈
- SwiftUI + SwiftData + MapKit，最低 iOS 17，Swift 5 语言模式。
- 工程用 **XcodeGen** 生成：`project.yml` → `xcodegen` → `HyperGO.xcodeproj`（`.xcodeproj` 不入库）。
- 代码在 `HyperGO/`：`Models/`、`Services/`（定位、Google 地图跳转、路线算法）、`Views/`。

## 当前状态 / 下一步
- 2026-11-17：已在本机（Xcode 27.2）用 iPhone 18 Pro 模拟器（iOS 27.2）编译通过，无需改代码，App 能正常启动（首页「地点」+ 地图/路线标签，定位权限提示正常）。
- 本机没有 Homebrew：xcodegen 2.47.0 是从 GitHub 官方发布页下载的，路径 `~/.local/xcodegen-dl/xcodegen/bin/xcodegen`。`HyperGO/Info.plist` 由 xcodegen 生成，不入库。GitHub CLI 2.105.0 在 `~/.local/gh-dl/gh_2.105.0_macOS_arm64/bin/gh`，已登录并配置为 git 凭据，可直接 `git push`。
- 编译命令：`xcodebuild -project HyperGO.xcodeproj -scheme HyperGO -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build`
- 2026-11-17：已装到用户的 iPhone 11 Pro Max（Redbird's iPhone，UDID 00008030-001648DA0151802E），已配对、开发者模式已开、证书已信任，App 能正常打开。Bundle ID `com.dehaohuang.hypergo`，Personal Team `AG35R2KFF7`（已写入 project.yml）。
- 重新安装（7 天到期后）：同一 Wi‑Fi 下手机解锁，`xcodebuild -project HyperGO.xcodeproj -scheme HyperGO -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build` → `xcrun devicectl device install app --device 00008030-001648DA0151802E build/Build/Products/Debug-iphoneos/HyperGO.app`。新版 Xcode 没有「Connect via network」勾选框，配对后自动无线。
- （已完成）装到真机的步骤：Xcode 登录 Apple ID、Team 选 Personal Team、Bundle ID 改为唯一值（如 `com.dehaohuang.hypergo`）、iPhone 开启开发者模式并信任证书。
- 以后可能加的功能：桌面小组件、Siri 快捷指令、地点分组。
