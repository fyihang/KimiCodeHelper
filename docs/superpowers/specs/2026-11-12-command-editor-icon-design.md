# 自定义运行命令与应用图标设计

## 目标

在现有 SwiftUI 控制台中编辑完整 Kimi Web 启动命令，保持 Terminal + screen 权限路径，并为新 App 添加原创图标。

## 方案比较

- **完整命令文本（已选择）**：符合终端习惯；用明确的 argv 解析器处理引号和反斜线，不经过 shell。
- **每行一个参数**：避免引号解析，但长命令编辑不直观，排除。
- **原创程序化图标（已选择）**：深色圆角终端、`>_` 和绿色状态点；不依赖 Kimi 官方素材，无第三方依赖。

## 命令编辑与保存

- 新增可滚动命令编辑区，从现有 `~/Library/Application Support/KimiWeb/com.kimi.web.plist` 的 `ProgramArguments` 读取并以安全 shell 风格引用展示。
- 解析器支持空白分隔、单/双引号和反斜线转义；拒绝空命令、未闭合引号、悬空白转义和非绝对/不可执行程序路径。解析结果直接成为 argv，不执行 shell 语法、变量展开或命令替换。
- 保存时使用 Foundation plist 序列化，仅修改 `ProgramArguments`，保留其他键；同目录临时文件校验后原子替换。
- 载入时记录 plist 原始数据摘要。保存前重新读取并比较；若外部已修改，则拒绝覆盖并提示重新加载，避免丢失其他并发修改。
- 提供「保存」和「保存并重启」。普通保存不改变运行状态并提示重启后生效；保存并重启先持久化，再通过现有 Terminal 动作层执行 `restart`，沿用 screen+HTTP 就绪与错误报告。
- 编辑期间不被后台刷新覆盖；外部配置变化仅在未编辑时重新载入。配置读取/写入不阻塞主线程。
- 测试使用 `KIMI_WEB_CONFIG` 隔离配置，不修改生产命令。

## 图标与构建

- 提交原创 1024×1024 PNG 源文件 `app-template/icon.png`。
- 构建脚本用系统 `sips` 生成 iconset 所需尺寸，用 `iconutil` 生成 `icon.icns`，复制到 App Resources。
- Info.plist 设置 `CFBundleIconFile=icon` 和 `CFBundleIconName=icon`；版本升级为 1.1/build 2。
- 图标和命令编辑均不改变 Terminal、LaunchAgent、TCC 或服务权限边界。

## 非目标

- 不提供任意 shell 脚本执行、变量展开、自动更新或命令历史管理。
- 不自动修改当前生产运行命令；只有用户点击保存才写入。

## 验证

- 对解析、引用往返、非法输入、空命令、路径校验和 plist 保留字段做一次性 RED/GREEN 验证。
- 隔离验证保存不重启、保存并重启、失败就绪报告和生产配置不变。
- 构建验证 icns、尺寸、Info.plist、签名；安装后通过窗口截图和 Finder/程序库信息确认图标。
- 真实 App 加载当前命令，但不点击保存时不得修改生产 plist。
