# Plan: zh-Hans.lproj 翻译补全与清理

## Context

对 `iina/zh-Hans.lproj/` 翻译文件的全面审计。原 translate 分支的提交 `ac716d63`（"更新翻译"，2026-03-25）已被撤销，当前工作区与官方 `origin/develop`（HEAD = `c5dccbc8`）完全一致。需要在官方最新代码基础上重新补全中文翻译，同时清理重复和不一致条目。

经与 `origin/develop` 分支比对确认：`zh-Hans.lproj/` 目录无任何本地未提交的修改，所有未翻译项均为官方新增/未覆盖的字符串。

**处理范围**：纯 .strings 资源文件修改，不涉及代码逻辑变更。品牌/缩写术语（HDR、MB、PNG、WebP 等）和格式占位符（%、user/repo）属于保留项，不翻译。

---

## Part 1: 补全未翻译字符串（约 57 条）

按优先级排列，集中处理自然语言标签和句子。

### 1.1 Localizable.strings — 重点（约 52 条）

**侧边栏 sidebar.\*（约 14 条）**：

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `sidebar.layout` | 546 | Layout | 布局 |
| `sidebar.hue` | 563 | Hue | 色调 |
| `sidebar.delay` | 566 | Delay | 延迟 |
| `sidebar.eq` | 568 | Equalizer | 均衡器 |
| `sidebar.primary` | 574 | Primary | 主要 |
| `sidebar.secondary` | 575 | Secondary | 次要 |
| `sidebar.external_subtitles` | 576 | External Subtitles | 外挂字幕 |
| `sidebar.position` | 579 | Position | 位置 |
| `sidebar.scale` | 580 | Scale | 缩放 |
| `sidebar.color` | 582 | Color | 颜色 |
| `sidebar.text` | 583 | Text | 文字 |
| `sidebar.background` | 585 | Background | 背景 |
| `sidebar.sub_settings_not_available` | 586 | Some settings are not available for this subtitle type. | 此字幕类型的部分设置不可用。 |
| `sidebar.plugins_placeholder` | 592 | Plugins can display custom sidebar contents. Select a plugin to view its sidebar or install a new plugin in Settings. | 插件可显示自定义侧边栏内容。选择一个插件以查看其侧边栏，或在设置中安装新插件。 |

**历史窗口 history_window.\*（约 12 条）**：

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `history_window.col.filename` | 519 | Media | 媒体 |
| `history_window.menu.delete_file` | 526 | Move to Trash… | 移到废纸篓… |
| `history_window.toolbar.group_by` | 528 | Group By | 分组方式 |
| `history_window.toolbar.group_by.menu` | 529 | Group by | 分组方式 |
| `history_window.toolbar.group_by.date_tooltip` | 531 | Sort by Date | 按日期排序 |
| `history_window.toolbar.group_by.location` | 532 | Folder and Website | 文件夹与网站 |
| `history_window.toolbar.group_by.location_tooltip` | 533 | Sort by Folder and Website | 按文件夹与网站排序 |
| `history_window.toolbar.expand_collapse` | 534 | Expand/Collapse | 展开/折叠 |
| `history_window.toolbar.expand_all` | 535 | Expand All | 全部展开 |
| `history_window.toolbar.collapse_all` | 536 | Collapse All | 全部折叠 |
| `history_window.search.full_path` | 539 | Full Path | 完整路径 |

**日志窗口 logwindow.\*（约 8 条）**：

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `logwindow.all_subsystems` | 502 | All subsystems | 所有子系统 |
| `logwindow.now` | 507 | Now | 当前 |
| `logwindow.now.desc` | 508 | Follow latest logs | 跟踪最新日志 |
| `logwindow.log_level` | 509 | Log level | 日志级别 |
| `logwindow.save_filtered` | 511 | Save filtered logs… | 筛选保存日志… |
| `logwindow.filter` | 512 | Filter | 筛选 |
| `logwindow.clear_subsystem_selections` | 513 | Clear Selections | 清除选择 |
| `logwindow.logs` | 515 | logs | 日志 |

**OSD 下载配额 + 文件/插件弹窗（约 9 条）**：

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `osd.sub_quota_exceeded` | 143 | Subtitle download limit reached | 已达到字幕下载上限 |
| `osd.sub_quota_exceeded.detail` | 144 | Try again after %@ | 请在 %@ 后重试 |
| `osd.sub_quota_exceeded.detail_unknown` | 145 | Try again later | 请稍后重试 |
| `preference.ui` | 154 | Interface | 界面 |
| `preference.video_audio` | 155 | Video & Audio | 视频与音频 |
| `alert.delete_keybindingset.title` | 288 | Delete Key Binding Set | 删除按键绑定集 |
| `alert.delete_keybindingset.message` | 289 | Are you sure to delete this key binding set? | 确定要删除此按键绑定集吗？ |
| `alert.extra_option.error` | 294 | Error setting option --%@=%@ with return value %d. Please check your extra option settings in Settings > Advanced. | 设置选项 --%@=%@ 时出错，返回值 %d。请检查“设置 > 高级”中的额外选项。 |
| `alert.delete_file.title` | 331 | Delete File | 删除文件 |
| `alert.delete_file.message` | 332 | Are you sure to trash the selected files? | 确定要将选中的文件移入废纸篓吗？ |
| `alert.install_plugin_macos_11.title` | 378 | Install plugin from GitHub | 从 GitHub 安装插件 |
| `alert.install_plugin_macos_11.message` | 379 | Use the format user/repo or enter the full GitHub URL. The plugin store is not available on macOS 11. A newer system is recommended for the best experience. | 使用 user/repo 格式或输入完整 GitHub URL。插件商店在 macOS 11 上不可用，推荐使用更新的系统以获得最佳体验。 |

**播放列表/OSC/设置描述（约 5 条）**：

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `pl_menu.subtitles` | 408 | Subtitles (%d loaded) | 字幕（已加载 %d 个） |
| `pl_menu.network_resources` | 409 | Network Resources | 网络资源 |
| `pl_menu.file_operations` | 410 | File Operations | 文件操作 |
| `osc_toolbar.live_text` | 438 | Toggle Live Text | 切换实时文本 |
| `settings.autoSearchOnlineSub.desc` | 766 | If enabled, IINA will automatically search online subtitles only for videos without loaded subtitles and longer than 20 minutes. | 启用后，IINA 只会为未加载字幕且长度超过 20 分钟的视频自动搜索在线字幕。 |

### 1.2 MainMenu.strings（2 条）

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `Saz-zT-RXt.title` | 482 | Lock Window Aspect Ratio | 锁定窗口宽高比 |
| `lq9-av-Um9.title` | 485 | Live Text | 实时文本 |

### 1.3 MiniPlayerWindowController.strings（2 条）

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `F4P-Wj-5qw.ibShadowedToolTip` | 2 | Close window | 关闭窗口 |
| `hZH-NM-Lst.ibShadowedToolTip` | 11 | Close window | 关闭窗口 |

### 1.4 InspectorWindowController.strings（1 条）

| Key | 行号 | 英文 | 翻译 |
|-----|------|------|------|
| `O4m-5f-4hM.title` | 71 | Comment: | 注释： |

---

## Part 2: 清理重复键

**文件**: `iina/zh-Hans.lproj/PrefControlViewController.strings`

删除以下重复行（每对只保留一处）：

| 重复 Key | 所在行 | 翻译内容 |
|----------|--------|----------|
| `XXq-G1-9sl.title` | 第 80 行 和 第 86 行 | 调整播放速度 |
| `nJZ-9M-DHk.title` | 第 131 行 和 第 161 行 | 调整播放速度 |

操作：删除第 80-85 行块或第 86-91 行块中的一组（保留靠近文件顶部的那组），以及第 131 行块或第 161 行块中的一组。

---

## Part 3: 修正误翻

### 3.1 Localizable.strings — rightClickAction.desc 误翻

| Key | 行号 | 当前值 | 修正为 | 说明 |
|-----|------|--------|--------|------|
| `settings.rightClickAction.desc` | 717 | `中键单击时` | `右键单击时` | Key 是 `rightClickAction`，但值误翻为"中键单击时"（middle click），应修正为"右键单击时" |

### 3.2 OpenURLWindowController.strings — 按钮标题误翻

| Key | 行号 | 当前值 | 修正为 | 说明 |
|-----|------|--------|--------|------|
| `zbf-uh-uGz.title` | 29 | `停止加载` | `打开` | 按钮英文标题为 "Open"，应译为"打开"；"停止加载"可能是加载状态下的动态标题误存 |

---

## Part 4: 统一不一致翻译

### 4.1 MainMenu.strings（样式统一）

| 英文 | 当前翻译 A | 当前翻译 B | 统一为 |
|------|-----------|-----------|--------|
| Open URL… | `打开 URL…` (行 8) | `打开URL…` (行 518) | `打开 URL…` （保持省略号前空格） |
| Playback (NSMenu) | `回放` (行 146) | `播放` (行 383) | 可保留差异（顶层菜单 vs 子项语义不同），但建议统一为 `播放` |
| Saved Video Filters | `已保存视频滤镜` (行 95) | `保存的视频滤镜` (行 500) | `已保存的视频滤镜` |

### 4.2 PrefSubViewController.strings（冒号格式统一）

| 英文 | Key | 当前翻译 | 行号 | 统一为 |
|------|-----|----------|------|--------|
| Y: | `ALz-LB-8sf.title` | `Y:` 半角冒号 | 35 | `Y：` 全角 |
| Y: | `xGf-fF-4Hx.title` | `Y：` 全角冒号 | 161 | `Y：` 全角（已正确） |
| " X:" | `CdS-9J-f2h.title` | ` X:` 半角冒号 | 47 | ` X：` 全角 |
| " X:" | `l7l-ZO-W79.title` | ` X：` 全角冒号 | 128 | ` X：` 全角（已正确） |
| Size: | `Vbl-Im-3UI.title` | `字号:` | 80 | 建议保留差异（字号=字体大小，大小=通用尺寸）；如不需要区分，统一为 `大小:` |
| Size: | `gkc-qt-sD9.title` | `大小:` | 119 | 同上 |

实际需要修改的：仅 `ALz-LB-8sf.title`（行 35）和 `CdS-9J-f2h.title`（行 47）两处，将半角冒号改为全角冒号。

### 4.3 PrefControlViewController.strings（Seek 译法统一）

| 英文 | Key | 当前翻译 | 行号 | 统一为 |
|------|-----|----------|------|--------|
| Seek | `RCe-3m-q9N.title` | `查找` | 71 | `跳转` |
| Seek | `wcS-tP-wav.title` | `跳转` | 155 | `跳转`（已正确） |

实际需要修改的：仅 `RCe-3m-q9N.title`（行 71），将 "查找" 改为 "跳转"。

---

## Part 5: AboutWindowController.strings — 窗口标题翻译

| Key | 行号 | 当前值 | 翻译为 | 说明 |
|-----|------|--------|--------|------|
| `F0z-JX-Cv5.title` | 2 | `About` | `关于` | 窗口标题不译不符合中文习惯；InspectorWindowController.strings 中同 ObjectID `F0z-JX-Cv5` 已译为"检查器"，此处应译为"关于" |

---

## Part 6: 保留不翻译的项

以下 ASCII 值为品牌名、技术术语、格式占位符，**不应翻译**：

- `KeyBinding.strings`：`%`、`{{property}} {{value}}` 等模板记号
- `InitialWindowController.strings`：HTML 链接模板
- `Localizable.strings`：`HDR`、`MB`、`OSD`、`Box`、`X`、`Y`、`No Title`（行 21）
- `PrefUIViewController.strings`：`MB`、`OSD:`
- `PrefGeneralViewController.strings`：`PNG`、`/path/to/screenshot/folder`
- `PrefUtilsViewController.strings`：`Firefox`、`Chrome`
- `PrefPluginViewController.strings`：`user/repo`（占位符）

---

## 关键文件清单

| 文件 | 改动类型 |
|------|----------|
| `iina/zh-Hans.lproj/Localizable.strings` | 修改：新增约 52 条翻译 + 修正 1 处误翻（`rightClickAction.desc`） |
| `iina/zh-Hans.lproj/MainMenu.strings` | 修改：新增 2 条 + 统一 3 处不一致 |
| `iina/zh-Hans.lproj/MiniPlayerWindowController.strings` | 修改：新增 2 条 |
| `iina/zh-Hans.lproj/InspectorWindowController.strings` | 修改：新增 1 条 |
| `iina/zh-Hans.lproj/PrefControlViewController.strings` | 修改：删除重复行(80/86, 131/161) + 统一 1 处不一致（Seek → 跳转） |
| `iina/zh-Hans.lproj/PrefSubViewController.strings` | 修改：统一 2 处半角冒号为全角 |
| `iina/zh-Hans.lproj/OpenURLWindowController.strings` | 修改：修正 1 处误翻（停止加载 → 打开） |
| `iina/zh-Hans.lproj/AboutWindowController.strings` | 修改：将 "About" 重新译为"关于" |

---

## 验证

1. **文件格式校验**：每个 `.strings` 文件的每行必须符合 `"KEY" = "VALUE";` 格式；注释行以 `/*` 开头
2. **无重复键**：用 `grep -c "KEY" file.strings` 对每个翻译后的 key 确认唯一
3. **无漏翻**：对整个 `zh-Hans.lproj` 目录重新跑 ASCII-only 值检测，确认无新增英文残留（保留项除外）
4. **误翻修正确认**：确认 `settings.rightClickAction.desc` 值为 "右键单击时" 而非 "中键单击时"
5. **新增翻译确认**：确认 `logwindow.save_filtered` 和 `history_window.menu.delete_file` 已翻译
6. **编译验证**：`xcodebuild -project iina.xcodeproj -scheme IINA build` 不报错（.strings 文件解析错误会导致构建失败）
7. **与 develop 分支无冲突**：`git diff origin/develop` 应仅包含上述翻译文件的修改，无其他文件变动

---

## 不做的事

- ❌ 不改英文源文件或 `.xib` 文件
- ❌ 不改动其他语言目录（zh-Hant、ja、ko 等）
- ❌ 不翻译技术术语/品牌名
- ❌ 不删除已翻译的条目（只清理真正的重复覆盖）
- ❌ 不改动代码逻辑（仅处理 .strings 资源文件）
