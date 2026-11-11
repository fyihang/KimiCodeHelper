# Terminal 启动方案

## 目标与原因

当前 SwiftUI 控制台通过 launchd 启动 `kimi web`，服务父进程为 launchd，不能继承 Terminal 的完全磁盘访问权限；App 使用 ad-hoc 签名且构建时会被替换，不是稳定的隐私授权主体。日志已出现 iCloud `Mobile Documents` 目录的 `EPERM`。改用 Terminal 前台启动，让 Kimi Code 始终继承 Terminal 的权限，避免 Kimi Code 或助手项目更新后授权失效。

## 方案比较

- **Terminal 前台启动（已选择）**：使用 macOS 自带、Apple 签名的 Terminal 作为固定授权主体；启动脚本直接执行 `kimi web`，Ctrl+C 停止。终端窗口需要保持打开。
- **iTerm 前台启动**：机制相同，但授权主体改为 iTerm；用户已选择 Terminal。
- **保留 launchd 后台服务**：不提供终端的权限继承，不能解决本次根因，因此排除。

## 改动范围

- 新增 `Scripts/start.sh`：定位 `kimi`，沿用现有启动参数，在 Terminal 中以前台方式运行；`Ctrl+C` 停止。
- 提供一次性迁移步骤：停止并卸载 `com.kimi.web` launchd 服务，删除其 LaunchAgent 自启 plist，避免双实例和旧权限路径继续运行。
- 删除 SwiftUI 控制台、App 模板和 App 构建脚本；README 改为终端启动、停止及完全磁盘访问授权说明。
- 在 macOS「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中启用 Terminal，并重启 Terminal 使授权生效。

## 非目标与约束

- 不保留无终端窗口的后台常驻或开机自启。
- 不修改 Kimi Code 本身的权限规则，不直接编辑受 SIP 保护的 TCC 数据库。
- 保留当前 `web --dangerous-bypass-auth --allowed-host ...` 参数及远程访问用途；安全警告继续保留。
- 完全磁盘访问会授予 Terminal 及其子进程较高文件访问权限，只应在用户信任的 Terminal 中运行可信命令。

## 验证

- 启动脚本能在 Terminal 中启动 Kimi Web，Ctrl+C 能停止。
- launchd 中不再存在 `com.kimi.web`，登录自启 plist 已移除。
- Terminal 完全磁盘访问开启并重启后，从同一 Terminal 启动的服务可读取和监听 iCloud 工作区，不再出现对应 `EPERM`。
- 仓库最终只包含终端方案相关文件，无遗留构建产物。
