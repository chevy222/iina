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
| 偏好清理深度 | 深度清理：删除废弃键定义、枚举与孤儿代码 |
| 旧 Preferences 窗口 | Mouse 区块一并移除 |
| useExactSeek UI | 随鼠标区块删除（偏好键保留，`PlayerCore.seek` 仍在用） |
| zh-Hans 范围 | 仅处理 `zh-Hans.lproj`：清理废弃键 + 去重，不补全无关缺失项 |

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
   单击 → 派发 `MBTN_LEFT`（定时器 userInfo 存按键名）；
   双击 → 取消定时器并派发 `MBTN_LEFT_DBL`。
   删除 hideOSC 特有的 `mouseExitEnterCount >= 2` 取消逻辑；
   `mouseExitEnterCount` 失去全部读者后连同变量与 MainWindow 两处自增一并删除。
3. `rightMouseUp` → `MBTN_RIGHT`。
4. `otherMouseUp`：按 §2.1 按 `event.buttonNumber` 映射派发；其余调用 super。
5. `scrollWheel` else 分支（非 OSC 滑块覆盖时）改为派发 `WHEEL_UP/DOWN/LEFT/RIGHT`：
   - 非 precise delta（物理滚轮）：每事件派发一次；
   - precise delta（触控板）：按方向累计 |delta|，每达到阈值常量
     `wheelTickThreshold = 40` 派发一次并扣减，避免一次手势触发几十次 seek；
   - 方向沿用现有 `scrollDirection` 与 delta 符号判定；
   - `seekOverride/volumeOverride` 分支（OSC 进度条/音量条滚动）原样保留；
   - 删除 Music Mode 音量弹窗联动调用（仅服务旧偏好路径）。
6. 清理缓存属性与 KVO：`singleClickAction`、`doubleClickAction`、
   `horizontalScrollAction`、`verticalScrollAction` 及对应 `observedPrefKeys` 条目和
   `observeValue` case。
7. 保留：`performMouseAction` 及其 MainWindow 重载（Force Touch 用）、
   `relativeSeekAmount/volumeScrollAmount/playbackSpeedScrollAmount/useExactSeek`
   偏好（OSC 滑块滚动仍在用）、`AppData` 三张映射表、
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
  `videoViewAcceptsFirstMouse`。
- 导出用大 switch 同步移除：Bool 列表中的 `.videoViewAcceptsFirstMouse`（:1495）、
  MouseClickAction case 仅留 `.forceTouchAction`（:1542-1546）、
  整个 `.horizontalScrollAction, .verticalScrollAction` case（:1570-1572）。
- 删除 `enum ScrollAction`（:509-530，含注释掉的 `passToMpv`）。
- 保留：`enum MouseClickAction`（Force Touch 用）、`PinchAction`、
  `useExactSeek`、三个灵敏度偏好的 Key 定义与 defaults 条目。

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

## 7. zh-Hans.lproj 翻译（仅动 zh-Hans）

### `Localizable.strings` — 删除废弃键
`settings.singleClickAction.*`、`settings.doubleClickAction.*`、
`settings.rightClickAction.*`（含错挂的 desc）、`settings.middleClickAction.*`、
`settings.verticalScrollAction.*`、`settings.horizontalScrollAction.*`、
`settings.videoViewAcceptsFirstMouse.label`、`settings.$Mouse`。
保留：`settings.pinchAction.*`、`settings.forceTouchAction.*`、`settings.$Trackpad`、
`settings.useExactSeek.*` 与灵敏度标签文案（对应功能仍在代码中使用，可能回归 UI）。

### `PrefControlViewController.strings` — 去重 + 清理
- 修复真实重复条目：`XXq-G1-9sl.title`（L79/L85）、`nJZ-9M-DHk.title`（L130/L160）各两次。
- 清理 xib 已删控件对应 ObjectID 条目，仅保留触控板区块相关翻译。

### 审计结论（本次不处理，仅记录）
zh-Hans `Localizable.strings` 本身无重复键；另有 85 个 EN 有而 ZH 缺失的键
（多为插件页/缓存页等，与本改动无关）与 10 个 EN 已废弃的陈旧键。

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
   `handleVolumePopover`、`mouseExitEnterCount`、`videoViewAcceptsFirstMouse`。
2. macOS 构建（需在 mac 上执行）：
   - §8 表逐项验证；
   - 键位绑定页修改鼠标绑定后立即生效；
   - 插件鼠标监听、Music Mode、交互模式不受影响；
   - 新旧两个设置窗口均只剩触控板设置且布局正常；
   - 侧键后退/前进方向正确（验证 §2.1 注）。

## 10. 明确不在范围内

- 其他 39 种语言的 .strings 清理（残留条目无害）；
- 插件输入系统（PluginInputManager）改动；
- zh-Hans 全文件补译（85 缺失 / 10 陈旧）。

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
