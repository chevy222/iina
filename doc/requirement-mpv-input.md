# 需求文档：鼠标/滚轮事件统一交给 mpv input.conf

> 对应提交：`d837200c`（mvp.input and translate）

## 1. 背景

IINA 原先在 Cocoa 层拦截鼠标按键与滚轮事件，根据"偏好设置 → 控制"中的配置（如"双击全屏""滚轮调音量"）执行动作。该方式与 mpv 的 `input.conf` 键绑定系统并存，配置分散、能力受限。

本需求将鼠标/滚轮事件的处理**统一收敛到 mpv 的 `input.conf`**，用户通过编辑 `input.conf` 文件即可自定义全部鼠标行为，与键盘快捷键的配置方式保持一致。

## 2. 需求目标

### 2.1 鼠标按键事件派发至 mpv 绑定

| 触发事件 | 派发的 mpv 键名 |
|---|---|
| 左键单击（clickCount = 1） | `MBTN_LEFT` |
| 左键双击（clickCount = 2） | `MBTN_LEFT_DBL` |
| 右键 | `MBTN_RIGHT` |
| 中键（buttonNumber = 2） | `MBTN_MID` |
| 前进侧键（buttonNumber = 3） | `MBTN_FORWARD` |
| 后退侧键（buttonNumber = 4） | `MBTN_BACK` |

- 查询 `PlayerCore.keyBindings`，存在绑定则执行对应命令（mpv 命令或 IINA 命令）。
- **无绑定时不执行任何操作**（纯 mpv 模式，无 IINA 兜底逻辑）。
- 移除原先基于偏好设置的单/双击延迟判定（定时器）逻辑，直接按 `clickCount` 区分。

### 2.2 滚轮事件派发至 mpv 绑定

- 仅处理**离散滚轮事件**（`phase.isEmpty`，即传统鼠标滚轮）；触控板连续滚动事件不做派发。
- 根据滚动主方向派发：`WHEEL_UP` / `WHEEL_DOWN` / `WHEEL_LEFT` / `WHEEL_RIGHT`（delta 绝对值较大者为主方向，已考虑自然滚动方向反转）。
- 派发次数按 delta 绝对值取整（至少 1 次），不做平滑插值。
- 移除原先基于偏好设置的滚轮行为（seek / 音量 / 倍速）整套逻辑，包括 seek 时自动暂停/恢复、音量气泡提示等。

### 2.3 移除图形偏好界面中的鼠标/滚轮配置

"偏好设置 → 控制"页面仅保留**触控板**部分，移除以下鼠标相关配置项：

- 单击 / 双击 / 右键 / 中键动作
- 垂直 / 水平滚动动作
- 精确 seek（useExactSeek）
- seek / 倍速 / 音量灵敏度滑块

用户此后直接编辑 `input.conf` 文件完成自定义。

### 2.4 键盘快捷键不受影响

保持现有 IINA 键盘 `keyDown → keyBindings` 处理流程不变。

## 3. 附带改动

### 3.1 简体中文翻译更新

更新 `zh-Hans.lproj` 下的 `.strings` 文件（Localizable、MainMenu、PrefControl 等），与界面文案变更保持同步。

## 4. 非目标（Out of Scope）

- 不修改键盘快捷键处理链路。
- 不为鼠标/滚轮事件提供 IINA 侧的兜底动作（无绑定即无动作）。
- 不在图形界面中提供 `input.conf` 编辑入口（用户手动编辑文件）。

## 5. 影响范围

| 模块 | 影响 |
|---|---|
| `PlayerWindowController.swift` | 鼠标/滚轮事件处理重写，删除旧偏好动作逻辑 |
| `MainWindowController.swift` | 删除滚轮 KVO |
| `SettingsPageControl.swift` | 移除"鼠标"设置区块 |
| `PrefControlViewController.swift` | 设置页仅保留触控板区块 |
| `zh-Hans.lproj/*.strings` | 翻译同步更新 |

## 6. 用户迁移指引

升级后如需恢复原有鼠标行为（例如"双击全屏""滚轮调音量"），需在 mpv 的 `input.conf` 中添加对应绑定，例如：

```
MBTN_LEFT_DBL cycle fullscreen
WHEEL_UP seek 10
WHEEL_DOWN seek -10
```
