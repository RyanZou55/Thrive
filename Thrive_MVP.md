# Thrive — MVP 需求文档

> 一款记录植物（尤其仙人掌 / 块根 caudex）生长与浇水的 iOS App。
> 亮点：**帮你每次都从同一角度拍照**，让时间轴拉长后能明显看出植物变化。

---

## 1. 产品目标

用最低的记录成本，帮玩家留下「同一角度、可对比」的生长影像，并管好浇水节奏。一个人可开发、可上架的第一版。

技术栈：**Swift + SwiftUI + SwiftData**，iOS 17+，MVVM。数据与照片放在 **App Group 共享容器**（为后续 Widget 预留，从第一天就设好）。

---

## 2. MVP 功能范围（v1.0，只做这些）

### 2.1 植物列表
- 添加植物：名字 + 一张封面照片（必填），其余可选。
- 首页网格展示所有植物，卡片显示封面 + 「距下次浇水还剩 N 天」。

### 2.2 生长记录（核心亮点 · 拍照对齐）
给某株植物拍照 + 一句备注，按时间排成时间轴。拍摄界面提供三件套对齐辅助：

1. **幽灵叠影（Ghost overlay）**：把该植物上一张照片以半透明叠在实时取景上，用户挪动手机让当前植株与虚影重合。
2. **姿态指示（CoreMotion）**：读取手机俯仰角 / 翻滚角，与上次拍摄时保存的角度对比，实时提示「对齐 / 偏了」，对齐时轻震动反馈。
3. **构图网格**：九宫格 + 可选参考框，辅助把花盆放在固定位置。

> 每次拍照都会**静默记录当时的姿态数据（pitch/roll/yaw）**，即使 v1.0 不做自动对齐，这些数据先存下来，未来自动对齐可回溯使用。

### 2.3 浇水记录 + 提醒
- 一键「已浇水」记录时间。
- 为每株设定浇水间隔天数，到期发本地通知。
- 提醒时间由「上次浇水 + 间隔」实时算出，不单独存储。

---

## 3. 页面结构（v1.0 共 3 个主页面）

| 页面 | 内容 |
|------|------|
| 首页 / 植物网格 | 所有植物卡片 · 待浇水提示 · 「＋」添加 |
| 植物详情 | 封面 · 浇水按钮 · 生长时间轴 |
| 拍摄 / 添加记录 | 相机 + 叠影 + 姿态条 + 网格 → 备注 → 保存 |

---

## 4. 数据库 Schema（设计目标：定下来尽量不改 / 强可扩展）

### 4.1 可扩展性原则（先立规矩）
- **主键一律 UUID**，永不复用、永不改。
- **每张表都有 `createdAt` / `updatedAt`**，便于同步与排序。
- **枚举一律存字符串**（如 `"water"`），加新类型不破坏旧数据。
- **新字段一律可选（Optional）**，只做加法，不改旧字段含义。
- **照片只存文件名引用**，图片本体放共享容器的文件系统，不进数据库。
- 预留 `schemaVersion`，用 SwiftData 轻量迁移。
- **传感器/元数据即使暂时不用也先存**（姿态、尺寸），保证未来功能可回溯。

### 4.2 三张核心表

**Plant（植物）**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| name | String | 名字 |
| coverPhotoFilename | String? | 封面图文件名 |
| species | String? | 品种（可选，预留） |
| caudexType | String? | 类型枚举：cactus / caudex / succulent / other |
| acquiredDate | Date? | 入手日期 |
| wateringIntervalDays | Int | 浇水间隔天数 |
| lastWateredAt | Date? | 上次浇水时间 |
| sortOrder | Int | 排序 |
| notes | String? | 备注（预留） |
| createdAt / updatedAt | Date | 时间戳 |

**GrowthEntry（生长记录 / 一张照片）**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| plantID | UUID | 所属植物（关系） |
| capturedAt | Date | 拍摄时间 |
| photoFilename | String | 照片文件名 |
| note | String? | 备注 |
| refEntryID | UUID? | 本次对齐参考的上一张（叠影用） |
| poseePitch | Double? | 拍摄俯仰角 ← 为自动对齐预存 |
| poseRoll | Double? | 拍摄翻滚角 |
| poseYaw | Double? | 拍摄偏航角 |
| heightCm | Double? | 株高（可选测量，预留） |
| caudexWidthMm | Double? | 块根宽度（可选，预留） |
| createdAt / updatedAt | Date | 时间戳 |

**CareRecord（养护记录 · 泛化设计）**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| plantID | UUID | 所属植物（关系） |
| performedAt | Date | 执行时间 |
| type | String | 枚举：water（现有）/ 未来 fertilize / repot |
| amountMl | Double? | 用量（可选） |
| note | String? | 备注 |
| createdAt | Date | 时间戳 |

> 浇水用 `type = "water"` 的 CareRecord 记录；将来施肥、换盆只是加新的 `type`，**不新建表、不改结构**——这是保证 schema 稳定的关键。

### 4.3 关系
- Plant `1 ──< 多` GrowthEntry
- Plant `1 ──< 多` CareRecord
- 「下次浇水时间」为计算值，不入库：`nextDue = lastWateredAt + wateringIntervalDays`

---

## 5. 后续版本路线（现在只记录，不做）

**v1.1**
- 统计面板：浇水频率 / 连续打卡 streak / 生长张数（用系统 Swift Charts，数据从现有表聚合，无需新表）。
- 桌面组件（WidgetKit）：显示下一盆待浇水 + 倒计时，支持组件上直接打卡（App Intent）。

**v1.2**
- Live Activity：到期日锁屏 / 灵动岛倒计时。
- **拍后自动对齐（原「功能 4」）**：用 Vision 图像配准（`VNHomographicImageRegistrationRequest`）＋已存的姿态数据，把新照片自动对齐到基准图；一键生成生长延时短视频用于分享。

---

*文档版本 v1.0 · 数据 schema 已按「加法扩展」原则冻结*
