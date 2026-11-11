import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ConsoleController

    private var output: String {
        [controller.actionOutput, controller.logText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kimi Web 控制台")
                    .font(.title2.bold())
                Spacer()
                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text("任务执行中")
                        .foregroundStyle(.secondary)
                }
                Button {
                    controller.reloadPersistentTask()
                    controller.reloadLog()
                    controller.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新状态")
                .disabled(controller.isBusy || controller.isRefreshing)
            }

            VStack(alignment: .leading, spacing: 7) {
                statusRow(
                    title: "Screen",
                    value: controller.screenRunning ? "运行中" : "已停止",
                    color: controller.screenRunning ? .green : .secondary
                )
                statusRow(title: "服务 PID", value: controller.servicePID.map(String.init) ?? "—", color: .primary)
                statusRow(title: "Kimi 版本", value: controller.version, color: .primary)
                statusRow(
                    title: "Web",
                    value: controller.webReachable ? "可访问" : "不可访问",
                    color: controller.webReachable ? .green : .secondary
                )
                Text(controller.configuration.webURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("启动") { controller.perform(.start) }
                Button("重启") { controller.perform(.restart) }
                Button("停止", role: .destructive) { controller.perform(.stop) }
            }
            HStack(spacing: 8) {
                Button("打开 Web") { controller.openWeb() }
                Button("接回 Terminal") { controller.perform(.attach) }
                    .help("在 Terminal 中接回；按 Control-A，然后按 D 脱离")
                Button("更新 Kimi Code") { controller.confirmingUpdate = true }
            }
            .disabled(controller.isBusy)

            if let task = controller.persistentTask {
                VStack(alignment: .leading, spacing: 3) {
                    Text("任务：\(task.action) · \(localizedStatus(task.status))")
                        .font(.callout.weight(.medium))
                    if !task.message.isEmpty {
                        Text(task.message)
                            .font(.caption)
                            .foregroundStyle(task.status == .failed ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("动作输出与日志")
                .font(.headline)
            ScrollView {
                Text(output.isEmpty ? "暂无日志。" : output)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(minHeight: 150, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 500)
        .alert("更新 Kimi Code？", isPresented: $controller.confirmingUpdate) {
            Button("取消", role: .cancel) {}
            Button("更新", role: .destructive) { controller.perform(.update) }
        } message: {
            Text("将执行 \(controller.configuration.kimiBinary) update -y，Web 会暂时中断。更新失败只尝试恢复服务，不保证二进制回滚。")
        }
    }

    private func statusRow(title: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func localizedStatus(_ status: PersistentTaskStatus) -> String {
        switch status {
        case .running: return "执行中"
        case .succeeded: return "成功"
        case .failed: return "失败"
        case .unknown: return "未知"
        }
    }
}
