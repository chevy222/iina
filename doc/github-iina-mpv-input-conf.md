# Plan: 去掉 IINA 快捷键拦截，完全使用 mpv 的 input.conf

## Context

用户希望让 IINA 绕过自身对**鼠标键/滚轮**的偏好处理逻辑，改为统一交给 mpv 的 `input.conf` 键绑定系统。原来 IINA 在 Cocoa 层拦截鼠标事件后，根据偏好设置（如"双击全屏""滚轮调音量"）执行动作，用户认为这不如直接在 mpv 的 `input.conf` 中配置来得统一和强大。

**修改内容：**
- 鼠标键事件 → 交给 mpv binding
- 鼠标滚轮事件 → 交给 mpv binding
- **无 binding 时不执行任何操作**（纯 mpv 模式，无 IINA fallback）
- 默认 `iina-default-input.conf` **不预填**鼠标/滚轮绑定
- 图形偏好界面里的鼠标/滚轮动作配置**移除**，用户直接编辑 `conf` 文件
- **键盘快捷键不受影响**，保持现有 IINA keyDown → keyBindings 流程

**设计原则：** 鼠标事件入口仍是 `PluginInputManager.handle`，本方案仅改其 `defaultHandler` 闭包——查 `PlayerCore.keyBindings`，有绑定则执行，无绑定则不执行任何操作。`PlayerCore.keyBindings` 按 `normalizedMpvKey` 索引，`KeyCodeHelper.normalizeMpv` 对 `MBTN_LEFT`/`WHEEL_UP` 等多字符特殊键仅做 `uppercased()`，不影响查找。`handleKeyBinding(_:)` 基类方法已能正确执行 mpv 命令和 IINA 命令，可直接复用。

---

## Part 1: 分支重置（用户执行）

1. 切到 `develop` 分支
2. `git fetch origin` 获取官方最新代码
3. `git checkout -b mpv_input origin/develop` 从官方最新创建干净分支

---

## Part 2: PlayerWindowController.swift — 鼠标键路由到 mpv binding

### 2.1 新增辅助方法

```swift
/// 尝试将鼠标键事件派发给 mpv input.conf 绑定。
/// 返回 true 表示已处理；false 表示无绑定。
private func handleInputBinding(_ input: String) -> Bool {
    guard let keyBinding = PlayerCore.keyBindings[input] else { return false }
    return handleKeyBinding(keyBinding)
}

/// 将 macOS 鼠标按钮编号映射为 mpv 按钮名称。
private func mpvMouseButtonName(for buttonNumber: Int) -> String? {
    switch buttonNumber {
    case 2: return "MBTN_MID"
    case 3: return "MBTN_FORWARD"
    case 4: return "MBTN_BACK"
    default: return nil
    }
}
```

### 2.2 左键抬起 `mouseUp(with:)` — 简化版

`mouseUp(with:)` 方法顶部已有 `guard !event.inAnyOf(mouseActionDisabledViews) else { return }`，在 OSC 等控件上点击时不会进入 defaultHandler，无需在 handler 内重复检查。

```swift
defaultHandler: { [self] in
    if event.clickCount == 2 {
        self.handleInputBinding("MBTN_LEFT_DBL")
    } else {
        self.handleInputBinding("MBTN_LEFT")
    }
}
```

> 设计说明：无单/双击延迟区分，直接根据 clickCount 查找对应 binding。无 binding 时不执行任何操作。

### 2.3 右键抬起 `rightMouseUp(with:)` — 简化版

```swift
defaultHandler: {
    self.handleInputBinding("MBTN_RIGHT")
}
```

### 2.4 中键/其他键 `otherMouseUp(with:)` — 简化版

```swift
defaultHandler: {
    guard event.type == .otherMouseUp else {
        super.otherMouseUp(with: event)
        return
    }
    if let input = self.mpvMouseButtonName(for: event.buttonNumber) {
        self.handleInputBinding(input)
    }
}
```

### 2.5 滚轮 `scrollWheel(with:)` — 纯 mpv 模式

完全替换原有滚轮逻辑，仅当存在 mpv WHEEL_* 绑定时处理滚轮事件：

```swift
override func scrollWheel(with event: NSEvent) {
    // 仅当存在 mpv WHEEL_* 绑定时处理滚轮事件
    if event.phase.isEmpty {
        _ = self.tryWheelBinding(event)
    }
}

/// 尝试将鼠标滚轮事件派发给 mpv WHEEL_* binding。
/// 仅对 phase.isEmpty 的离散滚轮事件生效。
private func tryWheelBinding(_ event: NSEvent) -> Bool {
    let isNatural = event.isDirectionInvertedFromDevice
    let deltaX = isNatural ? event.scrollingDeltaX : -event.scrollingDeltaX
    let deltaY = isNatural ? -event.scrollingDeltaY : event.scrollingDeltaY

    // 主方向判定
    let primaryBinding: String
    let primaryDelta: Double
    if abs(deltaY) >= abs(deltaX) {
        primaryBinding = deltaY > 0 ? "WHEEL_UP" : "WHEEL_DOWN"
        primaryDelta = Double(deltaY)
    } else {
        primaryBinding = deltaX > 0 ? "WHEEL_RIGHT" : "WHEEL_LEFT"
        primaryDelta = Double(deltaX)
    }

    guard PlayerCore.keyBindings[primaryBinding] != nil else { return false }

    // 按 delta 绝对值决定派发次数（整数计数，不做平滑插值）
    let dispatchCount = max(1, Int(abs(primaryDelta).rounded(.awayFromZero)))
    for _ in 0..<dispatchCount {
        _ = handleInputBinding(primaryBinding)
    }
    return true
}
```

> **设计说明**：
> - `event.phase.isEmpty` = 鼠标滚轮的离散 tick，适合 mpv 的"按 tick 触发"模型
> - 无 WHEEL_* 绑定时，滚轮事件不执行任何操作
> - 如用户希望每 tick 效果更大，可在 input.conf 中绑定 `WHEEL_UP add volume 10` 等更大步进值

### 2.6 已知限制：mouseDown 不路由到 mpv binding

mpv 的 input.conf 支持 `MBTN_LEFT_DOWN`/`MBTN_RIGHT_DOWN`/`MBTN_MID_DOWN` 等按下时触发的绑定。本方案**不处理** `mouseDown` 事件路由，原因：

1. IINA 现有 `mouseDown` 仅用于插件系统（`PluginInputManager.handle` 无 defaultHandler），不执行任何 IINA 偏好动作。
2. 按下事件在 Cocoa 中可能触发拖拽等其他行为，贸然路由可能引入副作用。
3. 鼠标"点击"语义（press+release）在 mpv 中由 `MBTN_LEFT`（等）表示，已覆盖。

如后续有需求，可在 `mouseDown` 的 `PluginInputManager.handle` 中追加 defaultHandler，调用 `handleInputBinding("MBTN_LEFT_DOWN")` 等。

---

## Part 4: 图形偏好界面 — 移除整个鼠标部分，只保留触摸板设置

### 4.1 PrefControlViewController.swift — 移除鼠标 section

将 `sectionViews` 改为只返回 `sectionTrackpadView`，不再包含 `sectionMouseView`。

```swift
override var sectionViews: [NSView] {
  return [sectionTrackpadView]
}
```

同时移除 `viewDidLoad` 方法（不再需要过滤子视图）。

### 4.2 SettingsPageControl.swift（SwiftUI 面板）

移除 `sectionMouse()` 方法和调用，`content()` 只保留 `sectionTrackpad()`。

```swift
override func content() -> [SettingsSection] {
  return sections {
    sectionTrackpad()
  }
}
```

删除整个 `sectionMouse()` 方法。

> **设计说明**：整个鼠标设置部分（包括 `videoViewAcceptsFirstMouse`、`useExactSeek`、灵敏度滑块等）都被移除，只保留触摸板的两个设置（`pinchAction` 和 `forceTouchAction`）。

---

## Part 5: 默认 input.conf — 不做改动

`iina/config/iina-default-input.conf` **保持原样**，不添加任何鼠标/滚轮绑定。

效果：默认安装下，鼠标键/滚轮**不执行任何操作**（因为无 binding）。用户需在 `~/.config/iina/input.conf` 或自定义配置文件中添加 `MBTN_LEFT`、`WHEEL_UP` 等绑定才能使用鼠标/滚轮功能。

---

## 关键文件清单

| 文件 | 改动类型 |
|------|----------|
| `iina/PlayerWindowController.swift` | 修改：简化鼠标键/滚轮 handler，新增 binding 路由辅助方法，移除 `dispatchPendingLeftClick` 和 `performMouseActionLater` |
| `iina/PrefControlViewController.swift` | 修改：sectionViews 只返回 sectionTrackpadView |
| `iina/SettingsPageControl.swift` | 修改：移除 sectionMouse() 方法和调用，只保留 sectionTrackpad() |
| `iina/MainWindowController.swift` | 修改：修复标题显示时序问题 |
| `iina/Titlebar.swift` | 修改：updateTitle 方法接受标题参数，修复时序问题 |

---

## 复用的现有方法/结构

| 现有代码 | 位置 | 用途 |
|----------|------|------|
| `handleKeyBinding(_:)` | PlayerWindowController.swift:248 | 分发 mpv 命令（默认分支调用 `player.mpv.command(rawString:)`） |
| `PlayerCore.keyBindings` | PlayerCore.swift:321 | 已解析的 binding 字典，按 normalizedMpvKey 索引 |
| `PlayerCore.setKeyBindings(_:)` | PlayerCore.swift:597 | 解析 input.conf 并填充 keyBindings 字典 |
| `PluginInputManager.handle(...)` | PluginInputManager.swift:87 | 鼠标事件入口（含插件链），本方案仅改其 defaultHandler 闭包 |
| `KeyCodeHelper.normalizeMpv` | KeyCodeHelper.swift:402 | 对多字符键做 `uppercased()`，`MBTN_LEFT` → `MBTN_LEFT` 不变 |

---

## 验证

1. **构建**：`xcodebuild -project iina.xcodeproj -scheme IINA -configuration Debug build`，确认无编译错误
2. **默认配置下鼠标/滚轮无效**：用默认 "IINA Default" 配置播放视频 — 左键点击、滚轮应无任何效果（因为无 MBTN/WHEEL 绑定）
3. **自定义 binding 生效**：在 `~/.config/iina/input.conf` 添加 `MBTN_LEFT cycle pause`、`WHEEL_UP add volume 5` 等，重载配置后 — 左键单击应暂停、滚轮应以 5 步进调音量
4. **双击 binding 生效**：配置 `MBTN_LEFT_DBL cycle fullscreen`，双击应全屏
5. **右键 binding 生效**：配置 `MBTN_RIGHT cycle pause`，右键单击应暂停
6. **偏好 UI 清理**：打开偏好设置 → Control 页面，应只显示触摸板设置（"Pinch to:" 和 "Force Touch to:"），无鼠标/滚轮设置
7. **配置切换**：在 Key Binding 设置中切换配置后重载，鼠标/滚轮行为应随之改变
8. **otherMouseUp 未知按钮不崩溃**：使用非标准鼠标按钮（buttonNumber > 4）时不应崩溃

---

## 不做的事

- ❌ 不修改默认 `iina-default-input.conf`
- ❌ 不修改 `.gitignore`（个人环境无关）
- ❌ 不改键盘快捷键处理逻辑
- ❌ 不路由 `mouseDown` 事件到 mpv binding（见 Part 2.7 已知限制）
- ❌ 不保留 IINA 原有的鼠标/滚轮 fallback 逻辑（纯 mpv 模式）

## 额外改动（超出原计划）

- ✅ 移除整个鼠标设置部分（`sectionMouseView` 和 `sectionMouse()`），只保留触摸板设置
- ✅ 修复播放器右上角标题显示错误（提交 `a2e26dec` 引入的时序 bug）

---

## Bug 修复记录

### 播放器右上角标题显示错误（显示旧文件名）

**引入版本：** 提交 `a2e26dec` (2026-06-01, "ui: use custom title bar")

**问题描述：** 播放新文件时，右上角自定义标题栏显示的不是当前播放的文件名，而是之前播放过的文件名。

**根本原因：** 时序问题。

在 `MainWindowController.updateTitle()` 中：
```swift
window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
titleBarView?.updateTitle()  // 立即调用
```

`setTitleWithRepresentedFilename` 设置窗口标题后，系统标题栏的 `NSTextField` 不会立即更新。而 `Titlebar.updateTitle()` 此时读取 `mainWindow.titleTextField.stringValue`（系统标题栏文本字段），获取到的还是旧文件名。

**修复方案：** 直接将计算好的标题字符串传递给 `Titlebar.updateTitle()`，避免依赖系统标题栏的更新时序。

**修改文件：**

1. `iina/MainWindowController.swift` — `updateTitle()` 方法：
   - 新增 `newTitle` 变量存储计算好的标题
   - 将 `newTitle` 传递给 `titleBarView?.updateTitle(newTitle)`

2. `iina/Titlebar.swift` — `updateTitle()` 方法：
   - 方法签名改为 `func updateTitle(_ title: String? = nil)`
   - 优先使用传入的 `title` 参数，否则回退到读取系统标题栏

**修复后代码：**

`MainWindowController.swift`:
```swift
@objc
override func updateTitle() {
    let newTitle: String
    if player.info.isNetworkResource {
        window?.representedURL = nil
        newTitle = player.getMediaTitle()
        window?.title = newTitle
    } else {
        window?.representedURL = player.info.currentURL
        newTitle = player.info.currentURL?.lastPathComponent ?? ""
        if Preference.bool(for: .useLegacyFullScreen) {
            window?.title = newTitle
        } else {
            window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
        }
    }
    titleBarView?.updateTitle(newTitle)  // 直接传入标题
    // ...
}
```

`Titlebar.swift`:
```swift
func updateTitle(_ title: String? = nil) {
    guard let titleTextField,
          let docIcon else { return }

    if let title = title {
        titleTextField.stringValue = title  // 使用传入的标题
    } else if let sysTitle = mainWindow.titleTextField {
        titleTextField.stringValue = sysTitle.stringValue  // 回退读取系统标题栏
    }

    if let fileName = mainWindow.window?.representedFilename {
        docIcon.image = NSWorkspace.shared.icon(forFile: fileName)
    } else {
        docIcon.image = nil
    }
}
```
