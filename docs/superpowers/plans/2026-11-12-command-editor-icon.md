# Command Editor and App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为现有控制台增加安全的完整运行命令编辑/保存/重启功能，并打包原创应用图标。

**Architecture:** 独立 Swift 解析器和配置存储负责 argv 往返、校验、冲突检测与原子 plist 保存；现有控制器调用它们并复用 Terminal 动作层重启。图标使用提交的 1024×1024 PNG，由系统工具生成 icns。

**Tech Stack:** SwiftUI、Foundation PropertyListSerialization、Bash、AppKit/CoreGraphics（一次性图标生成）、sips、iconutil

**Spec:** `docs/superpowers/specs/2026-11-12-command-editor-icon-design.md`

## Global Constraints

- 命令只解析为 argv，不经过 shell，不展开变量或命令替换。
- 仅修改 `ProgramArguments`，原子保存并检测外部配置冲突。
- 重启继续使用 Terminal 动作层，不改变 Terminal/LaunchAgent/TCC 权限边界。
- 测试用 `KIMI_WEB_CONFIG` 和临时目录隔离；不得自动修改生产 plist。
- 无第三方依赖或测试框架；一次性 RED/GREEN 检查，不新增测试文件。

## Review Focus

- 引号、反斜线、空参数和非法输入不能错误执行或损坏配置：Task 1 覆盖解析往返和失败 RED/GREEN。
- 外部修改不得被静默覆盖：Task 1 验证摘要冲突拒绝保存。
- 保存与保存并重启必须区分：Task 1 验证普通保存无动作，后者才调用 restart。
- 编辑中后台刷新不得覆盖草稿：Task 1 验证 dirty 状态。
- 图标必须进入构建产物且清晰可辨认：Task 2 检查全部尺寸、plist、签名和安装后视觉。

---

### Task 1: 命令解析、配置存储与编辑界面

**Files:**
- Create: `Sources/CommandLine.swift`
- Create: `Sources/CommandConfiguration.swift`
- Modify: `Sources/ConsoleController.swift`
- Modify: `Sources/ContentView.swift`

**Interfaces:**
- Produces: argv 解析/安全引用、`ProgramArguments` 载入/保存、草稿 dirty 状态、`saveCommand()` 与 `saveCommandAndRestart()`。
- Consumes: 现有 `ConsoleConfiguration.configPath` 和 Terminal `restart` 动作。

- [ ] **Step 1: 建立一次性失败检查**
  用独立临时 plist 和 Swift harness 覆盖：普通参数、单/双引号、反斜线、空参数、未闭合引号、空命令、非法程序路径；确认实现前检查失败。

- [ ] **Step 2: 实现解析和配置存储**
  完整命令与 argv 双向转换；拒绝 shell 特殊语义展开。存储载入原始摘要，保存前检测外部变化，使用 PropertyListSerialization 和原子替换保留其他键。

- [ ] **Step 3: 接入控制器与视图**
  异步载入/保存；编辑时设置 dirty 并不被刷新覆盖。提供完整命令编辑区、保存、保存并重启、重新加载和明确错误；保存并重启先保存再调用现有 Terminal restart。

- [ ] **Step 4: 隔离验收**
  验证解析往返、非法输入、原子保存、其他键保留、冲突拒绝、普通保存不重启、保存并重启、dirty 草稿保护；生产 plist 摘要保持不变。提交更改。

### Task 2: 原创图标、构建与安装验收

**Files:**
- Create: `app-template/icon.png`
- Modify: `Scripts/build.sh`
- Modify: `app-template/Info.plist`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 的完整源码。
- Produces: 含 `Contents/Resources/icon.icns` 的 `dist/Kimi Web.app` 和安装后的 `/Applications/Kimi Web.app`。

- [ ] **Step 1: 生成原创图标源文件**
  用 AppKit/CoreGraphics 一次性绘制 1024×1024 深色圆角终端、`>_` 和绿色状态点；读取生成图确认清晰，无官方素材或依赖。

- [ ] **Step 2: 接入可重复构建**
  用 sips 生成标准 iconset 尺寸、iconutil 生成 icns；Info.plist 设置 `CFBundleIconFile`/`CFBundleIconName` 为 `icon`，版本 1.1/build 2；README 补充命令编辑、冲突处理和图标说明。

- [ ] **Step 3: 构建和静态验收**
  运行完整构建、Shell/AppleScript 语法、plist lint、签名、图标尺寸/资源和生产 plist 不变检查；清理临时生成物并提交。

- [ ] **Step 4: 安装与视觉验收**
  替换并启动 `/Applications/Kimi Web.app`，通过真实窗口截图确认命令编辑区和图标；验证当前命令载入、服务 HTTP 200、Terminal 无残留窗口。不点击生产保存按钮。
