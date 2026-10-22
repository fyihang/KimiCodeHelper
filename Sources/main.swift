import SwiftUI
import Foundation

let kLabel = "com.kimi.web"
let kKimiBin = NSHomeDirectory() + "/.kimi-code/bin/kimi"
let kConfigDir = NSHomeDirectory() + "/Library/Application Support/KimiWeb"
let kConfigPlist = kConfigDir + "/com.kimi.web.plist"
let kLaunchAgentsPlist = NSHomeDirectory() + "/Library/LaunchAgents/com.kimi.web.plist"
let kDefaultArgs = "web --dangerous-bypass-auth --allowed-host kimi-mac.1h.ac.cn"

enum ServiceState {
    case running, loaded, notLoaded
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (code: Int32, out: String) {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "") }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func splitArgs(_ text: String) -> [String] {
    text.split(separator: " ").map(String.init)
}

func argValue(_ flag: String, in text: String) -> String? {
    let parts = splitArgs(text)
    guard let i = parts.firstIndex(of: flag), i + 1 < parts.count else { return nil }
    return parts[i + 1]
}

func humanizeEtime(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return "—" }
    var days = 0
    if let dash = s.firstIndex(of: "-") {
        days = Int(s[s.startIndex..<dash]) ?? 0
        s = String(s[s.index(after: dash)...])
    }
    let comps = s.split(separator: ":").map { Int($0) ?? 0 }
    var h = 0, m = 0, sec = 0
    if comps.count == 3 { h = comps[0]; m = comps[1]; sec = comps[2] }
    else if comps.count == 2 { m = comps[0]; sec = comps[1] }
    else { sec = comps.first ?? 0 }
    if days > 0 { return "\(days)天\(h)小时\(m)分" }
    if h > 0 { return "\(h)小时\(m)分\(sec)秒" }
    if m > 0 { return "\(m)分\(sec)秒" }
    return "\(sec)秒"
}

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func plistXML(args: [String]) -> String {
    let elems = ([kKimiBin] + args).map { "        <string>\(esc($0))</string>" }.joined(separator: "\n")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(kLabel)</string>
        <key>ProgramArguments</key>
        <array>
    \(elems)
        </array>
        <key>WorkingDirectory</key>
        <string>\(NSHomeDirectory())</string>
        <key>EnvironmentVariables</key>
        <dict>
            <key>PATH</key>
            <string>\(NSHomeDirectory())/.kimi-code/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        </dict>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>\(NSHomeDirectory())/.kimi-code/logs/web-launchd.log</string>
        <key>StandardErrorPath</key>
        <string>\(NSHomeDirectory())/.kimi-code/logs/web-launchd.log</string>
    </dict>
    </plist>
    """
}

@MainActor
final class Controller: ObservableObject {
    @Published var state: ServiceState = .notLoaded
    @Published var pid: Int32?
    @Published var uptime: String?
    @Published var autostart = false
    @Published var argsText = kDefaultArgs
    @Published var message: String?
    private var timer: Timer?

    private var domain: String { "gui/\(getuid())" }
    private var target: String { "\(domain)/\(kLabel)" }

    init() {
        ensureConfig()
        if let saved = argsFromConfig() {
            argsText = saved
        }
        autostart = FileManager.default.fileExists(atPath: kLaunchAgentsPlist)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    func refresh() {
        let r = run("/bin/launchctl", ["print", target])
        if r.code == 0 {
            if let p = Self.parsePid(r.out) {
                state = .running
                pid = p
                let raw = run("/bin/ps", ["-p", "\(p)", "-o", "etime="]).out
                uptime = humanizeEtime(raw)
            } else {
                state = .loaded
                pid = nil
                uptime = nil
            }
        } else {
            state = .notLoaded
            pid = nil
            uptime = nil
        }
        autostart = FileManager.default.fileExists(atPath: kLaunchAgentsPlist)
    }

    private func waitUntilGone() -> Bool {
        for _ in 0..<25 {
            if run("/bin/launchctl", ["print", target]).code != 0 { return true }
            usleep(200_000)
        }
        return false
    }

    /// Bootstrap from the config plist; returns an error message on failure, nil on success.
    private func bootstrapService() -> String? {
        let r = run("/bin/launchctl", ["bootstrap", domain, kConfigPlist])
        guard r.code != 0, !r.out.contains("already loaded") else { return nil }
        let detail = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "launchctl bootstrap 退出码 \(r.code)" : detail
    }

    func start() {
        if state == .loaded {
            run("/bin/launchctl", ["kickstart", target])
            message = nil
            refresh()
            return
        }
        // 清除可能存在的半销毁状态，等旧服务彻底卸载后再 bootstrap
        run("/bin/launchctl", ["bootout", target])
        guard waitUntilGone() else {
            message = "启动失败：旧服务未能退出，请稍后重试"
            refresh()
            return
        }
        if let err = bootstrapService() {
            message = "启动失败：\(err)"
            refresh()
            return
        }
        run("/bin/launchctl", ["kickstart", target])
        message = nil
        refresh()
    }

    func restart() {
        run("/bin/launchctl", ["bootout", target])
        // bootout 是异步的，必须等旧服务真正卸载，否则紧接着的 bootstrap 会失败
        guard waitUntilGone() else {
            message = "重启失败：旧服务未能停止，请稍后重试"
            refresh()
            return
        }
        if let err = bootstrapService() {
            message = "重启失败：\(err)"
            refresh()
            return
        }
        run("/bin/launchctl", ["kickstart", target])
        message = nil
        refresh()
    }

    func stop() {
        run("/bin/launchctl", ["bootout", target])
        refresh()
    }

    func toggleAutostart(_ on: Bool) {
        let fm = FileManager.default
        if on {
            ensureConfig()
            try? fm.removeItem(atPath: kLaunchAgentsPlist)
            try? fm.copyItem(atPath: kConfigPlist, toPath: kLaunchAgentsPlist)
        } else {
            try? fm.removeItem(atPath: kLaunchAgentsPlist)
        }
        autostart = fm.fileExists(atPath: kLaunchAgentsPlist)
    }

    func saveArgs() {
        let parts = splitArgs(argsText)
        guard parts.first == "web" else {
            message = "参数必须以 web 开头"
            return
        }
        ensureConfig()
        try? plistXML(args: parts).write(toFile: kConfigPlist, atomically: true, encoding: .utf8)
        if autostart {
            try? FileManager.default.removeItem(atPath: kLaunchAgentsPlist)
            try? FileManager.default.copyItem(atPath: kConfigPlist, toPath: kLaunchAgentsPlist)
        }
        message = (state == .running) ? "已保存，重启服务后生效" : "已保存"
    }

    private func ensureConfig() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: kConfigDir) {
            try? fm.createDirectory(atPath: kConfigDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: kConfigPlist) {
            try? plistXML(args: splitArgs(kDefaultArgs)).write(toFile: kConfigPlist, atomically: true, encoding: .utf8)
        }
    }

    private func argsFromConfig() -> String? {
        guard let dict = NSDictionary(contentsOfFile: kConfigPlist) as? [String: Any],
              let arr = dict["ProgramArguments"] as? [String], !arr.isEmpty else { return nil }
        return arr.dropFirst().joined(separator: " ")
    }

    private static func parsePid(_ text: String) -> Int32? {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("pid = ") {
                return t.dropFirst("pid = ".count).split(separator: " ").first.flatMap { Int32($0) }
            }
        }
        return nil
    }
}

struct ContentView: View {
    @EnvironmentObject private var ctrl: Controller

    private var statusColor: Color {
        switch ctrl.state {
        case .running: return .green
        case .loaded: return .orange
        case .notLoaded: return Color(nsColor: .systemGray)
        }
    }

    private var statusText: String {
        switch ctrl.state {
        case .running: return "运行中"
        case .loaded: return "已加载未运行"
        case .notLoaded: return "已停止"
        }
    }

    private var port: String { argValue("--port", in: ctrl.argsText) ?? "58627" }
    private var remote: String { argValue("--allowed-host", in: ctrl.argsText) ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 11, height: 11)
                Text(statusText).font(.headline)
                Spacer()
                if let pid = ctrl.pid {
                    Text("PID \(pid)").font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("已运行：\(ctrl.uptime ?? "—")")
                Text("端口：\(port)")
                Text("远程地址：\(remote)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("启动") { ctrl.start() }
                    .disabled(ctrl.state == .running)
                Button("重启") { ctrl.restart() }
                    .disabled(ctrl.state == .notLoaded)
                Button("停止") { ctrl.stop() }
                    .disabled(ctrl.state == .notLoaded)
            }

            Divider()

            Toggle("开机自启（下次登录生效）", isOn: Binding(
                get: { ctrl.autostart },
                set: { ctrl.toggleAutostart($0) }
            ))
            .toggleStyle(.checkbox)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("启动参数").font(.callout)
                TextField("web ...", text: $ctrl.argsText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: ctrl.argsText) { ctrl.message = nil }
            }

            HStack {
                Text(ctrl.message ?? " ").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("保存参数") { ctrl.saveArgs() }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct KimiWebApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var ctrl = Controller()

    var body: some Scene {
        Window("Kimi Web 控制台", id: "console") {
            ContentView()
                .environmentObject(ctrl)
        }
        .windowResizability(.contentSize)
    }
}
