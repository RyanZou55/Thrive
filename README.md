# Thrive

记录植物（尤其仙人掌 / 块根）生长与浇水的 iOS App。
亮点：**帮你每次都从同一角度拍照**，时间轴拉长后能明显看出变化。

需求文档见 [Thrive_MVP.md](Thrive_MVP.md)。

---

## 怎么跑起来（不需要懂 Swift）

1. 双击 `Thrive.xcodeproj`，Xcode 会打开工程。
2. 窗口顶部中间有个设备选择器，选任意一台 **iPhone 模拟器**（比如 iPhone 17 Pro）。
3. 按 `⌘R`（或点左上角的 ▶️）。第一次要等一两分钟编译。

模拟器里没有相机，所以拍摄页会自动退回「从相册选照片」。**要体验幽灵叠影和姿态提示，必须用真机。**

## 怎么装到自己 iPhone 上

1. Xcode 菜单 → Settings → Accounts → `+` 登录你的 Apple ID（免费账号就够）。
2. 左侧点蓝色的 `Thrive` 工程图标 → 选 TARGETS 里的 `Thrive` → `Signing & Capabilities` 标签页。
3. `Team` 下拉里选你刚加的账号。Bundle Identifier 如果报「已被占用」，把 `com.ryanzou.thrive` 改成别的，比如 `com.你的名字.thrive`。
4. 用数据线连上 iPhone，在设备选择器里选你的手机，按 `⌘R`。
5. 手机上第一次会提示「不受信任的开发者」：设置 → 通用 → VPN与设备管理 → 信任你的账号。

> 免费账号签的 App 7 天后会过期，重新按一次 `⌘R` 就行。

---

## 代码结构

```
Thrive/
├── ThriveApp.swift              App 入口，启动时重排所有浇水提醒
├── Models/                      三张核心表（对应文档 §4）
│   ├── Plant.swift              植物
│   ├── GrowthEntry.swift        生长记录（一张照片 + 姿态数据）
│   └── CareRecord.swift         养护记录（浇水/施肥/换盆共用一张表）
├── Storage/
│   ├── AppContainer.swift       数据落盘位置 + App Group 兜底逻辑
│   ├── PhotoStore.swift         照片读写（数据库只存文件名）
│   └── ModelContainerFactory.swift
├── Services/
│   ├── MotionService.swift      陀螺仪 → 姿态对齐判断
│   ├── CameraService.swift      相机会话
│   └── WateringScheduler.swift  本地通知
└── Views/
    ├── PlantGridView.swift      首页
    ├── PlantDetailView.swift    植物详情 + 时间轴
    └── Capture/CaptureView.swift 拍摄页（对齐三件套）
```

## 两个已知的设计取舍

**1. App Group 目前是关着的。**
文档要求数据放 App Group 共享容器（为将来的 Widget 预留），但 App Group 需要**付费开发者账号**才能签名，免费账号一打开就编译失败。

所以 `AppContainer.swift` 做了自动降级：拿得到共享容器就用共享容器，拿不到就用 App 自己的目录。功能完全一样。

将来你开通了付费账号，只需要在 Xcode 的 `Signing & Capabilities` 里加一个 App Groups capability、填 `group.com.ryanzou.thrive`，**代码一行都不用改** —— 下次启动会自动把已有数据搬进共享容器。

**2. 姿态对齐只看俯仰角和翻滚角，不看偏航角。**
偏航（yaw）参考的是磁北，室内受金属和电器干扰会一直漂，拿它判断会误报。俯仰和翻滚参考的是重力，很稳。三个角度都照常存进数据库，将来做自动对齐时能用上。

---

## 路线图

- **v1.0（当前）**：植物列表 · 生长时间轴 + 拍照对齐 · 浇水记录与提醒
- **v1.1**：统计面板（Swift Charts）· 桌面组件（WidgetKit）← 这一步需要打开 App Group
- **v1.2**：Live Activity · 拍后自动对齐（Vision 图像配准）+ 生长延时视频
