# 设计文档：鼠标按键与滚轮事件映射到 mpv input.conf

- 日期：2026-08-25
- 状态：**定稿**（已确认，可实施）
- 方案：A —— 查表派发（`PlayerCore.keyBindings` → `handleKeyBinding()`，与键盘同路径）

## 1. 目标与需求

将物理鼠标的左/中/右键、侧键及上/下/左/右滚轮事件的处理统一交由 mpv
`input.conf` 决定：**未绑定即无操作，不回退到任何 IINA 内置动作**。
删除设置界面中的鼠标设置及相关代码，仅保留触控板设置。

### 1.1 已确认决策

| 决策点 | 结论 |
|---|---|
| 绑定来源与执行 | 查表派发：事件映射为 `MBTN_* / WHEEL_*` 键名，归一化后查 `PlayerCore.keyBindings`（与传给 mpv `--input-conf` 的同一份文件），经现有 `handleKeyBinding()` 执行；支持 `@iina` 扩展命令、screenshot OSD、干净退出 |
| 无绑定行为 | 直接返回，无任何兜底 |
| 单双击判定 | 保留现有定时器消歧结构（`singleClickTimer` + `NSEvent.doubleClickInterval`），仅替换动作载荷为键名 |
| 滚轮事件范围 | 全部 scrollWheel 事件走 `WHEEL_*` 绑定；物理滚轮每格一次，触控板按累计位移折算刻度 |
| OSC 滑块悬停滚动 | 保留 `seekOverride/volumeOverride` 内部逻辑（进度条 seek、音量条调音量不变）；相关灵敏度偏好保留在代码中但不再提供 UI |
| 偏好清理深度 | 深度清理：删除废弃键定义、枚举与孤儿代码（含 `playbackSpeedScrollAmount`：速度滚动路径移除后已无任何功能使用） |
| 旧 Preferences 窗口 | Mouse 区块一并移除 |
| useExactSeek UI | 随鼠标区块删除（偏好键保留，`PlayerCore.seek` 仍在用） |
| zh-Hans 范围 | 全量补全 `zh-Hans.lproj`：补译全部缺失键 + 清理废弃/死键 + 去重；同步删除 `Base`/`en` 中同批废弃键 |

## 2. 架构

```
Cocoa 鼠标/滚轮事件
  └─ PlayerWindowController.mouseUp / rightMouseUp / otherMouseUp / scrollWheel
       └─ PluginInputManager.handle(...)            // 插件管道，保持不变
            └─ defaultHandler（本次重写）
                 └─ 事件 → mpv 键名（KeyCodeHelper.normalizeMpv 归一化）
                      └─ PlayerCore.keyBindings[key]
                           ├─ 命中 → handleKeyBinding(kb)
                           └─ 未命中 → 无操作（无回退）
```

- 内置 `iina/config/input.conf` 已按需求更新默认绑定：
  `MBTN_LEFT cycle pause`、`MBTN_LEFT_DBL cycle fullscreen`、`MBTN_MID cycle ontop`、
  `MBTN_RIGHT cycle fullscreen`、`MBTN_BACK/FORWARD playlist-prev/next`、
  `WHEEL_UP/DOWN seek 120/-5`、`WHEEL_LEFT/RIGHT seek 20/-20`；
  键盘 `RIGHT seek 120`、`LEFT seek -5`、`UP playlist-next`、`DOWN playlist-prev`、
  `SPACE cycle pause`。
- 键盘链路（`keyDown`）不受影响。
- `performMouseAction` 基类实现与 MainWindow 重载保留——仅 Force Touch（`pressureChange`）使用。

### 2.1 键名映射表

| 触发事件 | mpv 键名 |
|---|---|
| 左键单击（clickCount = 1） | `MBTN_LEFT` |
| 左键双击（clickCount = 2） | `MBTN_LEFT_DBL` |
| 右键 | `MBTN_RIGHT` |
| 中键（buttonNumber = 2） | `MBTN_MID` |
| 后退侧键（buttonNumber = 3） | `MBTN_BACK` |
| 前进侧键（buttonNumber = 4） | `MBTN_FORWARD` |

> 注：按 AppKit/macOS 通用约定 buttonNumber 3 = 后退、4 = 前进，
> 实施后以真机测试为准，如相反则在映射处对调。

## 3. 行为层改动 — `iina/PlayerWindowController.swift`

1. 新增私有助手（仿 `keyDown` 模式，参考 PlayerWindowController.swift:361）：

   ```swift
   private func dispatchMouseBinding(_ mpvKey: String) -> Bool {
     let normalized = KeyCodeHelper.normalizeMpv(mpvKey)
     guard let kb = PlayerCore.keyBindings[normalized] else { return false } // 未绑定=无操作
     return handleKeyBinding(kb)
   }
   ```

2. `mouseUp` 默认处理器：保留单击/双击定时器消歧结构；
   单击时先查 `MBTN_LEFT_DBL` 是否有绑定：**无绑定则立即派发 `MBTN_LEFT`，不启动定时器**；
   有绑定才启动定时器（userInfo 存 `"MBTN_LEFT"`），超时后经
   `performMouseActionLater` 派发；
   双击 → 取消定时器并派发 `MBTN_LEFT_DBL`。
   删除 hideOSC 特有的 `mouseExitEnterCount >= 2` 取消逻辑；
   `mouseExitEnterCount` 失去全部读者后连同变量与 MainWindow 两处自增一并删除。
3. `rightMouseUp` → `MBTN_RIGHT`。
4. `otherMouseUp`：按 §2.1 按 `event.buttonNumber` 映射派发；其余调用 super。
5. `scrollWheel` else 分支（非 OSC 滑块覆盖时）改为派发 `WHEEL_UP/DOWN/LEFT/RIGHT`，
   由两个新增私有助手实现：

   ```swift
   private func dispatchWheelBinding(direction: ScrollDirection, positive: Bool) {
     switch direction {
     case .horizontal:
       dispatchMouseBinding(positive ? "WHEEL_RIGHT" : "WHEEL_LEFT")
     case .vertical:
       dispatchMouseBinding(positive ? "WHEEL_UP" : "WHEEL_DOWN")
     }
   }

   /// 归一化滚动增量：正值 = 向上/向右
   private func normalizedScrollDelta(_ event: NSEvent, direction: ScrollDirection) -> Double {
     let isPrecise = event.hasPreciseScrollingDeltas
     let isNatural = event.isDirectionInvertedFromDevice

     var deltaX = isPrecise ? Double(event.scrollingDeltaX) : event.scrollingDeltaX.unifiedDouble
     var deltaY = isPrecise ? Double(event.scrollingDeltaY) : event.scrollingDeltaY.unifiedDouble * 2

     if isNatural {
       deltaY = -deltaY
     } else {
       deltaX = -deltaX
     }
     return direction == .horizontal ? deltaX : deltaY
   }
   ```

   - 归一化规则细节（务必照抄）：非 precise 的垂直增量 ×2（与现有
     `seekAmountMapMouse` 量级匹配）；自然滚动（`isDirectionInvertedFromDevice`）
     时翻转 `deltaY` 符号，否则翻转 `deltaX` 符号；
   - 方向判定：`phase` 为空（鼠标）或含 `.began`（触控板起手）时按
     `scrollingDeltaX/Y` 非零确定 `scrollDirection`；
   - 非 precise delta（物理滚轮）：每事件派发一次，并清空该方向的累计残量
     （`wheelDeltaAccumulation[scrollDirection] = nil`）；
   - precise delta（触控板）：按方向累计 |delta|，每达到阈值常量
     `private static let wheelTickThreshold: Double = 40` 派发一次并扣减
     （`while` 循环，一次事件可派发多格），避免一次手势触发几十次 seek；
   - 手势结束（`isTrackpadEnd`）时 `scrollDirection = nil` 且清空全部累计残量
     （`wheelDeltaAccumulation.removeAll()`），避免未满阈值的残量带入下一次
     手势使其提前触发一格；
   - `seekOverride/volumeOverride` 分支（OSC 进度条/音量条滚动）原样保留；
   - 删除 Music Mode 音量弹窗联动调用（仅服务旧偏好路径）。
6. 清理缓存属性与 KVO：`singleClickAction`、`doubleClickAction`、
   `horizontalScrollAction`、`verticalScrollAction`、`playbackSpeedScrollAmount`
   及对应 `observedPrefKeys` 条目和 `observeValue` case。
7. 保留：`performMouseAction` 及其 MainWindow 重载（Force Touch 用）、
   `relativeSeekAmount/volumeScrollAmount/useExactSeek`
   偏好（OSC 滑块滚动仍在用）、`AppData` 的 `seekAmountMap/seekAmountMapMouse/volumeMap`
   映射表（`playbackSpeedMap` 随 `playbackSpeedScrollAmount` 一并删除）、
   `singleClickTimer` 与 `performMouseActionLater`（载荷改为键名）。

## 4. 其他行为层改动

### `iina/MainWindowController.swift`
- 删除 `verticalScrollAction/horizontalScrollAction` KVO case（:306-313）。
- 删除 `mouseExitEnterCount` 两处自增（变量在基类中一并删除）。
- `scrollWheel` 其余守卫（interactiveMode、momentum 准入、sidebar/titleBar、
  OSC 悬停覆盖）保持不变。

### `iina/MiniPlayerWindowController.swift`
- 删除 `handleVolumePopover` 方法及 Music Mode 音量气泡联动（仅服务旧偏好路径）；
  音量按钮/静音按钮点击交互不动。

### `iina/VideoView.swift`
- 删除 `acceptsFirstMouse` 重写（恢复 AppKit 默认焦点行为）。

## 5. 偏好定义 — `iina/Preference.swift`

- 删除 Key 定义与 defaults 字典条目：`singleClickAction`、`doubleClickAction`、
  `rightClickAction`、`middleClickAction`、`verticalScrollAction`、`horizontalScrollAction`、
  `videoViewAcceptsFirstMouse`、`playbackSpeedScrollAmount`（速度滚动路径已随
  `ScrollAction.playbackSpeed` 移除，无任何功能再读取该偏好）。
- 导出用大 switch 同步移除：Bool 列表中的 `.videoViewAcceptsFirstMouse`（:1495）、
  MouseClickAction case 仅留 `.forceTouchAction`（:1542-1546）、
  整个 `.horizontalScrollAction, .verticalScrollAction` case（:1570-1572）。
- 删除 `enum ScrollAction`（:509-530，含注释掉的 `passToMpv`）。
- 保留：`enum MouseClickAction`（Force Touch 用）、`PinchAction`、
  `useExactSeek`、`relativeSeekAmount/volumeScrollAmount` 两个灵敏度偏好的
  Key 定义与 defaults 条目（OSC 滑块滚动仍在用）。

## 6. 设置界面

### 新窗口 — `iina/SettingsPageControl.swift`
- `content()` 仅返回 `sectionTrackpad()`；删除 `sectionMouse()`、`SliderView` 辅助类、
  `sensSeek/sensVolume/sensSpeed` 属性。
- `iina/SettingsLocalization.swift`：移除 `text_Mouse`（:138）。

### 旧窗口 — `Base.lproj/PrefControlViewController.xib` + `iina/PrefControlViewController.swift`
- xib：删除 Mouse 区块视图 `Wmg-PT-BGO` 全部子控件（纵横滚动弹出菜单、精确查找、
  灵敏度滑条×3、单/双/右/中键菜单、Accepts-first-mouse 复选框）及其 outlet 连接、
  UserDefaults binding、约束，确保无悬空引用。
- swift：删除 `sectionMouseView` outlet 与 `sectionViews` 条目；删除
  `scrollVerticallyLabel` outlet 及 `viewDidLoad` 中依赖它的宽度约束（:33-40）。
- Trackpad 区块（pinch/forceTouch）保留。

## 7. 翻译（zh-Hans 全量补全 + 英文侧废弃键清理）

### `zh-Hans.lproj/Localizable.strings` — 补译全部缺失键
补齐 EN 有而 ZH 缺失的全部在用键（约 73 个），按分节插入并保持键序：
- General：`screenshotSaveToFile.desc`；
- Video：`enableHdrSupport.label`、`enableLiveText.*`、`hardwareDecoder.items.0/1/2.desc`；
- Audio：`audioDriverEnableAVFoundation.items.0.desc`、`gaplessAudio.items.0/1/2.desc`；
- Network：`cachePauseInitial.*`、`cachePauseWait.*`、`defaultCacheSize.*`；
- Subtitles：`subBold.desc`、`subOverrideLevel.items.0~4`（mpv 字面值不译）及各 `.desc`；
- UI：`controlBarAutoHideTimeout.label`、`more_ui_settings`、`thumbnailWidth.*`；
- Advanced：`logLevel.desc`；
- Inline labels（`$` 键）：`$AdditionalMpvOptions.desc`、`$BrowserExtensions`、
  `$CheckForUpdates.items.*`（每小时/每天/每周/每月）、`$Chrome`、`$ColorHDR`、
  `$CommunityPlugins`、`$CreateAnEmptySet`、`$Decoding`、`$DuplicateCurrentSet`、
  `$Firefox`、`$GetPlugins`、`$Hardware`、`$InputGithubURL`、`$Installed`、
  `$Installing`、`$KeyBindingSet`、`$LegacyOpenSubAlert`、`$LiveText`（实况文本）、
  `$Logging`、`$MPVSettings`、`$NewKeyBindingSet`、`$NoSelection`、`$OfficialPlugins`、
  `$OpenLogWindow`、`$OrSelectFrom`、`$Other`、`$Percent`、`$SPDIFOutputWarning`、
  `$Safari`、`$SubtitleSource(.desc)`、`$SubtitleSourcePluginDesc`、`$ThisPluginIsNot`、
  `$Volume`、`$YTDL`、`$onlineMediaPluginAdvice`、`$ytdlWarning`。

### `zh-Hans.lproj/Localizable.strings` — 废弃/死键清理
- 删除本次功能移除的键：`settings.singleClickAction.*`、`settings.doubleClickAction.*`、
  `settings.rightClickAction.*`（含错挂的 desc）、`settings.middleClickAction.*`、
  `settings.verticalScrollAction.*`、`settings.horizontalScrollAction.*`、
  `settings.videoViewAcceptsFirstMouse.*`、`settings.$Mouse`、
  `settings.playbackSpeedScrollAmount.label`。
- 删除上游演进遗留的死键/陈旧键：`settings.cacheBufferSize.*`（已被
  `defaultCacheSize` 取代）、`settings.subAlignX.label`（新界面对齐控件改用
  `$X/$Y` 标签，且原译文有误）、`settings.$Audio`、`settings.$Video`（无代码引用）。
- 修复遗留未翻译条目：`settings.autoSearchOnlineSub.desc`（原为英文）。
- 保留：`settings.pinchAction.*`、`settings.forceTouchAction.*`、`settings.$Trackpad`、
  `settings.useExactSeek.*` 与 `relativeSeekAmount/volumeScrollAmount` 灵敏度标签
  （对应功能仍在代码中使用，可能回归 UI）；`screenShotFormat.items.1/2`、
  `toneMappingAlgorithm.items.0` 为对 `VerbatimStrings.strings` 兜底值的本地化覆盖，保留。

### `PrefControlViewController.strings` — 去重 + 清理
- 修复真实重复条目：`XXq-G1-9sl.title`（L79/L85）、`nJZ-9M-DHk.title`（L130/L160）各两次。
- 清理 xib 已删控件对应 ObjectID 条目，仅保留触控板区块相关翻译。

### `Base.lproj` / `en.lproj` `Localizable.strings` — 同步删除废弃键
两文件内容完全一致，均删除上述同批废弃键（鼠标动作/滚动动作/
`videoViewAcceptsFirstMouse`/`$Mouse`/`playbackSpeedScrollAmount.label`），
避免英文源残留死键。

### 审计结论
补全后 `settings.*` 域 EN→ZH 缺失为 0；三个文件均无重复键。
其余 39 种语言仍残留废弃条目（无害，交由 Crowdin 同步清理）。

### 译文对照表（恢复时照抄，键值均已核实入库）

| 键 | 译文 |
|---|---|
| `settings.screenshotSaveToFile.desc` | `/path/to/screenshot/folder` |
| `settings.enableHdrSupport.label` | 启用 HDR 模式 |
| `settings.enableLiveText.label` | 实况文本 |
| `settings.enableLiveText.desc` | 在暂停的视频画面上显示实况文本叠层，用于识别文字。需要 macOS 13 或更高版本。 |
| `settings.hardwareDecoder.items.0.desc` | 禁用硬件解码。 |
| `settings.hardwareDecoder.items.1.desc` | 启用硬件解码。但大多数视频滤镜将无法正常工作。 |
| `settings.hardwareDecoder.items.2.desc` | 启用硬件解码。会消耗双倍内存，但可与视频滤镜配合使用。 |
| `settings.audioDriverEnableAVFoundation.items.0.desc` | 默认音频驱动。 |
| `settings.gaplessAudio.items.0.desc` | 连续播放音频文件时，可能在文件切换处出现静音或中断。 |
| `settings.gaplessAudio.items.1.desc` | 当解码器输出的音频格式改变时，音频设备会被关闭并重新打开，中断无缝播放。 |
| `settings.gaplessAudio.items.2.desc` | 音频设备将使用为第一个文件选定的参数打开，并保持开启以实现无缝播放。后续文件可能会被重采样。 |
| `settings.cachePauseInitial.label` | 播放前缓冲 |
| `settings.cachePauseInitial.desc` | 在开始播放前先进入缓冲模式。可用于确保播放流畅启动，代价是需要等待一段时间预取并缓冲网络数据。 |
| `settings.cachePauseWait.label` | 恢复播放前的缓冲秒数 |
| `settings.cachePauseWait.desc` | 进入缓冲模式后，重新开始播放前需要缓冲的秒数。如果播放频繁再次进入缓冲模式，请增大此设置。\n\n默认值：1 |
| `settings.defaultCacheSize.label` | 缓存区大小（KiB） |
| `settings.defaultCacheSize.desc` | 默认值：153,600 |
| `settings.autoSearchOnlineSub.desc` | 启用后，IINA 将仅为未加载字幕且时长超过 20 分钟的视频自动搜索在线字幕。（修复原英文条目） |
| `settings.subBold.desc` | `sans-serif` |
| `settings.subOverrideLevel.items.0~4` | `yes` / `force` / `strip` / `scale` / `no`（mpv 字面值，不译） |
| `settings.subOverrideLevel.items.0.desc` | 应用本节中的所有样式设置。 |
| `settings.subOverrideLevel.items.1.desc` | 应用所有字幕样式。 |
| `settings.subOverrideLevel.items.2.desc` | 彻底移除字幕中的所有 ASS 标签与样式。 |
| `settings.subOverrideLevel.items.3.desc` | 在本节的样式设置之外，额外应用缩放设置。 |
| `settings.subOverrideLevel.items.4.desc` | 按字幕脚本的设定渲染字幕，不做任何覆盖。 |
| `settings.controlBarAutoHideTimeout.label` | 在此时间后自动隐藏 |
| `settings.more_ui_settings` | 更多用户界面设置可在布局边栏中找到。 |
| `settings.thumbnailWidth.label` | 缩略图宽度 |
| `settings.thumbnailWidth.desc` | 修改宽度将清除当前缩略图缓存，并以所选尺寸重新生成全部缩略图。 |
| `settings.logLevel.desc` | 可通过菜单中的「窗口 - 日志查看器」查看日志。 |
| `settings.$AdditionalMpvOptions.desc` | 粘贴 key=value 格式的选项可自动填充两个字段。 |
| `settings.$BrowserExtensions` | 浏览器扩展 |
| `settings.$CheckForUpdates.items.3600` | 每小时 |
| `settings.$CheckForUpdates.items.86400` | 每天 |
| `settings.$CheckForUpdates.items.604800` | 每周 |
| `settings.$CheckForUpdates.items.2629800` | 每月 |
| `settings.$Chrome` | Chrome |
| `settings.$ColorHDR` | 颜色与 HDR |
| `settings.$CommunityPlugins` | 社区插件 |
| `settings.$CreateAnEmptySet` | 创建空白配置… |
| `settings.$Decoding` | 解码 |
| `settings.$DuplicateCurrentSet` | 复制当前配置… |
| `settings.$Firefox` | Firefox |
| `settings.$GetPlugins` | 获取插件… |
| `settings.$Hardware` | 硬件 |
| `settings.$InputGithubURL` | 输入 GitHub 链接 |
| `settings.$Installed` | 已安装 |
| `settings.$Installing` | 正在安装 |
| `settings.$KeyBindingSet` | 按键绑定配置 |
| `settings.$LegacyOpenSubAlert` | ⚠️ 旧的 OpenSubtitles 支持已弃用，请改用 OpenSubtitles 插件。如需登录，请前往旧版设置窗口。 |
| `settings.$LiveText` | 实况文本 |
| `settings.$Logging` | 日志 |
| `settings.$MPVSettings` | mpv 设置 |
| `settings.$NewKeyBindingSet` | 新建按键绑定配置 |
| `settings.$NoSelection` | 未选择 |
| `settings.$OfficialPlugins` | 官方插件 |
| `settings.$OpenLogWindow` | 打开日志查看器 |
| `settings.$OrSelectFrom` | 或从可用插件中选择 |
| `settings.$Other` | 其他 |
| `settings.$Percent` | % |
| `settings.$SPDIFOutputWarning` | 应使用压缩音频直通输出的编解码器列表。\n\n警告：通常没有理由使用此设置。HDMI 支持未压缩的多声道 PCM，无损 DTS-HD 也可通过 FFmpeg 的 DCA 解码器解码。如果输出设备不支持 S/PDIF 而启用了此设置，可能无法开始播放。 |
| `settings.$Safari` | Safari |
| `settings.$SubtitleSource` | 字幕来源 |
| `settings.$SubtitleSource.desc` | 这是搜索字幕时的默认来源。播放时可通过菜单手动选择从其他来源搜索字幕。 |
| `settings.$SubtitleSourcePluginDesc` | 此来源由插件提供。请前往插件设置页进行配置。 |
| `settings.$ThisPluginIsNot` | 此插件未托管在 GitHub 上，请前往其网站下载。 |
| `settings.$Volume` | 音量 |
| `settings.$YTDL` | 在线视频（yt-dlp） |
| `settings.$onlineMediaPluginAdvice` | 推荐使用在线媒体插件 |
| `settings.$ytdlWarning` | 在线媒体插件提供画质切换、视频下载等额外功能。若已安装并启用该插件，IINA 将优先使用它；以下设置仅在插件不可用时生效。 |

## 8. 默认行为变化对照（源自更新后的内置 input.conf 默认值）

| 输入 | 变更前 | 变更后 |
|---|---|---|
| 左键单击 | 隐藏 OSC | 暂停/继续 |
| 左键双击 | 全屏 | 全屏（不变） |
| 右键 | 暂停/继续 | 全屏 |
| 中键 | 无操作 | 窗口置顶切换 |
| 鼠标侧键 前/后 | 当作中键（无操作） | 下一集/上一集 |
| 垂直滚轮 | 调音量 | 快进 120s / 快退 5s |
| 横向滚轮 | 快进/快退 | 快进 20s / 快退 20s |
| 触控板双指滚动 | 同纵横滚轮偏好 | 同 `WHEEL_*` 绑定（累计位移折算刻度） |
| OSC 进度条/音量条上滚动 | seek / 调音量 | 不变 |
| Music Mode 滚轮音量气泡 | 有 | 移除 |
| RIGHT / LEFT 键 | seek ±5s | seek +120s / -5s |
| UP / DOWN 键 | seek ±60s | 下一集/上一集 |
| SPACE | 暂停/继续 | 不变 |
| 捏合 / Force Touch | — | 不变 |

老用户可在「键位绑定」编辑器或 input.conf 自定义上述绑定（支持 `@iina` 命令）。

## 9. 验证计划

1. 静态检查（本机）：grep 确认无残留引用——7 个已删 Key 名、`ScrollAction` 枚举、
   `text_Mouse`、xib 已删 ObjectID、`sectionMouseView`、`scrollVerticallyLabel`、
   `handleVolumePopover`、`mouseExitEnterCount`、`videoViewAcceptsFirstMouse`、
   `playbackSpeedScrollAmount`、`playbackSpeedMap`；
   对比 `Base` 与 `zh-Hans` 的 `settings.*` 键集合，确认缺失为 0 且无重复键。
2. macOS 构建（需在 mac 上执行）：
   - §8 表逐项验证；
   - 键位绑定页修改鼠标绑定后立即生效；
   - 插件鼠标监听、Music Mode、交互模式不受影响；
   - 新旧两个设置窗口均只剩触控板设置且布局正常；
   - 侧键后退/前进方向正确（验证 §2.1 注）。

## 10. 明确不在范围内

- 其他 39 种语言的 .strings 清理（残留条目无害，交由 Crowdin 同步）；
- 插件输入系统（PluginInputManager）改动。

## 11. 实施备注：Swift 闭包内调用 `super` 的编译限制

这是一个容易踩的常见错误，首次 CI 构建（commit `1cc8e6bb`）即触发：

```
iina/PlayerWindowController.swift:483:9: error: using 'super' in a closure
where 'self' is explicitly captured is not yet supported
```

### 现象与原因

- Swift **不允许**在显式捕获列表包含 `self` 的闭包（`{ [self] in ... }`）中使用 `super`。
- 本次改动的 `otherMouseUp(with:)` 恰好同时需要两者：
  `defaultHandler: { [self] in ... super.otherMouseUp(with: event) ... }` → 编译失败。
- 注意 `mouseUp` / `rightMouseUp` 的 `{ [self] in ... }` 闭包体内没有 `super` 调用，
  因此不受影响。

### 修复方式

去掉显式捕获列表，改用隐式捕获；由于 `defaultHandler` 是逃逸闭包，
闭包内访问成员必须写显式 `self.` 前缀：

```swift
PluginInputManager.handle(
  input: PluginInputManager.Input.otherMouse, event: .mouseUp, player: player,
  arguments: mouseEventArgs(event), defaultHandler: {          // ← 无 [self]
  guard event.type == .otherMouseUp else {
    super.otherMouseUp(with: event)                            // ✓ 允许
    return
  }
  switch event.buttonNumber {
  case 3:  self.dispatchMouseBinding("MBTN_BACK")              // ✓ 显式 self.
  case 4:  self.dispatchMouseBinding("MBTN_FORWARD")
  default: self.dispatchMouseBinding("MBTN_MID")
  }
})
```

> 不要用 `[weak self]` 绕过：弱引用无法调用 `super`。

### 排查结论

对全仓 `*.swift` 扫描「`{ [self]` 闭包体中出现 `super.`」的组合，仅此一处；
其余 `{ [self] in` 闭包（如 `rightMouseUp`、原版遗留代码）均不含 `super` 调用，无需处理。
