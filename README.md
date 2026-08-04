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

签名已经配好了（Team `3Z47RGMC36`），直接连上 iPhone、在设备选择器里选你的手机、按 `⌘R` 就行。

手机上第一次会提示「不受信任的开发者」：设置 → 通用 → VPN与设备管理 → 信任你的账号。

> **如果真机编译报 "PLA Update available"**：去 [developer.apple.com/account](https://developer.apple.com/account) 登录，
> 首页会弹出新版的 Program License Agreement，勾选同意即可。Apple 每次更新协议都会这样卡住签名，
> 同意完回 Xcode 重新 `⌘R`。（模拟器不受影响，一直能跑。）

---

## 代码结构

```
Thrive/
├── ThriveApp.swift              App 入口
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
│   └── CameraService.swift      相机会话
└── Views/
    ├── PlantGridView.swift      首页
    ├── PlantDetailView.swift    植物详情 + 时间轴
    └── Capture/CaptureView.swift 拍摄页（对齐三件套）
```

## 两个设计取舍

**1. App Group 已启用，但代码保留了降级路径。**
数据和照片都写进共享容器 `group.com.ryanzou.thrive`（见 `Thrive.entitlements`），v1.1 的桌面组件能直接读。

`AppContainer.swift` 仍然保留了兜底逻辑：万一共享容器拿不到（换了签名配置、换了机器），会自动退回 App 自己的目录，不会崩也不会丢功能；等共享容器恢复可用，下次启动自动把数据搬回去。

**2. 姿态对齐只看俯仰角和翻滚角，不看偏航角。**
偏航（yaw）参考的是磁北，室内受金属和电器干扰会一直漂，拿它判断会误报。俯仰和翻滚参考的是重力，很稳。三个角度都照常存进数据库，将来做自动对齐时能用上。

---

## 路线图

- **v1.0（当前）**：植物列表 · 生长时间轴 + 拍照对齐 · 浇水记录
- **v1.1**：统计面板（Swift Charts）· 桌面组件（WidgetKit）← 这一步需要打开 App Group
- **v1.2**：Live Activity · 拍后自动对齐（Vision 图像配准）+ 生长延时视频
