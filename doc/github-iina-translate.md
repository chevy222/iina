# 中文翻译更新 (zh-Hans.lproj)

## 提交信息

**提交**: `e5522fa7` (2026-08-09, "mvp.input and translate")
**作者**: 杨春伟

## 变更概览

| 文件 | 改动 |
|------|------|
| `Localizable.strings` | +38 条新翻译, 1 处误翻修正 |
| `MainMenu.strings` | +2 条新翻译, 4 处统一 |
| `MiniPlayerWindowController.strings` | +2 条新翻译 |
| `InspectorWindowController.strings` | +1 条新翻译 |
| `OpenURLWindowController.strings` | 1 处误翻修正 |
| `PrefControlViewController.strings` | 1 处统一, 删除 2 条重复 |
| `PrefSubViewController.strings` | 2 处格式修正 |
| `AboutWindowController.strings` | 1 条新翻译 |

## 新增翻译 (38 条)

### Localizable.strings

**侧边栏 (14 条)**:
- `sidebar.layout` = 布局
- `sidebar.hue` = 色调
- `sidebar.delay` = 延迟
- `sidebar.eq` = 均衡器
- `sidebar.primary` = 主要
- `sidebar.secondary` = 次要
- `sidebar.external_subtitles` = 外挂字幕
- `sidebar.position` = 位置
- `sidebar.scale` = 缩放
- `sidebar.color` = 颜色
- `sidebar.text` = 文字
- `sidebar.background` = 背景
- `sidebar.sub_settings_not_available` = 此字幕类型的部分设置不可用。
- `sidebar.plugins_placeholder` = 插件可显示自定义侧边栏内容。选择一个插件以查看其侧边栏，或在设置中安装新插件。

**历史窗口 (11 条)**:
- `history_window.col.filename` = 媒体
- `history_window.menu.delete_file` = 移到废纸篓…
- `history_window.toolbar.group_by` = 分组方式
- `history_window.toolbar.group_by.menu` = 分组方式
- `history_window.toolbar.group_by.date_tooltip` = 按日期排序
- `history_window.toolbar.group_by.location` = 文件夹与网站
- `history_window.toolbar.group_by.location_tooltip` = 按文件夹与网站排序
- `history_window.toolbar.expand_collapse` = 展开/折叠
- `history_window.toolbar.expand_all` = 全部展开
- `history_window.toolbar.collapse_all` = 全部折叠
- `history_window.search.full_path` = 完整路径

**日志窗口 (8 条)**:
- `logwindow.all_subsystems` = 所有子系统
- `logwindow.now` = 当前
- `logwindow.now.desc` = 跟踪最新日志
- `logwindow.log_level` = 日志级别
- `logwindow.save_filtered` = 筛选保存日志…
- `logwindow.filter` = 筛选
- `logwindow.clear_subsystem_selections` = 清除选择
- `logwindow.logs` = 日志

**OSD 与弹窗 (5 条)**:
- `osd.sub_quota_exceeded` = 已达到字幕下载上限
- `osd.sub_quota_exceeded.detail` = 请在 %@ 后重试
- `osd.sub_quota_exceeded.detail_unknown` = 请稍后重试
- `preference.ui` = 界面
- `preference.video_audio` = 视频与音频

**播放列表/OSC/设置 (5 条)**:
- `pl_menu.subtitles` = 字幕（已加载 %d 个）
- `pl_menu.network_resources` = 网络资源
- `pl_menu.file_operations` = 文件操作
- `osc_toolbar.live_text` = 切换实时文本
- `settings.autoSearchOnlineSub.desc` = 启用后，IINA 只会为未加载字幕且长度超过 20 分钟的视频自动搜索在线字幕。

**弹窗消息 (5 条)**:
- `alert.delete_keybindingset.title` = 删除按键绑定集
- `alert.delete_keybindingset.message` = 确定要删除此按键绑定集吗？
- `alert.extra_option.error` = 设置选项 --%@=%@ 时出错，返回值 %d。请检查"设置 > 高级"中的额外选项。
- `alert.delete_file.title` = 删除文件
- `alert.delete_file.message` = 确定要将选中的文件移入废纸篓吗？
- `alert.install_plugin_macos_11.title` = 从 GitHub 安装插件
- `alert.install_plugin_macos_11.message` = 使用 user/repo 格式或输入完整 GitHub URL。插件商店在 macOS 11 上不可用，推荐使用更新的系统以获得最佳体验。

### MainMenu.strings (2 条新增)
- `Saz-zT-RXt.title` = 锁定窗口宽高比
- `lq9-av-Um9.title` = 实时文本

### MiniPlayerWindowController.strings (2 条)
- `F4P-Wj-5qw.ibShadowedToolTip` = 关闭窗口
- `hZH-NM-Lst.ibShadowedToolTip` = 关闭窗口

### InspectorWindowController.strings (1 条)
- `O4m-5f-4hM.title` = 注释：

### AboutWindowController.strings (1 条)
- `F0z-JX-Cv5.title` = 关于

## 修正与统一

### 误翻修正 (2 处)

| 文件 | Key | 原值 | 修正 |
|------|-----|------|------|
| `Localizable.strings` | `settings.rightClickAction.desc` | 中键单击时 | 右键单击时 |
| `OpenURLWindowController.strings` | `zbf-uh-uGz.title` | 停止加载 | 打开 |

### 翻译统一 (6 处)

| 文件 | 统一内容 |
|------|----------|
| `MainMenu.strings` | "Saved Video Filters" 统一为 "已保存的视频滤镜" |
| `MainMenu.strings` | "Playback" 菜单统一为 "播放" |
| `MainMenu.strings` | "Open URL…" 统一为 "打开 URL…"（空格） |
| `PrefControlViewController.strings` | "Seek" 统一为 "跳转" |
| `PrefSubViewController.strings` | "Y:" / " X:" 冒号统一为全角 "Y：" / " X：" |

### 重复清理 (2 处)

| 文件 | 删除的重复 Key |
|------|----------------|
| `PrefControlViewController.strings` | `XXq-G1-9sl.title` (第 80 行) |
| `PrefControlViewController.strings` | `nJZ-9M-DHk.title` (第 131 行) |

## 保留不翻译

以下术语保持英文：
- 品牌/技术术语：HDR, MB, OSD, PNG, WebP, Box, X, Y
- 格式占位符：`%@`, `user/repo`, `{{property}}`
- 窗口标题：InspectorWindowController 中的 "Comment:" 已翻译为 "注释："
