# HyperGO

记录自定义地点，一键用 Google 地图导航；地图上查看所有地点和距离；多选地点自动排出最短路线。

## 功能

- **地点**：自定义名称、图标（SF Symbol 或 emoji）、颜色；点一下用 Google 地图导航；左滑编辑/删除，右上角「编辑」可拖动排序
- **地图**：显示所有地点和自己的位置，点图标看直线距离和预计用时；右上角「在中心添加」把地图中心存为新地点
- **路线**：勾选多个地点（最多 10 个），自动计算最短访问顺序（≤12 个点保证最优），画出路线并一键交给 Google 地图
- 左上角可切换出行方式：驾车 / 步行 / 骑行 / 公交

## 在 Mac 上运行

需要 Xcode 15 或更新版本，iPhone 需 iOS 17 或更新。

```bash
brew install xcodegen
cd HyperGO
xcodegen
open HyperGO.xcodeproj
```

1. Xcode → Settings → Accounts，登录你的 Apple ID（免费即可）
2. 选中 HyperGO target → Signing & Capabilities → Team 选你的「Personal Team」
3. 把 Bundle Identifier 改成独一无二的，例如 `com.你的名字.hypergo`（也可以改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 后重新 `xcodegen`）
4. 先选一个模拟器点 ▶ 试试；模拟器里可以在 Features → Location 设置模拟位置

## 装到自己的 iPhone（免费 Apple ID）

1. 数据线连接 iPhone，在 iPhone 上信任这台电脑
2. iPhone：设置 → 隐私与安全性 → 开发者模式 → 打开（会重启）
3. Xcode 顶部设备选你的 iPhone，点 ▶
4. 第一次打开时，iPhone：设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书

免费签名 **7 天后过期**，到期重新连 Mac 点一次 ▶ 即可，数据不会丢。

## 说明

- 导航需要 iPhone 上安装 Google 地图 App；没装会打开网页版（网页版途经点较少）
- 最短路线按直线距离排序；道路距离和用时由 Apple 地图估算，仅供参考
