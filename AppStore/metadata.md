# App Store 上架资料

App Store Connect 里按语言分两份填。字数都按苹果的上限核过，方括号里是上限。

---

## 通用设置（不分语言）

| 字段 | 值 |
|------|-----|
| Bundle ID | `com.ryanzou.thrive` |
| SKU | `thrive-ios-001` |
| 主要语言 | 简体中文 |
| 本地化 | 简体中文、英文（App 已做双语，跟随系统语言） |
| 主要类别 | 生活 |
| 次要类别 | 效率 |
| 年龄分级 | 4+ |
| 价格 | 免费 |

---

# 简体中文

## 名称 [30]

```
Thrive 植物生长记录
```

## 副标题 [30]

```
同一角度拍照，看见它长大
```

## 关键词 [100 字符，逗号分隔不留空格]

```
多肉,仙人掌,块根,块根植物,生长记录,植物养护,浇水记录,园艺,延时摄影,打卡,植物日记,转盘,360度,多角度
```

## 促销文本 [170]

```
每次都从同一角度拍照，几个月后翻时间轴，你会清楚看见它长大了多少。
```

## 描述 [4000]

```
Thrive 帮你记录植物的生长——尤其是仙人掌和块根这类长得慢、变化不容易察觉的品种。

大多数人拍植物的问题不是拍得少，而是每次角度都不一样。半年后翻相册，只看到一堆没法对比的照片。

Thrive 解决的就是这件事。

【拍照对齐三件套】

· 幽灵叠影
把上一张照片以半透明叠在实时取景上。挪动手机，让眼前的植株和虚影重合，按下快门——两张照片的构图就是一致的。

· 姿态提示
读取手机的俯仰角和翻滚角，跟你上次拍摄时保存的角度实时比对。偏了会告诉你往哪个方向调，对准了轻震一下，你的眼睛可以一直盯着取景框。

· 构图网格
九宫格加可选参考框，帮你把花盆每次落在同一个位置。

【一条时间轴】

生长照和浇水记录按时间排在一起，每条都能配一句备注，并标出距入手第几天。照片点开可以双指放大细看，也能存回你自己的相册。备注写完之后还能改。

【浇水记录】

浇完点一下，卡片上就写着「3 天前浇水」。顺手拍一张也行，不拍也行。不设周期、不发提醒——仙人掌和块根什么时候该浇，看盆看天看植株，那是你的判断，不是闹钟的。

【关于隐私】

Thrive 没有账号，没有服务器，不收集任何数据。你的照片和记录只存在你自己的手机上。
```

## 新版本说明（1.0）

```
Thrive 的第一个版本。
· 拍照对齐：幽灵叠影、姿态提示、构图网格
· 生长照与浇水记录合成一条时间轴
· 照片可放大查看、存回相册
· 中英双语，跟随系统语言
```

## 网址

| 字段 | 值 |
|------|-----|
| 支持网址（必填） | `https://ryanzou55.github.io/Thrive/` |
| 隐私政策网址（必填） | `https://ryanzou55.github.io/Thrive/privacy-policy/` |
| 营销网址（选填） | 留空 |

---

# English

## Name [30]

```
Thrive: Plant Growth Log
```

## Subtitle [30]

```
Same angle, every single time
```

## Keywords [100 chars, comma separated, no spaces]

```
succulent,cactus,caudex,plant,growth,tracker,journal,watering,garden,timelapse,houseplant,360,spin
```

## Promotional Text [170]

```
Shoot from the same angle every time. Months later, scroll the timeline and you'll actually see how much it grew.
```

## Description [4000]

```
Thrive tracks how your plants grow — especially cacti and caudex plants, the ones that change so slowly you can't tell by looking.

The problem isn't that people don't photograph their plants. It's that every shot is from a different angle. Six months later your camera roll is a pile of photos you can't compare.

That's what Thrive fixes.

THREE WAYS TO LINE UP THE SHOT

· Ghost overlay
Your last photo sits semi-transparent over the live viewfinder. Move the phone until the plant lines up with the ghost, then shoot — the two frames match.

· Angle guide
Thrive reads your phone's pitch and roll and compares them to the angle saved with your last photo. It tells you which way to tilt, and gives a light haptic tap when you're lined up, so your eyes never leave the viewfinder.

· Composition grid
A rule-of-thirds grid plus an optional reference box, so the pot lands in the same spot every time.

ONE TIMELINE

Growth photos and waterings sit together in one chronological list. Every entry can carry a note, and each one is tagged with how many days it's been since you got the plant. Tap any photo to pinch-zoom into the detail, or save it back to your own photo library. Notes stay editable afterwards.

WATERING, LOGGED SIMPLY

Tap once when you water. The card then reads "3 days ago." Snap a photo while you're at it, or don't. No schedules, no reminders — when a cactus needs water depends on the pot, the weather and the plant. That's your call, not an alarm's.

PRIVACY

No account, no server, no analytics. Your photos and records never leave your phone.
```

## What's New (1.0)

```
The first release of Thrive.
· Shot alignment: ghost overlay, angle guide, composition grid
· Growth photos and waterings in one timeline
· Pinch-zoom any photo, save it back to your library
· English and Simplified Chinese, following your system language
```

## URLs

| Field | Value |
|-------|-------|
| Support URL (required) | `https://ryanzou55.github.io/Thrive/en/` |
| Privacy Policy URL (required) | `https://ryanzou55.github.io/Thrive/privacy-policy-en/` |
| Marketing URL (optional) | leave blank |

---

## 开启 GitHub Pages

上面四个网址都靠它托管。仓库页面 → Settings → Pages → Source 选
`Deploy from a branch` → 分支选 `main`、目录选 `/docs` → Save。
等一两分钟，四个地址就能打开了。

## App 隐私问卷

在 App Store Connect 的「App 隐私」里，全选 **不收集数据（Data Not Collected）**。

Thrive 确实不收集任何数据：没有网络请求，没有第三方 SDK，照片和记录全部只写本机。

## 出口合规

Info.plist 里已经写好 `ITSAppUsesNonExemptEncryption = false`，
提交时不会再问加密相关的问题。

## 版本更新说明（此版本的新功能）

发更新时 ASC 会要求填「此版本的新功能 / What's New in This Version」，中英各一份。
每发一版在这里往上叠一段，最新的放最前面。

### 1.3

简体中文：

```
详情页顶上的大图现在是封面，在任意一张生长照里都能把它设成封面。
转盘拍摄稳了很多：手举得高一点低一点、离得近一点远一点，成片会自动对齐，不再上下晃、忽大忽小。
没绕够一圈也不算白拍，会留下一张普通的生长照。
录制时会提醒你走太快，或者手机端得不稳。
补上了转盘相关的英文界面，删除入手日期前也会先问一句。
```

English：

```
The big photo on a plant's page is now its cover, and any growth photo can be set as the cover.
Spin capture is far steadier: differences in how high you held the phone and how close you walked are corrected automatically, so the plant no longer bobs or changes size as it turns.
A lap that doesn't make it all the way around now leaves you an ordinary growth photo instead of nothing.
While recording, Thrive tells you when you're walking too fast or letting the phone tilt.
Spin-related text now follows your system language, and clearing a date acquired asks first.
```

### 1.2

简体中文：

```
现在可以举着手机绕植物走一圈，Thrive 会按你转过的角度挑出等间隔的 24 帧。
在生长记录里左右一拖，植株就转起来了。
背景会自动抠掉，转起来只有植物本身，所以在哪儿拍都无所谓。
不用非得转满一圈，转过三分之一以上就能存下来。
```

English：

```
You can now walk a circle around your plant while it records, and Thrive picks 24 evenly spaced frames based on how far you turned.
Drag left or right on a growth photo and the plant turns.
The background is removed automatically, so only the plant moves — it doesn't matter where you shoot.
A full circle isn't required; a third of the way around is enough to save.
```

### 1.1.1

简体中文：

```
入手日期现在在植物详情页里也能改：点一下日期就能调整，也可以清除，或者给以前没记过的植株补记。
```

English：

```
You can now change a plant's date acquired right from its detail page — adjust it, clear it, or fill one in for a plant that never had one.
```

### 1.1（已上架）

简体中文：

```
封面照片现在可以点开全屏看，也能选择填满裁剪或完整显示。
浇水拍照改用和拍生长照相同的取景界面，同样有幽灵叠影，能对着上一张把植株摆回原位。
添加植物时封面可以直接拍照，入手日期的选择也更直接了。
```

English：

```
Cover photos now open full screen, and you can choose between fill and fit.
Watering photos use the same viewfinder as growth photos, ghost overlay included, so you can line the plant up against the previous shot.
You can now shoot a cover photo straight from the camera when adding a plant, and picking a date acquired takes one tap less.
```

---

## 截图

`AppStore/screenshots/` 下按**尺寸**再按语言分好了，目录名就是 ASC 里对应的槽位：

```
6.9英寸-1320x2868/zh-Hans/    ← ASC 的「6.9 英寸显示屏」槽位
6.9英寸-1320x2868/en/
6.5英寸-1284x2778/zh-Hans/    ← ASC 的「6.5 英寸显示屏」槽位
6.5英寸-1284x2778/en/
```

每套三张，内容一致：

1. `01_首页-植物网格` — 植物网格与「几天前浇水」
2. `02_详情-时间轴` — 生长照与浇水混排的时间轴
3. `03_生长记录-拍摄角度` — 单条记录、可编辑备注、保存下来的拍摄角度

**传错槽位会报 "The dimensions of one or more screenshots are wrong"。**
报错里列的尺寸就是它期望的，对照目录名找对应那套。两个尺寸都是原生截的，
没有缩放（6.9 用 iPhone 17 Pro Max，6.5 用 iPhone 14 Plus）。

**还缺两张，都必须真机拍：**

1. **拍摄页的幽灵叠影** —— 模拟器里那张取景画面是静态图替身，
   当成真实功能截图放商店不合适。给同一株植物拍第二张时截屏即可。
2. **转盘（1.2 新增）** —— 两张更好：取景页转盘模式（进度环 + 参考框 + 提示条），
   和详情页转到中间某一帧的样子。模拟器没有相机也没有陀螺仪，这两张根本截不出来。

截图快捷键是电源键 + 音量上键，中英文各一份（切系统语言重截）。

> 1.2 的商店描述**没有**提转盘，只有「此版本的新功能」里写了。
> 所以转盘截图不是上架硬门槛 —— 但商店页面一张都不放的话，
> 用户翻截图时看不出这版多了什么。
