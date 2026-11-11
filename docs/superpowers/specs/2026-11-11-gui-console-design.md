# Kimi Web 图形控制台设计

## 背景与目标

旧 SwiftUI 控制台已从「应用程序」移到废纸篓。新控制台用于管理现有 Terminal + detached screen + 登录 LaunchAgent 方案，并提供显式的 Kimi Code 更新按钮。控制台不是服务宿主，不得绕过 Terminal 的完全磁盘访问权限路径。

## 方案比较

- **SwiftUI 控制台（已选择）**：状态、按钮和更新输出展示清晰；复用现有 Swift 工具链，无第三方依赖。
- **AppleScript 弹窗工具**：文件少，但状态轮询、日志展示和错误处理体验较差，排除。
- **GUI 直接运行所有命令**：实现较简单，但会重新引入 GUI/launchd 的 TCC 权限归属问题，排除。

## 功能

- 显示 screen 会话状态、服务 PID、Web 可达性和当前 `kimi --version`。
- 提供启动、重启、停止、打开 Web、接回 Terminal 会话按钮。
- 提供「更新 Kimi Code」按钮，显示确认提示、执行中状态和输出日志。
- 关闭控制台窗口不影响服务；打开控制台也不自动启动服务。

## 配置与测试隔离

- 生产环境固定使用 `kimi-web` 会话、现有配置文件、`~/.kimi-code/bin/kimi` 和 `http://127.0.0.1:58627/`。
- AppleScript 动作与管理脚本共享 `KIMI_WEB_SCREEN_SESSION`、`KIMI_WEB_CONFIG` 覆盖；控制台动作另支持测试用 `KIMI_WEB_URL` 和 `KIMI_WEB_KIMI_BIN` 环境覆盖，确保隔离验证不会操作正式服务或执行真实更新。
- 未设置覆盖时，App 和登录 LaunchAgent 管理同一个生产会话。

## 权限与执行边界

- 服务启动、停止、重启、接回和更新均由 Terminal 执行；GUI 只发起 AppleScript 和读取非敏感状态。
- 启动/管理脚本随 App 放入 `Contents/Resources`，避免 GUI 直接读取 iCloud 项目路径。登录 LaunchAgent 继续使用项目中的脚本，两者通过同一 screen 会话名和配置协同。
- GUI 状态检查只查询 screen、进程、HTTP 和 `kimi --version`，不要求 GUI 获得完全磁盘访问。
- 不修改 TCC，不恢复 `com.kimi.web` 旧 launchd 直启服务，不改变 `com.kimi.web.terminal` 登录启动器。

## 更新流程

1. 用户点击更新并看到确认：将执行 `~/.kimi-code/bin/kimi update -y`，Web 会暂时中断。
2. 记录原运行状态；若正在运行，先通过 Terminal 停止服务。
3. 在新建的 Terminal 窗口中执行更新，输出写入 `~/Library/Logs/KimiWeb/`；GUI 异步等待，不阻塞界面。
4. 更新成功后无论原状态如何均通过 Terminal 启动服务，显示新旧版本。
5. 更新失败时显示日志、保留诊断窗口；若原先正在运行，则尝试通过 Terminal 启动当前残留的 Kimi 可执行文件。**这只是恢复服务尝试，不保证回滚已修改的二进制**；不做安装目录备份或版本回滚。
6. 同一时间只允许一个服务操作或更新任务，使用持久锁防止重复点击和多个控制台实例并发更新。

## 成功判定

- 启动、重启和更新后的自动启动必须同时满足 screen 会话存在和 Web HTTP 可达，最多等待 30 秒；仅脚本退出码为 0 不算服务就绪。
- 更新成功但服务恢复失败时，分别报告「更新成功、服务恢复失败」，保留诊断窗口，不能合并报成全部成功。
- 停止成功以 screen 会话及其服务进程消失为准。

## 界面、任务与错误处理

- 主窗口沿用紧凑控制台风格，操作期间禁用相关按钮。
- 更新输出区域可滚动；启动/停止失败以明显错误消息呈现。
- Terminal 窗口只用于本次动作；成功且服务就绪时按窗口身份关闭，失败时保留。不得关闭用户已有窗口。
- 更新任务将状态和日志持久化。关闭窗口、退出或崩溃不会取消 Terminal 中已开始的操作；重新打开 App 后读取状态并继续显示，不重复启动任务。
- 打开 Web 使用 `http://127.0.0.1:58627/`；接回会话在 Terminal 中执行 `kimi-web.sh attach`，提示 Control-A、D 脱离。

## 构建与安装

- 新增 SwiftUI 源码和构建脚本，生成 `dist/Kimi Web.app`，再复制到 `/Applications/Kimi Web.app`。
- App 使用独立 bundle identifier `com.kimi.web.console`。ad-hoc 签名可以接受，因为 App 不是隐私授权主体。
- README 说明控制台与终端方案的关系、更新停机行为、日志位置及安全警告。

## 非目标

- 不自动检查或执行更新，不更新控制台自身，不提供 Kimi 二进制版本回滚。
- 不修改启动参数编辑器，不新增开机自启切换；现有 LaunchAgent 继续负责自启。
- 不引入第三方依赖或测试框架。

## 验证

- 构建、AppleScript 编译和 plist 校验通过。
- 在不影响正式服务的情况下用隔离会话、配置和 URL 验证控制台启动、停止、重启、就绪超时和窗口保护。
- 用可控的更新命令替身验证成功自动启动、失败日志、恢复服务尝试和 App 重启后的任务状态恢复。
- 安装新 App 后验证真实状态显示、打开 Web 和按钮管理。
- 通过新控制台动作真实执行一次 `kimi update -y`，确认成功自动重启、版本输出和 Web 恢复；若当前会话中断，重连后复核。
