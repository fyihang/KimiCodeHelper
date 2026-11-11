# Kimi Web GUI Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建并安装新的 SwiftUI 控制台，通过 Terminal 管理现有 screen 服务并支持显式 `kimi update -y` 更新。

**Architecture:** AppleScript 动作层负责所有 Terminal 操作、就绪检查、持久任务状态和日志；SwiftUI 只读取状态并异步调用动作层。构建脚本把管理脚本和动作层打包进 App Resources，避免控制台依赖 iCloud 项目路径。

**Tech Stack:** SwiftUI、Foundation、AppleScript、Bash、macOS Terminal/screen/launchd

**Spec:** `docs/superpowers/specs/2026-11-11-gui-console-design.md`

## Global Constraints

- 所有服务动作和更新均由 Terminal 执行；GUI 不得直接托管服务或要求完全磁盘访问。
- 生产使用 `kimi-web`、现有配置、`~/.kimi-code/bin/kimi`、端口 58627；测试必须使用环境覆盖隔离。
- 就绪同时要求 screen 存在和 Web HTTP 可达，超时 30 秒；更新成功与服务恢复失败分别报告。
- 更新失败只尝试恢复服务，不承诺二进制回滚。
- 不修改现有登录 LaunchAgent、TCC 或旧 `com.kimi.web`。
- 无第三方依赖或测试框架；使用一次性验证，不新增测试文件。

## Review Focus

- 环境覆盖必须贯穿 GUI → AppleScript → Terminal → 管理脚本：Task 1/2 用非默认隔离值验证。
- Terminal 焦点变化不得导致误关旧窗口：Task 1 验证返回 tab/TTY 对应窗口身份。
- 更新失败与恢复失败必须分别呈现：Task 1 用替身覆盖更新失败、恢复成功和恢复失败。
- App 退出不能取消 Terminal 任务或重复执行：Task 1/2 验证持久状态与重开恢复。
- 并发点击/多个实例不得重复更新：Task 1 验证持久锁，Task 2 验证按钮禁用。

---

### Task 1: Terminal 动作层与持久任务

**Files:**
- Create: `Scripts/console-action.applescript`

**Interfaces:**
- Produces: `/usr/bin/osascript Scripts/console-action.applescript start|stop|restart|update|attach`
- Consumes: 现有 `Scripts/kimi-web.sh`；支持 `KIMI_WEB_SCREEN_SESSION`、`KIMI_WEB_CONFIG`、`KIMI_WEB_URL`、`KIMI_WEB_KIMI_BIN`。
- 状态与日志写入 `$HOME/Library/Logs/KimiWeb/`；生产更新命令精确为 `<kimi-bin> update -y`。

- [ ] **Step 1: 建立隔离失败基线**
  在临时环境运行不存在的动作脚本，确认失败；准备替身配置、URL 和 `kimi` 命令，确保不触碰生产会话。

- [ ] **Step 2: 实现 Terminal 动作与窗口安全**
  通过 Terminal 执行动作；使用返回 tab 的唯一 TTY 确定新建窗口，禁止读取 `front window` 作为关闭目标。启动/重启要求 screen+HTTP 就绪，停止要求进程消失，失败保留诊断窗口。

- [ ] **Step 3: 实现更新与持久状态**
  记录原运行状态，更新前按需停止；成功自动启动，失败仅在原运行时尝试启动残留二进制。用原子状态文件和排他锁记录 running/succeeded/failed，日志落盘，App 退出后任务继续。

- [ ] **Step 4: 隔离验证**
  编译 AppleScript，覆盖启动幂等、重启、停止、Web 不就绪超时、窗口保护、更新成功自动启动、更新失败恢复/恢复失败、重复任务拒绝和状态恢复。不得执行真实更新或控制生产会话。

### Task 2: SwiftUI 控制台

**Files:**
- Create: `Sources/main.swift`
- Create: `Sources/ConsoleController.swift`
- Create: `Sources/ContentView.swift`

**Interfaces:**
- Consumes: Task 1 动作接口和 `$HOME/Library/Logs/KimiWeb/` 状态/日志。
- Produces: 状态/PID/版本/Web 显示，启动/重启/停止/打开 Web/接回/更新按钮及更新输出。

- [ ] **Step 1: 实现只读状态模型**
  使用 `/usr/bin/screen`、进程查询、`kimi --version` 和 HTTP 请求刷新状态；环境覆盖与 Task 1 一致，不读取 iCloud 项目文件。

- [ ] **Step 2: 实现异步控制器**
  用 `Process` 调用打包的 `console-action.applescript`，避免阻塞主线程；操作期间禁用按钮，启动时读取持久任务状态并恢复展示，不重复执行。

- [ ] **Step 3: 实现 SwiftUI 视图**
  紧凑窗口显示状态、PID、版本、Web、操作按钮、确认更新提示和可滚动日志；关闭窗口退出 App 但不影响 Terminal 任务或服务。

- [ ] **Step 4: 编译与隔离行为检查**
  用 `swiftc -parse-as-library` 编译全部源码；通过隔离环境验证状态展示、按钮动作、任务恢复和并发禁用，不操作生产服务。

### Task 3: 打包、安装、文档与真实验收

**Files:**
- Create: `Scripts/build.sh`
- Create: `app-template/Info.plist`
- Modify: `README.md`

**Interfaces:**
- Produces: `dist/Kimi Web.app`，bundle id `com.kimi.web.console`，Resources 包含 `kimi-web.sh` 和 `console-action.applescript`。

- [ ] **Step 1: 实现可重复构建**
  校验依赖，清理并重建 App，编译 Swift 源码、复制资源、写入 Info.plist；构建产物保持在 `dist/`。

- [ ] **Step 2: 更新文档**
  说明 GUI 与 Terminal 权限边界、安装路径、更新停机、日志、恢复语义和安全警告，不恢复旧 GUI 直启说明。

- [ ] **Step 3: 静态和隔离验收**
  运行 Shell/AppleScript 语法、Swift 构建、plist lint、Resources 检查和隔离端到端场景；确认 git status 无临时产物。

- [ ] **Step 4: 安装并验证真实控制台**
  用新构建替换 `/Applications/Kimi Web.app`，启动 App，验证真实状态、打开 Web 和服务按钮。

- [ ] **Step 5: 真实更新验收**
  通过新控制台动作执行一次真实 `kimi update -y`；确认更新输出、自动重启、Web HTTP 200、screen 存活和 Terminal 无残留成功窗口。若当前远程会话中断，重连后复核。
