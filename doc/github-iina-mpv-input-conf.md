# Plan: 去掉 IINA 快捷键拦截，完全使用 mpv 的 input.conf

## Context

用户希望让 IINA 绕过自身对**鼠标键/滚轮**的偏好处理逻辑，改为统一交给 mpv 的 `input.conf` 键绑定系统。原来 IINA 在 Cocoa 层拦截鼠标事件后，根据偏好设置（如"双击全屏""滚轮调音量"）执行动作，用户认为这不如直接在 mpv 的 `input.conf` 中配置来得统一和强大。

**修改内容：**
- 鼠标键事件 → 交给 mpv binding
- **滚轮保持原有 IINA 高质量逻辑**——精确、有幅度区分，不做离散重复派发
- **Trackpad 完全保持 IINA 精确逻辑**，只有鼠标滚轮走 mpv binding 旁路
- 默认 `iina-default-input.conf` **不预填**鼠标/滚轮绑定，无 binding 时回退到 IINA 原有偏好逻辑
- 图形偏好界面里的鼠标/滚轮动作配置**移除**，用户直接编辑 `conf` 文件
- **键盘快捷键不受影响**，保持现有 IINA keyDown → keyBindings 流程

**设计原则：** 鼠标事件入口仍是 `PluginInputManager.handle`，本方案仅改其 `defaultHandler` 闭包——优先查 `PlayerCore.keyBindings`，无绑定则回退 IINA 原有偏好逻辑。`PlayerCore.keyBindings` 按 `normalizedMpvKey` 索引，`KeyCodeHelper.normalizeMpv` 对 `MBTN_LEFT`/`WHEEL_UP` 等多字符特殊键仅做 `uppercased()`，不影响查找。`handleKeyBinding(_:)` 基类方法已能正确执行 mpv 命令和 IINA 命令，可直接复用。

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
/// 返回 true 表示已处理（调用方应停止后续 IINA 逻辑）；false 表示无绑定，由调用方走原有 IINA 逻辑。
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

### 2.2 左键抬起 `mouseUp(with:)` — defaultHandler 改造

`mouseUp(with:)` 方法顶部已有 `guard !event.inAnyOf(mouseActionDisabledViews) else { return }`，在 OSC 等控件上点击时不会进入 defaultHandler，无需在 handler 内重复检查。

`VideoView.mouseUp`（VideoView.swift:129）在全屏模式下会直接调用 `player.mainWindow.mouseUp(with: event)` 作为 Cocoa 缺陷 workaround。本方案只改 defaultHandler 闭包内容，不改变方法签名，该 workaround 不受影响。

```swift
defaultHandler: { [self] in
    // 优先：mpv binding
    if event.clickCount == 2 {
        if self.handleInputBinding("MBTN_LEFT_DBL") { return }
        // DBL 无绑定时，回退到单击 binding
        if self.handleInputBinding("MBTN_LEFT") { return }
    } else {
        // 单击：如果有 DBL 绑定则延迟派发，否则直接派发 MBTN_LEFT
        if PlayerCore.keyBindings["MBTN_LEFT_DBL"] != nil {
            singleClickTimer?.invalidate()
            singleClickTimer = Timer.scheduledTimer(
                timeInterval: NSEvent.doubleClickInterval,
                target: self,
                selector: #selector(dispatchPendingLeftClick),
                userInfo: singleClickAction,
                repeats: false)
            mouseExitEnterCount = 0
            return  // 等待 timer，不立即执行
        }
        if self.handleInputBinding("MBTN_LEFT") { return }
    }

    // 兜底：原有 IINA 偏好逻辑
    if event.clickCount == 1 {
        if doubleClickAction == .none {
            performMouseAction(singleClickAction)
        } else {
            singleClickTimer = Timer.scheduledTimer(
                timeInterval: NSEvent.doubleClickInterval,
                target: self,
                selector: #selector(performMouseActionLater),
                userInfo: singleClickAction,
                repeats: false)
            mouseExitEnterCount = 0
        }
    } else if event.clickCount == 2 {
        if let timer = singleClickTimer { timer.invalidate(); singleClickTimer = nil }
        performMouseAction(doubleClickAction)
    }
}
```

新增 timer 回调（用于 mpv binding 路径的延迟单击）：

```swift
/// 延迟派发单击 binding。若 MBTN_LEFT 无绑定，回退到 IINA 偏好逻辑。
/// 同时检查 mouseExitEnterCount 以取消鼠标重新进入窗口后的 hideOSC 动作，
/// 与 performMouseActionLater 保持一致行为。
@objc private func dispatchPendingLeftClick(_ timer: Timer) {
    singleClickTimer = nil
    // 优先尝试 mpv binding
    if handleInputBinding("MBTN_LEFT") { return }
    // 无 MBTN_LEFT 绑定时，回退到 IINA 偏好逻辑
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
    if mouseExitEnterCount >= 2 && action == .hideOSC {
        return
    }
    performMouseAction(action)
}
```

> 设计说明：`userInfo` 传入 `singleClickAction` 而非 `nil`，是为了在用户绑定了 `MBTN_LEFT_DBL` 但未绑定 `MBTN_LEFT` 时，单击触发 timer → binding 查找失败 → 回退到 IINA 原有单击动作，避免单击事件被吞掉。

### 2.3 右键抬起 `rightMouseUp(with:)` — defaultHandler 改造

```swift
defaultHandler: {
    if !self.handleInputBinding("MBTN_RIGHT") {
        self.performMouseAction(Preference.enum(for: .rightClickAction))  // 兜底
    }
}
```

### 2.4 中键/其他键 `otherMouseUp(with:)` — defaultHandler 改造

保留原有 `event.type` 检查和 `super.otherMouseUp` 回退，确保非 `.otherMouseUp` 类型和未知按钮仍走原有路径：

```swift
defaultHandler: {
    guard event.type == .otherMouseUp else {
        super.otherMouseUp(with: event)
        return
    }
    guard let input = self.mpvMouseButtonName(for: event.buttonNumber) else {
        self.performMouseAction(Preference.enum(for: .middleClickAction))  // 兜底
        return
    }
    if !self.handleInputBinding(input) {
        self.performMouseAction(Preference.enum(for: .middleClickAction))  // 兜底
    }
}
```

### 2.5 滚轮 `scrollWheel(with:)` — 保持原有逻辑，仅对**鼠标滚轮**追加 mpv binding 旁路

原有逻辑（`relativeSeekAmount`/`volumeScrollAmount`/`playbackSpeedScrollAmount` + `seekAmountMap`/`volumeMap`/`playbackSpeedScrollMap` + trackpad 暂停恢复 + MiniPlayer volume popover）**完全保留不动**。

仅在方法顶部增加鼠标滚轮的 binding 旁路：

```swift
override func scrollWheel(with event: NSEvent) {
    // --- 新增：鼠标滚轮的 mpv binding 旁路（仅 phase.isEmpty 的离散滚轮事件）---
    if event.phase.isEmpty, self.tryWheelBinding(event) { return }

    // --- 以下全部是原有逻辑，一字不改 ---
    let isMouse = event.phase.isEmpty
    // ... (原有全部代码保持不变)
}

/// 尝试将鼠标滚轮事件派发给 mpv WHEEL_* binding。
/// 仅对 phase.isEmpty 的离散滚轮事件生效；trackpad 连续滚动返回 false 走原有逻辑。
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

> **delta 计算差异说明**：
> - 原有滚轮代码对非精确滚动（鼠标）使用 `event.scrollingDeltaY.unifiedDouble * 2` 来放大 delta（典型鼠标滚轮每 tick = ±1，放大后 = ±2）。
> - `tryWheelBinding` 使用 `scrollingDeltaY` 原始值（每 tick = ±1），派发 1 次。这是有意为之——mpv 的 WHEEL 绑定按 tick 触发，每个 tick 派发一次更符合 mpv 语义。
> - 如用户希望每 tick 效果更大，可在 input.conf 中绑定 `WHEEL_UP add volume 10` 等更大步进值。
> - **仅当存在 WHEEL_* 绑定时** `tryWheelBinding` 才返回 true，否则原有逻辑不受影响。

> **设计说明**：
> - `event.phase.isEmpty` = 鼠标滚轮的离散 tick，适合 mpv 的"按 tick 触发"模型
> - trackpad 的连续滚动（phase 含 `.began/.changed/.ended`）始终走原有精确 delta×系数逻辑
> - 默认配置不含 WHEEL_* 绑定时，`tryWheelBinding` 返回 false，所有滚轮行为与改动前完全一致

### 2.6 缓存属性 & KVO — **全部保留** + 修复 MiniPlayer scroll-action KVO

`relativeSeekAmount`/`volumeScrollAmount`/`playbackSpeedScrollAmount`/`singleClickAction`/`doubleClickAction`/`horizontalScrollAction`/`verticalScrollAction` 属性和 KVO 全部保留（滚轮和兜底逻辑仍用）。

**顺带修复一个已存在的 KVO 问题**：`horizontalScrollAction`/`verticalScrollAction` 在 `PlayerWindowController.observedPrefKeys`（:66-67）中注册了 KVO，但 `PlayerWindowController.observeValue`（:73-132）的 switch 无对应 case（落入 `default: return`）。`MainWindowController.observeValue`（:296-303）已自行补了这两个 case，所以主窗口不受影响；但 `MiniPlayerWindowController` 不覆写 `observeValue`，直接继承父类，因此运行时修改滚动偏好对 MiniPlayer 不生效。

修复方式：将这两个 case 上移到父类 `PlayerWindowController.observeValue`，然后从 `MainWindowController.observeValue` 中删除（见 Part 3）。

在 `PlayerWindowController.observeValue` 的 switch 中补充：

```swift
case PK.horizontalScrollAction.rawValue:
    if let newValue = change[.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
    }
case PK.verticalScrollAction.rawValue:
    if let newValue = change[.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
    }
```

### 2.7 保留不变的方法

- `performMouseAction(_:)` — 兜底用
- `performMouseActionLater(_:)` — 兜底用
- `ScrollDirection` 枚举、`scrollDirection`、`wasPlayingBeforeSeeking` — 滚轮逻辑用
- `singleClickTimer`、`mouseExitEnterCount` — 单击/双击区分用

### 2.8 已知限制：mouseDown 不路由到 mpv binding

mpv 的 input.conf 支持 `MBTN_LEFT_DOWN`/`MBTN_RIGHT_DOWN`/`MBTN_MID_DOWN` 等按下时触发的绑定。本方案**不处理** `mouseDown` 事件路由，原因：

1. IINA 现有 `mouseDown` 仅用于插件系统（`PluginInputManager.handle` 无 defaultHandler），不执行任何 IINA 偏好动作。
2. 按下事件在 Cocoa 中可能触发拖拽等其他行为，贸然路由可能引入副作用。
3. 鼠标"点击"语义（press+release）在 mpv 中由 `MBTN_LEFT`（等）表示，已覆盖。

如后续有需求，可在 `mouseDown` 的 `PluginInputManager.handle` 中追加 defaultHandler，调用 `handleInputBinding("MBTN_LEFT_DOWN")` 等。

---

## Part 3: MainWindowController.swift

删除 `observeValue` 中对 `.verticalScrollAction`/`.horizontalScrollAction` 的两个 case（已上移到父类 2.6）：

```swift
// 删除以下两个 case（已移入 PlayerWindowController）
case PK.verticalScrollAction.rawValue:
    if let newValue = change[.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
    }
case PK.horizontalScrollAction.rawValue:
    if let newValue = change[.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
    }
```

本类中 `scrollWheel(with:)` 的 `seekOverride`/`volumeOverride` 置位逻辑保持不变（父类滚轮逻辑需要）。

---

## Part 4: 图形偏好界面 — 移除鼠标/滚轮动作配置

### 4.1 PrefControlViewController.swift — viewDidLoad 改造

在 `viewDidLoad` 中通过 XIB `identifier` 标记过滤 `sectionMouseView` 子视图。需要在 XIB 中为保留的控件添加 `identifier="keep"`，然后运行时移除所有未标记的子视图。

保留的控件（在 XIB 中添加 `identifier="keep"`）：
- "Accepts first mouse click when not focused" checkbox（`l7e-jz-0cj`）
- "Seek type:" label（`zSQ-pa-Urx`）
- "Seek type:" popup（`VlR-LI-plv`）
- "Exact seek is more precise..." description（`LN0-rs-jJB`）
- 左侧图像容器（`2ma-hh-43h`，Mouse Image Container View）

此外保留隐藏的 section title（`fL5-By-MLE`，`identifier="SectionTitleMouse"`，`hidden="YES"`）。

移除的控件（未添加 `identifier="keep"`，运行时自动移除）：
- "Single click to:" popup + label
- "Double click to:" popup + label
- "Right click to:" popup + label
- "Middle click to:" popup + label
- "Scroll vertically to:" popup + label
- "Scroll horizontally to:" popup + label
- "Sensitivity for normal seek:" slider + label
- "Sensitivity for volume:" slider + label
- "Sensitivity for speed:" slider + label
- `forceTouchLabel`（隐藏的辅助 label）

实现方式：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    let keepIdentifiers: Set<String> = ["keep", "SectionTitleMouse"]
    sectionMouseView.subviews
      .filter { !keepIdentifiers.contains($0.identifier?.rawValue ?? "") }
      .forEach { $0.removeFromSuperview() }
}
```

> **注意**：`viewDidLoad` 中原有代码 `forceTouchLabel.widthAnchor.constraint(equalTo: scrollVerticallyLabel.widthAnchor...)` 会因移除控件而崩溃。必须**先删除此约束代码**，再执行子视图过滤。同时需移除 `forceTouchLabel` 和 `scrollVerticallyLabel` 两个 IBOutlet 声明。

> **设计说明**：通过 XIB `identifier` 标记保留控件，运行时按 identifier 过滤移除其余子视图。相比遍历判断控件类型或重建约束，此方案更简洁且不易出错。被移除控件的约束因 `removeFromSuperview()` 一并失效，无需手动清理。

### 4.2 PrefControlViewController.xib

删除 File's Owner 中的 outlet 连接：
- `forceTouchLabel`
- `scrollVerticallyLabel`

XIB 中的控件实例由 viewDidLoad 动态移除，无需手动删 XIB 节点。

### 4.3 SettingsPageControl.swift（SwiftUI 面板）

删除 `sectionMouse()` 方法内以下 `SettingsItem` 行：
- `singleClickAction` 的 `PopupButton`
- `doubleClickAction` 的 `PopupButton`
- `rightClickAction` 的 `PopupButton`
- `middleClickAction` 的 `PopupButton`
- `verticalScrollAction` 的 `PopupButton`
- `horizontalScrollAction` 的 `PopupButton`

保留：
- `videoViewAcceptsFirstMouse` 的 `Switch`
- `useExactSeek` 的 `PopupButton`（及其 `.hasDescription()`）
- `sensSeek`/`sensVolume`/`sensSpeed` 的 `Custom` view 及对应 `lazy var` 属性

> **设计说明**：灵敏度滑块（`relativeSeekAmount`/`volumeScrollAmount`/`playbackSpeedScrollAmount`）仍被 Part 2.5 保留的 IINA 滚轮兜底逻辑使用。移除滑块会导致用户无法调整兜底滚轮行为的灵敏度，因此保留。仅移除鼠标/滚轮**动作选择**（单击/双击/右键/中键/滚轮方向 → 动作），动作选择改为通过 `input.conf` 配置。

`sectionMouse()` 改造后：

```swift
private func sectionMouse() -> SettingsSection {
    return section {
      SettingsList(title: .text_Mouse) {
        SettingsItem.Switch()
          .bindTo(.videoViewAcceptsFirstMouse)
          .image(name: ["macwindow.and.pointer.arrow", "macwindow.and.cursorarrow"])
      }
      SettingsList {
        SettingsItem.PopupButton()
          .bindTo(.useExactSeek, ofType: Preference.SeekOption.self)
          .image(name: ["15.arrow.trianglehead.clockwise", "goforward.15"])
          .hasDescription()
        SettingsItem.Custom()
          .view(sensSeek.view)
        SettingsItem.Custom()
          .view(sensSpeed.view)
        SettingsItem.Custom()
          .view(sensVolume.view)
      }
    }
}
```

---

## Part 5: 默认 input.conf — 不做改动

`iina/config/iina-default-input.conf` **保持原样**，不添加任何鼠标/滚轮绑定。

效果：默认安装下，所有鼠标键/滚轮行为与改动前完全一致（走 IINA 偏好逻辑）。用户如需自定义，在 `~/.config/iina/input.conf` 或自定义配置文件中添加 `MBTN_LEFT`、`WHEEL_UP` 等绑定即可覆盖。

---

## 关键文件清单

| 文件 | 改动类型 |
|------|----------|
| `iina/PlayerWindowController.swift` | 修改：鼠标键 handler + 新增 binding 路由辅助方法 + 鼠标滚轮旁路 + 修复 scroll-action KVO + 新增 `dispatchPendingLeftClick` |
| `iina/MainWindowController.swift` | 修改：删除已上移到父类的两个 scroll-action KVO case |
| `iina/PrefControlViewController.swift` | 修改：删除 `forceTouchLabel`/`scrollVerticallyLabel` outlet 和约束，viewDidLoad 过滤子视图移除鼠标动作配置 UI |
| `iina/Base.lproj/PrefControlViewController.xib` | 修改：删除 `forceTouchLabel`/`scrollVerticallyLabel` 的 outlet 连接 |
| `iina/SettingsPageControl.swift` | 修改：移除鼠标/滚轮动作选择 SettingsItem，保留灵敏度滑块 |

---

## 复用的现有方法/结构

| 现有代码 | 位置 | 用途 |
|----------|------|------|
| `handleKeyBinding(_:)` | PlayerWindowController.swift:248 | 分发 mpv 命令（默认分支调用 `player.mpv.command(rawString:)`） |
| `PlayerCore.keyBindings` | PlayerCore.swift:321 | 已解析的 binding 字典，按 normalizedMpvKey 索引 |
| `PlayerCore.setKeyBindings(_:)` | PlayerCore.swift:597 | 解析 input.conf 并填充 keyBindings 字典 |
| `PluginInputManager.handle(...)` | PluginInputManager.swift:87 | 鼠标事件入口（含插件链），本方案仅改其 defaultHandler 闭包 |
| `performMouseAction(_:)` | PlayerWindowController.swift:429 | 兜底：无 binding 时的原有行为 |
| `performMouseActionLater(_:)` | PlayerWindowController.swift:529 | 兜底：单击延迟派发（含 `mouseExitEnterCount` 检查） |
| `singleClickTimer`/`mouseExitEnterCount` | PlayerWindowController.swift:142/143 | 单击/双击区分机制，复用 |
| `AppData.seekAmountMap/seekAmountMapMouse/volumeMap/playbackSpeedMap` | AppData.swift | 滚轮原有精确系数表 |
| `KeyCodeHelper.normalizeMpv` | KeyCodeHelper.swift:402 | 对多字符键做 `uppercased()`，`MBTN_LEFT` → `MBTN_LEFT` 不变 |

---

## 验证

1. **构建**：`xcodebuild -project iina.xcodeproj -scheme IINA -configuration Debug build`，确认无编译错误
2. **默认配置下行为不变**：用默认 "IINA Default" 配置播放视频 — 左键双击应全屏、滚轮应调音量（与改动前完全一致，因为默认配置无 MBTN/WHEEL 绑定，全部走 IINA 兜底逻辑）
3. **自定义 binding 生效**：在 `~/.config/iina/input.conf` 添加 `MBTN_LEFT cycle pause`、`WHEEL_UP add volume 5` 等，重载配置后 — 左键单击应暂停、滚轮应以 5 步进调音量
4. **DBL 绑定但无 LEFT 绑定时单击不被吞**：配置 `MBTN_LEFT_DBL cycle fullscreen`（不配 `MBTN_LEFT`），单击应执行 IINA 偏好中的单击动作（如暂停/隐藏 OSC），双击应全屏
5. **Trackpad 精确控制不变**：用触控板滑动 — 仍有连续精确的 IINA 原有 delta 系数控制（不走 mpv binding）
6. **偏好 UI 清理**：打开偏好设置 → Control 页面，"Mouse" 区段应仅显示 "Accepts first mouse click" 和 "Seek type:"，无单击/双击/滚轮动作配置
7. **配置切换**：在 Key Binding 设置中切换配置后重载，鼠标行为应随之改变
8. **MiniPlayer 滚轮偏好生效**：在设置中修改纵向滚动动作，MiniPlayer 窗口中的滚轮行为应即时更新（改动前不生效）
9. **otherMouseUp 未知按钮不崩溃**：使用非标准鼠标按钮（buttonNumber > 4）时不应崩溃

---

## 不做的事（与 51b8c5f1 明确区分）

- ❌ 不删除 `relativeSeekAmount`/`volumeScrollAmount`/`playbackSpeedScrollAmount` 属性（滚轮逻辑仍在用）
- ❌ 不删除 `ScrollDirection` 枚举、`scrollDirection`、`wasPlayingBeforeSeeking`（滚轮逻辑需要）
- ❌ 不删除滚轮 trackpad 暂停恢复、MiniPlayer volume popover 等体验优化
- ❌ 不删除 `MouseClickAction`/`ScrollAction` 枚举定义（XIB 引用 + 兜底逻辑仍用）
- ❌ 不修改默认 `iina-default-input.conf`
- ❌ 不修改 `.gitignore`（个人环境无关）
- ❌ 不改键盘快捷键处理逻辑
- ❌ 不路由 `mouseDown` 事件到 mpv binding（见 Part 2.8 已知限制）
