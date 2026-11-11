# Terminal + Screen Autostart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Terminal 授权的 detached screen 会话运行 Kimi Web，实现无终端窗口、登录自启和旧 launchd 服务迁移。

**Architecture:** 一个 Bash 管理脚本负责 Kimi Web 的运行与 screen 会话生命周期；一个 AppleScript 登录启动器只通过 Terminal 创建会话并关闭其临时窗口。LaunchAgent 仅调用 AppleScript，不再直接启动 `kimi`，最终切换由用户在本机 Terminal 执行，避免中断当前由旧服务托管的会话。

**Tech Stack:** Bash、macOS `/usr/bin/screen`、AppleScript、launchd、Terminal

**Spec:** `docs/superpowers/specs/2026-11-11-terminal-screen-autostart-design.md`

## Global Constraints

- 不新增第三方依赖；使用系统已有 `/usr/bin/screen`。
- Terminal 应用保持后台运行，但不保留窗口，不完全退出 Terminal。
- 不直接修改 TCC 数据库，不绕过 SIP。
- 保留 `--dangerous-bypass-auth` 的用途和安全警告。
- 项目没有测试框架，不新增测试文件；使用一次性命令和端到端场景验证。
- 最终旧服务切换由用户在本机 Terminal 执行，避免当前会话随旧服务退出。

## Review Focus

- 重复启动不得建立同名会话：Task 1 用连续两次 `start` 验证幂等性。
- 显式停止不得被运行循环复活：Task 1 用 `stop` 后检查会话和进程。
- 路径包含空格（当前项目位于 iCloud 目录）：Task 1、2 的所有调用使用数组或正确 shell quoting，并直接用真实路径验证。
- 登录启动器不得关闭用户原有 Terminal 窗口：Task 2 只关闭 `do script` 创建的窗口。
- 当前会话依赖旧服务：Task 4 只允许用户在本机 Terminal 执行最终切换。

---

### Task 1: Screen 会话管理脚本

**Files:**
- Create: `Scripts/kimi-web.sh`

**Interfaces:**
- Produces: `Scripts/kimi-web.sh run|start|stop|restart|status|attach`
- `run`：前台运行 Kimi Web，异常退出后等待 5 秒重试。
- `start`：从 Terminal 创建名为 `kimi-web` 的 detached screen 会话；已存在时不重复创建。
- `stop`：显式结束 `kimi-web` 会话；`status` 报告会话状态；`attach` 接回会话。
- `KIMI_WEB_SCREEN_SESSION` 和 `KIMI_WEB_CONFIG` 可覆盖默认会话名和配置路径，仅用于隔离验证。

- [ ] **Step 1: 验证旧启动路径的失败证据**
  运行 `launchctl print gui/$(id -u)/com.kimi.web`，确认 `program` 是 `$HOME/.kimi-code/bin/kimi` 且父服务不是 Terminal；保留现有 `web-launchd.log` 中 iCloud `EPERM` 作为迁移前基线。

- [ ] **Step 2: 先做临时 Terminal + screen 权限实验**
  用户确认 Terminal 已获完全磁盘访问后，从 Terminal 创建独立临时 screen 会话，在其中读取当前 iCloud 工作区；关闭新建窗口后再次读取并确认进程存活。若失败，停止实施并回到方案评估，不修改正式服务。

- [ ] **Step 3: 实现管理脚本**
  使用 Bash 和绝对路径调用 `/usr/bin/screen`；`run` 从现有 `$HOME/Library/Application Support/KimiWeb/com.kimi.web.plist` 读取 `ProgramArguments` 并执行，避免丢失当前参数。所有路径和参数按数组处理；`start` 在创建后确认会话存在，`stop` 后确认会话消失。

- [ ] **Step 4: 验证管理命令而不切换正式服务**
  用 `KIMI_WEB_SCREEN_SESSION` 和指向临时配置（运行 `/bin/sleep 30`）的 `KIMI_WEB_CONFIG` 隔离验证：运行 `bash -n Scripts/kimi-web.sh`，连续两次启动只出现一个会话，状态可见，停止后会话和子进程消失。不得停止正式 `com.kimi.web`。

### Task 2: Terminal 登录启动器

**Files:**
- Create: `Scripts/login-bootstrap.applescript`

**Interfaces:**
- Consumes: Task 1 的 `Scripts/kimi-web.sh start`
- Produces: 可由 `/usr/bin/osascript Scripts/login-bootstrap.applescript` 执行的启动器；成功时存在 `kimi-web` screen 会话且新建 Terminal 窗口关闭。

- [ ] **Step 1: 实现 AppleScript**
  `tell application "Terminal"` 后用 `do script` 调用管理脚本，保存新建窗口引用；轮询确认 `kimi-web` 会话建立后只关闭该窗口，失败时保留窗口显示错误。

- [ ] **Step 2: 验证无窗口启动与权限**
  在 Terminal 已获完全磁盘访问的前提下运行启动器，确认 `screen` 会话和 Kimi 进程存活、原有 Terminal 窗口未被误关、新窗口已关闭；从会话读取当前 iCloud 工作区并检查日志无新增对应 `EPERM`。

### Task 3: 安装、迁移与项目清理

**Files:**
- Create: `Scripts/install.sh`
- Create: `Scripts/uninstall.sh`
- Modify: `README.md`
- Delete: `Sources/main.swift`, `Scripts/build.sh`, `app-template/Info.plist`

**Interfaces:**
- Consumes: Task 1 管理脚本和 Task 2 登录启动器。
- Produces: `install.sh` 生成 `$HOME/Library/LaunchAgents/com.kimi.web.terminal.plist` 并加载；`uninstall.sh` 卸载新启动器并停止 screen 会话。

- [ ] **Step 1: 实现安装与卸载**
  安装脚本用当前 `$HOME` 和项目绝对路径生成 LaunchAgent，label 为 `com.kimi.web.terminal`；先检查 Terminal 授权提示和脚本存在性，再卸载旧 `com.kimi.web`、删除旧 LaunchAgent，加载新启动器并调用一次。卸载只处理新 label 和 screen 会话，不删除用户配置。

- [ ] **Step 2: 更新文档和移除 GUI 代码**
  README 说明安装、启动、停止、接回、卸载、完全磁盘访问授权和 Terminal 不可完全退出；保留安全警告。删除 SwiftUI/App 构建文件，不保留失效的 GUI 使用说明。

- [ ] **Step 3: 静态验证**
  运行 `bash -n Scripts/*.sh`、`plutil -lint` 检查生成 plist、`osascript` 语法检查；确认 `git status` 只包含本方案文件且无构建产物。

### Task 4: 本机切换与端到端验收

**Files:**
- Uses: `Scripts/install.sh`

**Interfaces:**
- Consumes: 已通过 Tasks 1–3 的项目。

- [ ] **Step 1: 用户授权 Terminal**
  在系统设置中启用 Terminal 的完全磁盘访问，按提示重启 Terminal；不要退出由 screen 使用的 Terminal 应用。

- [ ] **Step 2: 用户在本机 Terminal 执行最终切换**
  运行 `./Scripts/install.sh`。预期旧 `com.kimi.web` 消失，新 `com.kimi.web.terminal` 已加载，Kimi Web 地址可访问，Terminal 无新增驻留窗口。

- [ ] **Step 3: 验证会话管理和 iCloud 权限**
  执行 `Scripts/kimi-web.sh status`、读取 iCloud 工作区并发起一次真实 Kimi 操作；确认无新增 `EPERM`，`stop` 可停止且 `start` 可恢复。

- [ ] **Step 4: 用户注销重登或重启**
  确认登录后自动建立 `kimi-web` 会话、Web 服务可访问、iCloud 权限仍正常；记录结果，若权限未继承则停止并回到方案评估，不叠加绕过性修补。
