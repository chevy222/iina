# 设计文档：鼠标/滚轮事件统一派发至 mpv input.conf

## 1. 概述

将鼠标按键与滚轮事件的处理从 IINA 的偏好设置驱动模式，统一收敛到 mpv 的 `input.conf` 键绑定系统。用户通过编辑 `input.conf` 即可自定义全部鼠标行为，与键盘快捷键的配置方式保持一致。

核心原则：

- **纯 mpv 模式**：无绑定即无动作，IINA 侧不提供任何兜底逻辑。
- **最小化修改**：不引入新文件、新抽象；`Preference.swift` 完全不动。
- **键盘链路不受影响**：`keyDown → keyBindings` 流程保持原样。

## 2. 架构设计

### 2.1 事件派发链路（新）

```
Cocoa 鼠标/滚轮事件
  └─ PlayerWindowController.mouseUp / rightMouseUp / otherMouseUp / scrollWheel
       └─ PluginInputManager.handle(...)          // 插件管道，保持不变
            └─ defaultHandler（本次重写部分）
                 └─ 将事件映射为 mpv 键名
                      └─ PlayerCore.keyBindings[key]   // 从 input.conf 加载
                           └─ handleKeyBinding(kb)     // 执行 mpv 命令或 IINA 命令
```

- `PluginInputManager` 插件输入管道保持原有优先级语义不变，仅重写 `defaultHandler`。
- `PlayerCore.keyBindings` 加载自用户选择的 input.conf（默认 `iina/config/input.conf`），该文件已内置鼠标/滚轮默认绑定（`MBTN_LEFT_DBL cycle fullscreen`、`WHEEL_UP seek 10` 等），升级后默认体验与旧版一致。

### 2.2 关键设计决策

| 决策 | 理由 |
|---|---|
| 无绑定时不执行任何操作 | 要求纯 mpv 模式 |
| `Preference.swift` 中的键定义（`singleClickAction` 等）保留不动 | 老用户 UserDefaults 中已存在这些键，删除定义无收益且有迁移风险；UI 入口移除后这些键仅成为无害的遗留数据 |
| 移除 `videoViewAcceptsFirstMouse` 的设置入口 | 该选项随鼠标设置区块一并移除；焦点行为不属于 input.conf 能力范围，接受此项能力收缩 |
| 保留 `performMouseAction`（基类与 MainWindow 覆写） | Force Touch（`pressureChange`）仍在使用该路径 |
| 保留 MiniPlayer 的 `showVolumePopover` / `hideVolumeControl` | 静音按钮、音量按钮的点击交互仍在使用 |

## 3. 详细修改内容

### 3.1 PlayerWindowController.swift（核心）

**鼠标按键派发**（`mouseUp` / `rightMouseUp` / `otherMouseUp`）：

| 触发事件 | 派发的 mpv 键名 |
|---|---|
| 左键单击（clickCount = 1） | `MBTN_LEFT` |
| 左键双击（clickCount = 2） | `MBTN_LEFT_DBL` |
| 右键 | `MBTN_RIGHT` |
| 中键（buttonNumber = 2） | `MBTN_MID` |
| 前进侧键（buttonNumber = 3） | `MBTN_FORWARD` |
| 后退侧键（buttonNumber = 4） | `MBTN_BACK` |

直接按 `clickCount` 区分单双击，替代旧的单/双击延迟判定。

**滚轮派发**（`scrollWheel`）：

- 仅处理离散滚轮事件：`guard event.phase.isEmpty, event.momentumPhase.isEmpty`，触控板连续滚动及其动量事件不派发。
- 先按 `isDirectionInvertedFromDevice` 反转 delta（统一为"自然滚动关闭"语义），再按主方向（delta 绝对值较大者）确定键名：`WHEEL_UP` / `WHEEL_DOWN` / `WHEEL_LEFT` / `WHEEL_RIGHT`。
- 派发次数为 `max(Int(delta.rounded()), 1)`，不做平滑插值。

**删除的旧逻辑**：

- 单双击延迟判定：`singleClickTimer`、`mouseExitEnterCount`、`performMouseActionLater`
- 滚轮方向状态机：`ScrollDirection` 枚举、`scrollDirection` 变量
- seek 自动暂停/恢复：`wasPlayingBeforeSeeking`
- 滑块悬停覆盖：`seekOverride` / `volumeOverride` 及子类协作协议
- 基于偏好的缓存变量与 KVO 观察：`useExactSeek`、`relativeSeekAmount`、`volumeScrollAmount`、`playbackSpeedScrollAmount`、`singleClickAction`、`doubleClickAction`、`horizontalScrollAction`、`verticalScrollAction`

### 3.2 MainWindowController.swift

- 删除 `verticalScrollAction` / `horizontalScrollAction` 的 KVO 观察。
- `scrollWheel` 简化为：交互模式守卫 → 禁用视图守卫 → `super.scrollWheel(with:)`；删除 `seekOverride` / `volumeOverride` 逻辑。
- 删除 `mouseExitEnterCount` 的两处自增。
- 删除 `isMomentumScrollingAllowed` 变量及其全部三处引用（声明、`scrollWheel` 中的动量守卫与赋值、`mouseExited` 中的重置）。该动量准入判定原用于区分"正常动量"与"突变动量"滚动，但基类 `scrollWheel` 已通过 `guard event.phase.isEmpty, event.momentumPhase.isEmpty` 丢弃全部触控板/动量事件，使其成为死逻辑。`isMouseInWindow` 在光标显隐逻辑中仍有使用，正确保留。

### 3.3 MiniPlayerWindowController.swift

- `scrollWheel` 简化为单一守卫 + `super.scrollWheel(with:)`。
- 删除 `hideVolumeControlTask` 变量与 `handleVolumePopover` 方法（滚轮调音量的气泡提示逻辑）。

### 3.4 设置界面

- `SettingsPageControl.swift`：移除 `sectionMouse()` 及三个灵敏度滑块（`SliderView` 辅助类），`content()` 仅返回 `sectionTrackpad()`。
- `PrefControlViewController.swift`：`sectionViews` 仅保留 `sectionTrackpadView`；删除 `sectionMouseView`、`forceTouchLabel`、`scrollVerticallyLabel` IBOutlet 及 `viewDidLoad` 中的宽度约束。
- `Base.lproj/PrefControlViewController.xib`：删除鼠标设置区块视图及全部相关连接（outlet、UserDefaults binding、约束），无悬空引用。
- `SettingsLocalization.swift`：移除 `text_Mouse` 本地化 key。
- Force Touch 与双指缩放属于触控板区块，保留。

### 3.5 翻译（zh-Hans）

- `Localizable.strings`：删除单击/双击/右键/中键动作、纵横滚动动作、精确 seek、三个灵敏度滑块共 47 条文案；保留 `forceTouchAction`、`pinchAction`。
- `PrefControlViewController.strings`：仅保留触控板区块控件的 8 条翻译。

### 3.6 其他

- `.gitignore`：追加 `.idea/`。

## 4. 行为变化（用户可见）

| 场景 | 旧行为 | 新行为 |
|---|---|---|
| 滚轮悬停在进度条/音量滑块上 | 滚轮 seek / 调音量 | 派发至 input.conf 绑定（默认 `WHEEL_UP/DOWN seek ±10`） |
| 滚轮 seek 时自动暂停/恢复 | 有 | 无 |
| 迷你播放器滚轮调音量气泡 | 有 | 无（音量按钮交互保留） |
| 鼠标行为自定义入口 | 偏好设置 → 控制 | 手动编辑 input.conf |

迁移示例（见需求文档 §6）：

```
MBTN_LEFT_DBL cycle fullscreen
WHEEL_UP seek 10
WHEEL_DOWN seek -10
```
