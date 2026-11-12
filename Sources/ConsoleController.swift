import Foundation
import SwiftUI

enum ConsoleAction: String, CaseIterable {
    case start
    case restart
    case stop
    case attach
    case update

    var title: String {
        switch self {
        case .start: return "启动"
        case .restart: return "重启"
        case .stop: return "停止"
        case .attach: return "接回 Terminal"
        case .update: return "更新 Kimi Code"
        }
    }
}

enum PersistentTaskStatus: String {
    case running
    case succeeded
    case failed
    case unknown
}

struct PersistentTask: Equatable {
    let id: String
    let action: String
    let status: PersistentTaskStatus
    let pid: Int?
    let updatedAt: String
    let message: String
    let log: String

    static func parse(_ text: String) -> PersistentTask? {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        guard let id = values["id"], let action = values["action"] else { return nil }
        return PersistentTask(
            id: id,
            action: action,
            status: PersistentTaskStatus(rawValue: values["status"] ?? "") ?? .unknown,
            pid: values["pid"].flatMap(Int.init),
            updatedAt: values["updated_at"] ?? "",
            message: values["message"] ?? "",
            log: values["log"] ?? ""
        )
    }
}

struct ScreenStatus: Equatable {
    let isRunning: Bool
    let screenPID: Int?
    let servicePID: Int?

    static func parse(screenOutput: String, sessionName: String, processOutput: String) -> ScreenStatus {
        let suffix = ".\(sessionName)"
        var screenPID: Int?
        for line in screenOutput.split(whereSeparator: \.isNewline) {
            guard let entry = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
                  entry.hasSuffix(suffix) else { continue }
            let pidText = entry.dropLast(suffix.count)
            if let pid = Int(pidText) {
                screenPID = pid
                break
            }
        }
        guard let screenPID else {
            return ScreenStatus(isRunning: false, screenPID: nil, servicePID: nil)
        }

        var children: [Int: [Int]] = [:]
        for line in processOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, let pid = Int(fields[0]), let parent = Int(fields[1]) else { continue }
            children[parent, default: []].append(pid)
        }
        let managerPID = children[screenPID]?.first
        let servicePID = managerPID.flatMap { children[$0]?.first } ?? managerPID
        return ScreenStatus(isRunning: true, screenPID: screenPID, servicePID: servicePID)
    }
}

struct ConsoleConfiguration {
    let sessionName: String
    let configPath: String
    let webURL: URL
    let kimiBinary: String
    let stateDirectory: URL
    let actionEnvironment: [String: String]

    init(environment: [String: String]) {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        sessionName = environment["KIMI_WEB_SCREEN_SESSION"].flatMap { $0.isEmpty ? nil : $0 } ?? "kimi-web"
        configPath = environment["KIMI_WEB_CONFIG"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(home)/Library/Application Support/KimiWeb/com.kimi.web.plist"
        let webString = environment["KIMI_WEB_URL"].flatMap { $0.isEmpty ? nil : $0 } ?? "http://127.0.0.1:58627/"
        webURL = URL(string: webString) ?? URL(string: "http://127.0.0.1:58627/")!
        kimiBinary = environment["KIMI_WEB_KIMI_BIN"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.kimi-code/bin/kimi"
        stateDirectory = URL(fileURLWithPath: environment["KIMI_WEB_STATE_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(home)/Library/Logs/KimiWeb", isDirectory: true)

        var actionEnvironment = environment
        actionEnvironment["HOME"] = home
        actionEnvironment["KIMI_WEB_SCREEN_SESSION"] = sessionName
        actionEnvironment["KIMI_WEB_CONFIG"] = configPath
        actionEnvironment["KIMI_WEB_URL"] = webURL.absoluteString
        actionEnvironment["KIMI_WEB_KIMI_BIN"] = kimiBinary
        actionEnvironment["KIMI_WEB_STATE_DIR"] = stateDirectory.path
        self.actionEnvironment = actionEnvironment
    }
}

private struct ConsoleProcessResult {
    let status: Int32
    let output: String
}

private enum ConsoleProcessRunner {
    static func run(
        _ executablePath: String,
        _ arguments: [String],
        environment: [String: String],
        completion: @escaping (ConsoleProcessResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                completion(ConsoleProcessResult(status: -1, output: error.localizedDescription))
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            completion(ConsoleProcessResult(
                status: process.terminationStatus,
                output: String(data: data, encoding: .utf8) ?? ""
            ))
        }
    }
}

private final class ConsoleStatusProbe {
    private let configuration: ConsoleConfiguration

    init(configuration: ConsoleConfiguration) {
        self.configuration = configuration
    }

    func screen(completion: @escaping (ScreenStatus) -> Void) {
        ConsoleProcessRunner.run("/usr/bin/screen", ["-ls"], environment: configuration.actionEnvironment) { result in
            let initial = ScreenStatus.parse(
                screenOutput: result.output,
                sessionName: self.configuration.sessionName,
                processOutput: ""
            )
            guard initial.isRunning else {
                completion(initial)
                return
            }
            ConsoleProcessRunner.run("/bin/ps", ["-axo", "pid=,ppid="], environment: self.configuration.actionEnvironment) { processes in
                completion(ScreenStatus.parse(
                    screenOutput: result.output,
                    sessionName: self.configuration.sessionName,
                    processOutput: processes.output
                ))
            }
        }
    }

    func version(completion: @escaping (String) -> Void) {
        ConsoleProcessRunner.run(configuration.kimiBinary, ["--version"], environment: configuration.actionEnvironment) { result in
            let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(result.status == 0 && !version.isEmpty ? version : "未知")
        }
    }

    func web(completion: @escaping (Bool) -> Void) {
        guard configuration.webURL.scheme == "http" || configuration.webURL.scheme == "https" else {
            completion(false)
            return
        }
        var request = URLRequest(url: configuration.webURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { _, response, error in
            completion(error == nil && (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true)
        }.resume()
    }
}

@MainActor
final class ConsoleController: ObservableObject {
    @Published private(set) var screenRunning = false
    @Published private(set) var servicePID: Int?
    @Published private(set) var version = "检查中…"
    @Published private(set) var webReachable = false
    @Published private(set) var persistentTask: PersistentTask?
    @Published private(set) var actionOutput = ""
    @Published private(set) var logText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isInitialTaskRestorePending = true
    @Published private(set) var commandText = ""
    @Published private(set) var commandDirty = false
    @Published private(set) var isCommandSaving = false
    @Published private(set) var commandStatusMessage: String?
    @Published var confirmingUpdate = false

    let configuration: ConsoleConfiguration
    private let actionScriptURL: URL?
    private let probe: ConsoleStatusProbe
    private var commandConfiguration: CommandConfiguration?
    private var activeAction: ConsoleAction?
    private var refreshItemsRemaining = 0
    private var taskReadGeneration = 0
    private var logReadGeneration = 0
    private var commandLoadGeneration = 0
    private var commandEditGeneration = 0
    private var isCommandLoading = false
    private var refreshTimer: Timer?

    var isBusy: Bool {
        isInitialTaskRestorePending || isCommandSaving || activeAction != nil || persistentTask?.status == .running
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        actionScriptURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("console-action.applescript"),
        autoRefresh: Bool = true
    ) {
        configuration = ConsoleConfiguration(environment: environment)
        self.actionScriptURL = actionScriptURL
        probe = ConsoleStatusProbe(configuration: configuration)
        reloadPersistentTask()
        reloadLog()
        reloadCommand(force: true)
        refresh()
        if autoRefresh {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.reloadPersistentTask()
                    self?.reloadLog()
                    self?.refresh()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
    }

    func updateCommandText(_ text: String) {
        commandText = text
        commandDirty = true
        commandEditGeneration += 1
        commandStatusMessage = nil
    }

    func reloadCommand(force: Bool = false) {
        guard !isCommandSaving, !isCommandLoading, force || !commandDirty else { return }
        commandLoadGeneration += 1
        let generation = commandLoadGeneration
        let editGeneration = commandEditGeneration
        let fileURL = URL(fileURLWithPath: configuration.configPath)
        isCommandLoading = true
        if force {
            errorMessage = nil
            commandStatusMessage = nil
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try CommandConfiguration.load(from: fileURL) }
            Task { @MainActor in
                guard generation == self.commandLoadGeneration else { return }
                self.isCommandLoading = false
                switch result {
                case .success(let loaded):
                    self.commandConfiguration = loaded
                    guard editGeneration == self.commandEditGeneration else { return }
                    do {
                        self.commandText = try CommandLine.string(from: loaded.programArguments)
                        self.commandDirty = false
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func saveCommand() {
        saveCommand(restartAfterSave: false)
    }

    func saveCommandAndRestart() {
        saveCommand(restartAfterSave: true)
    }

    private func saveCommand(restartAfterSave: Bool) {
        guard !isCommandSaving else { return }
        guard !restartAfterSave || !isBusy else {
            errorMessage = "另一个控制台任务正在执行；命令尚未保存，不能重启。"
            return
        }
        guard let snapshot = commandConfiguration else {
            errorMessage = "命令配置尚未载入，无法保存。请重新加载。"
            return
        }
        let draft = commandText
        let editGeneration = commandEditGeneration
        commandLoadGeneration += 1
        isCommandLoading = false
        isCommandSaving = true
        errorMessage = nil
        commandStatusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                let arguments = try CommandLine.parse(draft)
                return try snapshot.saving(programArguments: arguments)
            }
            Task { @MainActor in
                self.isCommandSaving = false
                switch result {
                case .success(let saved):
                    self.commandConfiguration = saved
                    if editGeneration == self.commandEditGeneration {
                        self.commandDirty = false
                    }
                    if restartAfterSave {
                        self.commandStatusMessage = "命令已保存，已发起重启。"
                        if self.isBusy {
                            self.errorMessage = "命令已保存，但另一个控制台任务正在执行，未发起重启。"
                        } else {
                            self.perform(.restart)
                        }
                    } else {
                        self.commandStatusMessage = "命令已保存；重启后生效。"
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func perform(_ action: ConsoleAction) {
        guard !isBusy else { return }
        guard let actionScriptURL else {
            errorMessage = "App Resources 中缺少 console-action.applescript。"
            return
        }
        activeAction = action
        errorMessage = nil
        actionOutput = "正在执行\(action.title)…\n"
        ConsoleProcessRunner.run(
            "/usr/bin/osascript",
            [actionScriptURL.path, action.rawValue],
            environment: configuration.actionEnvironment
        ) { result in
            Task { @MainActor in
                self.activeAction = nil
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.actionOutput = output.isEmpty ? "退出状态：\(result.status)" : output
                if result.status != 0 {
                    self.errorMessage = "\(action.title)失败（退出状态 \(result.status)）。请查看输出与 Terminal 诊断窗口。"
                }
                self.reloadPersistentTask()
                self.reloadLog()
                self.refresh()
            }
        }
    }

    func openWeb() {
        NSWorkspace.shared.open(configuration.webURL)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        reloadCommand()
        refreshItemsRemaining = 3
        probe.screen { status in
            Task { @MainActor in
                self.screenRunning = status.isRunning
                self.servicePID = status.servicePID
                self.finishRefreshItem()
            }
        }
        probe.version { version in
            Task { @MainActor in
                self.version = version
                self.finishRefreshItem()
            }
        }
        probe.web { reachable in
            Task { @MainActor in
                self.webReachable = reachable
                self.finishRefreshItem()
            }
        }
    }

    func reloadPersistentTask() {
        taskReadGeneration += 1
        let generation = taskReadGeneration
        let stateURL = configuration.stateDirectory.appendingPathComponent("task.state")
        DispatchQueue.global(qos: .userInitiated).async {
            let text = try? String(contentsOf: stateURL, encoding: .utf8)
            let task = text.flatMap(PersistentTask.parse)
            Task { @MainActor in
                guard generation == self.taskReadGeneration else { return }
                self.persistentTask = task
                self.isInitialTaskRestorePending = false
            }
        }
    }

    func reloadLog() {
        logReadGeneration += 1
        let generation = logReadGeneration
        let logURL = configuration.stateDirectory.appendingPathComponent("console.log")
        DispatchQueue.global(qos: .utility).async {
            let text = Self.readLogTail(at: logURL)
            Task { @MainActor in
                guard generation == self.logReadGeneration else { return }
                self.logText = text
            }
        }
    }

    private func finishRefreshItem() {
        refreshItemsRemaining -= 1
        if refreshItemsRemaining == 0 {
            isRefreshing = false
        }
    }

    private nonisolated static func readLogTail(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        let maximumBytes: UInt64 = 256 * 1024
        try? handle.seek(toOffset: size - min(size, maximumBytes))
        let data = handle.readDataToEndOfFile()
        var text = String(decoding: data, as: UTF8.self)
        if size > maximumBytes, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }
}
