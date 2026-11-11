# Terminal + screen 无窗口自启方案

## 目标

继续使用 Terminal 的完全磁盘访问权限，同时让 Kimi Web 在没有终端窗口的情况下运行，并在用户登录后自动启动。替代当前由 launchd 直接启动 `kimi` 的权限路径。

## 方案比较

- **Terminal + screen（已选择）**：登录启动器唤起 Terminal，由 Terminal 内的 shell 创建 detached `screen` 会话，然后关闭新建窗口。Terminal 应用保持后台运行，Kimi Web 在 screen 会话中运行。
- **稳定签名的 launchd 服务**：后台管理更直接，但权限授予专用服务而非 Terminal，不符合本次选择。
- **直接 launchd 启动 `kimi`**：已产生 iCloud 目录 `EPERM`，排除。
- **`nohup`/普通后台任务**：缺少稳定的会话管理、接回终端和崩溃恢复能力，不采用。

## 实现设计

- 使用系统已有 `/usr/bin/screen`，不新增依赖。
- 新增终端服务脚本，以固定会话名启动、停止、重启和查询 Kimi Web；保留当前 Web 启动参数与远程访问用途。
- 服务脚本在 screen 会话中运行，异常退出后延迟重试；停止脚本显式结束会话，避免自动复活。
- 新增登录 LaunchAgent，通过 AppleScript 指示 Terminal 创建 detached screen 会话；确认会话建立后，仅关闭本次创建的 Terminal 窗口，不退出 Terminal 应用。
- 停用并移除旧 `com.kimi.web` 服务和 LaunchAgent，避免双实例；新启动器使用独立 label。
- 删除 SwiftUI 控制台、App 模板和 App 构建脚本，README 改为无窗口终端方案、日常命令、授权步骤和安全说明。

## 权限与限制

- 在 macOS「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中启用 Terminal，并按系统提示重启 Terminal。
- Terminal 应用需要保持后台运行，但不保留窗口；不要完全退出 Terminal。
- 自启在用户登录后发生，不是登录前的系统守护进程。
- 不直接修改 TCC 数据库，不绕过 SIP。
- `--dangerous-bypass-auth` 的安全风险保持不变，仍需隧道层鉴权。

## 验证

1. 先用临时 screen 会话验证：从 Terminal 启动后关闭窗口，进程仍存活，并可读取 iCloud 工作区。
2. 实施脚本后验证启动、接回、停止、重启和异常退出恢复。
3. 验证旧 launchd 服务已卸载、旧自启 plist 已移除，新登录启动器可建立无窗口会话。
4. 由用户执行一次注销重登或重启，确认自动启动和 iCloud 访问仍正常，日志不再出现对应 `EPERM`。
