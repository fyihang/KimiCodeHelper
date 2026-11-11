# KimiCodeHelper

用 macOS Terminal 和 detached `screen` 会话运行 [Kimi Code](https://www.kimi.com/code) Web 服务。服务在后台持续运行，不保留终端窗口，支持登录后自动启动，并可随时接回会话查看输出。

## 工作原理

`Scripts/kimi-web.sh` 从现有配置读取 `ProgramArguments`，在名为 `kimi-web` 的 `screen` 会话中运行服务；异常退出时等待 5 秒后重试。登录 LaunchAgent 调用 `Scripts/login-bootstrap.applescript`，由 Terminal 创建会话，成功后仅关闭本次新建的窗口。

Terminal 的完全磁盘访问权限因此可以传递给服务，避免直接由 launchd 启动时访问 iCloud 目录出现权限错误。

## 环境要求

- macOS 13 或更高版本
- 已安装 [Kimi Code CLI](https://www.kimi.com/code/docs/en/)
- 系统自带的 Terminal、`/usr/bin/screen` 和 `/usr/bin/osascript`
- 已有服务配置：`~/Library/Application Support/KimiWeb/com.kimi.web.plist`，其中包含 Kimi Web 的 `ProgramArguments`

## 授权 Terminal

1. 打开「系统设置 → 隐私与安全性 → 完全磁盘访问权限」。
2. 为 Terminal 开启权限，并按系统提示完成授权所需的 Terminal 重启。
3. 安装并启动服务后，让 Terminal 保持在后台运行，**不要完全退出 Terminal**；正常运行不需要保留 Terminal 窗口。

本项目不会修改 TCC 数据库，也不会绕过 SIP。

## 图形控制台

控制台只显示状态、读取日志并通过 Terminal 发起服务动作；它不是服务宿主，也不会在打开时自动启动服务。启动、停止、重启、接回和更新都在 Terminal 中执行，因此沿用 Terminal 的完全磁盘访问权限。**不要给 Kimi Web App 开放完全磁盘访问权限**；首次操作时，按 macOS 提示允许 App 控制 Terminal 即可。关闭控制台窗口会退出 App，但不会停止服务，也不会取消 Terminal 中已经开始的任务。

构建并安装到「应用程序」：

```bash
./Scripts/build.sh
/usr/bin/ditto "dist/Kimi Web.app" "/Applications/Kimi Web.app"
open -a "/Applications/Kimi Web.app"
```

构建需要 macOS 自带的 Swift 工具链，不使用第三方依赖。产物为 `dist/Kimi Web.app`，bundle identifier 为 `com.kimi.web.console`；管理脚本和 Terminal 动作层均包含在 App 内，不依赖 iCloud 项目路径。重新安装只会替换控制台 App，不修改登录 LaunchAgent 或现有服务配置。

控制台显示 screen、服务 PID、Kimi 版本和 Web 可达性，并提供启动、重启、停止、打开 Web、接回 Terminal 和更新按钮。打开 Web 使用 `http://127.0.0.1:58627/`；接回后按 `Control-A`，再按 `D` 脱离。

### 更新、日志与恢复

点击「更新 Kimi Code」并确认后，Terminal 会执行 `~/.kimi-code/bin/kimi update -y`。若服务原本正在运行，会先停止服务，**更新期间 Web 会暂时中断**。更新成功后无论原状态如何都会自动启动服务，并在最多 30 秒内同时确认 screen 会话和 HTTP 就绪。更新失败时，仅在服务原本运行的情况下尝试启动当前残留的二进制；这只是服务恢复尝试，**不保证二进制回滚**。

动作状态和输出保存在：

- `~/Library/Logs/KimiWeb/task.state`
- `~/Library/Logs/KimiWeb/console.log`

同一时间只允许一个控制台动作或更新任务。重新打开 App 会读取持久状态并继续显示，不会重复执行已开始的任务。成功的 Terminal 动作窗口会按本次新建窗口的身份关闭；失败窗口会保留供诊断，更新成功但服务恢复失败也会明确报错并保留窗口。控制台不自动检查更新、不更新自身，也不提供版本回滚。

## 安装与迁移

在本机 Terminal 中运行：

```bash
cd /path/to/KimiCodeHelper
./Scripts/install.sh
```

安装器会要求确认 Terminal 已获得完全磁盘访问权限，并检查所需脚本和配置。确认后，它会：

1. 生成并校验 `~/Library/LaunchAgents/com.kimi.web.terminal.plist`。
2. 暂时卸载旧 `com.kimi.web` 服务，加载 label 为 `com.kimi.web.terminal` 的新 LaunchAgent；`RunAtLoad` 会立即调用一次 Terminal 启动器，之后也在每次登录时启动。
3. 确认 `kimi-web` screen 会话实际运行后，才删除旧 `~/Library/LaunchAgents/com.kimi.web.plist`，避免登录时双实例。

如果启动器失败或确认超时，安装器会返回非零状态，卸载并删除新 LaunchAgent，并从保留的旧 plist 恢复旧服务；旧自启配置只会在确认成功后删除。安装会暂时中断旧服务，请在不需要保持现有远程会话时执行。

## 日常管理

```bash
./Scripts/kimi-web.sh start
./Scripts/kimi-web.sh stop
./Scripts/kimi-web.sh restart
./Scripts/kimi-web.sh status
./Scripts/kimi-web.sh attach
```

| 命令 | 作用 |
| --- | --- |
| `start` | 创建 detached `screen` 会话；已运行时不会重复创建 |
| `stop` | 停止会话及其服务进程，不会被运行循环重新拉起 |
| `restart` | 停止后重新启动 |
| `status` | 查询会话是否运行 |
| `attach` | 接回会话查看实时输出 |
| `run` | 前台运行服务并在异常退出后重试；通常由 `start` 内部调用 |

接回后按 `Control-A`，再按 `D`，可离开会话而不停止服务。

## 卸载

```bash
./Scripts/uninstall.sh
```

卸载只卸载并删除新 `com.kimi.web.terminal` LaunchAgent，然后停止 `kimi-web` 会话。它不会操作旧 `com.kimi.web`，也不会删除 `~/Library/Application Support/KimiWeb/com.kimi.web.plist` 或其他用户配置。

## 配置与自启

- 启动参数：`~/Library/Application Support/KimiWeb/com.kimi.web.plist` 中的 `ProgramArguments`
- 新 LaunchAgent：`~/Library/LaunchAgents/com.kimi.web.terminal.plist`
- 新 launchd label：`com.kimi.web.terminal`
- 默认 screen 会话：`kimi-web`

修改启动参数后运行 `./Scripts/kimi-web.sh restart` 使其生效。自启发生在用户登录后，不是登录前的系统守护进程。

## ⚠️ 安全提示

`--dangerous-bypass-auth` 会完全关闭 Kimi Code 的鉴权：任何能访问到该端口的人都将获得你机器上的完整会话、文件和 shell 权限。

- **务必**在隧道层加保护：Cloudflare Access（推荐，零信任）、Basic Auth 或 IP 白名单。
- 不建议在不可信网络中直接暴露端口。
- 远程操作结束后可运行 `./Scripts/kimi-web.sh stop` 停止服务。

## 免责声明

本项目与 Moonshot AI（月之暗面）无关，亦非官方项目。Kimi Code 及相关商标归 Moonshot AI 所有。

## License

[MIT](LICENSE)
