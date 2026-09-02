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
├── Localizable.xcstrings        界面文案（中英）
├── InfoPlist.xcstrings          权限说明（中英）
├── Models/                      三张核心表（对应文档 §4）
│   ├── Plant.swift              植物
│   ├── GrowthEntry.swift        生长记录（一张照片 + 姿态数据）
│   ├── CareRecord.swift         养护记录（浇水/施肥/换盆共用一张表）
│   └── TimelineItem.swift       把两类记录合成一条时间轴
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
    ├── GrowthEntryDetailView.swift
    ├── CareRecordDetailView.swift
    ├── Capture/CaptureView.swift 拍摄页（对齐三件套）
    └── Components/              看图缩放、存相册、备注框等
```

## 三个设计取舍

**1. App Group 已启用，但代码保留了降级路径。**
数据和照片都写进共享容器 `group.com.ryanzou.thrive`（见 `Thrive.entitlements`），v1.1 的桌面组件能直接读。

`AppContainer.swift` 仍然保留了兜底逻辑：万一共享容器拿不到（换了签名配置、换了机器），会自动退回 App 自己的目录，不会崩也不会丢功能；等共享容器恢复可用，下次启动自动把数据搬回去。

**2. 界面文案走 String Catalog，跟随系统语言。**
`Localizable.xcstrings` 是简体中文为源语言、英文为译文。注意模型层和服务层返回的
普通 String（植物状态、姿态提示等）不在 SwiftUI 的 `Text` 字面量里，不会被自动
本地化，必须手动包 `String(localized:)`，否则英文环境下会漏出中文。

**3. 跨天的姿态对齐只看俯仰角和翻滚角，不看偏航角。**
偏航（yaw）用的是 `.xArbitraryZVertical` 参考系，零点是每次启动时的朝向 —— 两次拍摄之间没有可比性，拿它做跨天对比会误报。俯仰和翻滚参考的是重力，很稳。

但**单次拍摄会话之内 yaw 是可靠的**：它只是陀螺仪积分，漂移量级是每分钟一两度，而绕一圈只要二十几秒。转盘就是靠它定位每一帧的。

---

## 路线图

- **v1.0**：植物列表 · 时间轴（生长照 + 浇水）· 拍照对齐 · 看图与存图 · 中英双语
- **v1.1**：封面全屏与裁切 · 浇水复用拍摄页 · 入手日期可改
- **v1.2**：转盘拍摄 —— 绕植物走一圈，按 yaw 抽 24 帧，抠掉背景，详情页拖着转
- **v1.3**：封面可指定 · 转盘按主体基线／高度／盆底中心逐帧对齐 · 转不成也留一张 · 录制中的速度与端稳提示
- **v1.3.2（当前）**：成片按取景框比例裁切，所见即所得 · 确认页能拖着转，并指定哪一帧当这条记录的主照片
- **往后**：统计面板（Swift Charts）· 桌面组件（WidgetKit）· 两个时间点的转盘并排同步旋转 · 用 ARKit 的真实方位角取代 yaw
