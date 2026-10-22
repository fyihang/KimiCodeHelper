# KimiCodeHelper

一个 macOS 小工具：用 SwiftUI 控制台管理后台运行的 [Kimi Code](https://www.kimi.com/code) Web 服务——启动 / 重启 / 停止、开机自启勾选、启动参数可配置，全程无终端窗口。

A tiny macOS control panel for running `kimi web` as a background service: start / restart / stop, optional login autostart, and editable launch arguments — no terminal window left sitting on your desktop.

## 为什么会有这个项目

我把 Kimi Code 部署在家里的一台 Mac 上，想在外出时通过 **Cloudflare Tunnel** 远程访问它的 Web 界面。但有两个痛点：

1. **不美观**：`kimi web` 只能前台运行并驻留在终端里，桌面一直摆着一个终端窗口。
2. **鉴权不健全**：Kimi Code 处于 RC 阶段，鉴权机制还不够完善。开启远程访问需要 `--dangerous-bypass-auth` 关掉服务本身的鉴权，再把鉴权交给隧道层（如 Cloudflare Access）——这意味着服务必须稳定地跑在后台，而不是挂在某个终端会话里。

于是写了这个 App：它把 `kimi web` 托管给 macOS 的 launchd 在后台运行，自己只做一个启停控制台。

## 功能

- **状态栏**：每秒刷新，显示 运行中 / 已停止、PID、已运行时长、端口、远程地址
- **三个按钮**：启动、重启、停止（按状态自动启用 / 禁用）
- **开机自启**：勾选框控制，勾上即写入 `~/Library/LaunchAgents`，下次登录自动启动
- **启动参数可配置**：例如 `web --dangerous-bypass-auth --allowed-host your-domain.example.com`，保存后重启生效
- **崩溃自动恢复**：服务通过 launchd 托管（`KeepAlive`），异常退出会被自动拉起
- 关闭控制台窗口即退出 App，不影响后台服务

## 环境要求与构建

- macOS 13+
- 已安装 [Kimi Code CLI](https://www.kimi.com/code/docs/en/)（`kimi` 命令可用）
- 系统自带 Swift 工具链（Xcode Command Line Tools）

```bash
git clone https://github.com/fyihang/KimiCodeHelper.git
cd KimiCodeHelper
./Scripts/build.sh
```

构建产物为 `dist/Kimi Web.app`，拖进「应用程序」即可使用。
App 内的 `Contents/Resources/` 附有源码和 `build.sh`，改完界面可原地重新编译。

> 图标未包含在仓库中（版权归 Moonshot AI 所有）。如需 Kimi 风格图标，可自行放置 `icon.icns` 到 `app-template/` 后重新构建。

## 使用说明

| 项目 | 位置 |
| --- | --- |
| 服务配置 / 启动参数 | `~/Library/Application Support/KimiWeb/com.kimi.web.plist` |
| 开机自启 | `~/Library/LaunchAgents/com.kimi.web.plist`（勾选框即创建 / 删除此文件） |
| 服务日志 | `~/.kimi-code/logs/web-launchd.log` |
| launchd Label | `com.kimi.web` |

默认启动参数：`web --dangerous-bypass-auth --allowed-host your-domain.example.com`
（首次启动时自动初始化，请改成你自己的隧道域名。）

## 工作原理

- **启动**：`launchctl bootstrap gui/$UID <plist>` + `kickstart`（未加载时）；已加载则直接 `kickstart`
- **重启**：`bootout` → `bootstrap` → `kickstart`，确保新参数被加载
- **停止**：`bootout`——直接把服务从 launchd 移除，因此不会被 `KeepAlive` 立刻复活（这是它能"停得住"的关键）
- **开机自启**：勾选 = 把 plist 拷进 `~/Library/LaunchAgents`；取消 = 删除。launchd 在登录时自动加载该目录下的 plist（`RunAtLoad`）
- 控制台本身每秒执行 `launchctl print` + `ps` 轮询状态

## ⚠️ 安全提示

`--dangerous-bypass-auth` 会完全关闭 Kimi Code 的鉴权：任何能访问到该端口的人都将获得你机器上的完整会话、文件和 shell 权限。

- **务必**在隧道层加保护：Cloudflare Access（推荐，零信任）、Basic Auth 或 IP 白名单
- 不建议在不可信网络中直接暴露端口
- 远程操作结束后可在控制台一键停止服务

## 免责声明

本项目与 Moonshot AI（月之暗面）无关，亦非官方项目。Kimi Code 及相关商标归 Moonshot AI 所有。

## License

[MIT](LICENSE)
