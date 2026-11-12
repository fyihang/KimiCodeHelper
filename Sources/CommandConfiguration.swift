import CryptoKit
import Foundation

enum CommandConfigurationError: Error, LocalizedError {
    case invalidPropertyList
    case missingProgramArguments
    case conflict

    var errorDescription: String? {
        switch self {
        case .invalidPropertyList:
            return "配置文件不是有效的 plist 字典。"
        case .missingProgramArguments:
            return "配置文件中缺少有效的 ProgramArguments 字符串数组。"
        case .conflict:
            return "配置文件已被外部修改；未保存。请重新加载后再编辑。"
        }
    }
}

struct CommandConfiguration: Sendable {
    let fileURL: URL
    let programArguments: [String]
    let originalDigest: String

    static func load(from fileURL: URL) throws -> CommandConfiguration {
        let data = try Data(contentsOf: fileURL)
        let dictionary = try propertyListDictionary(from: data)
        guard let arguments = dictionary["ProgramArguments"] as? [String] else {
            throw CommandConfigurationError.missingProgramArguments
        }
        try CommandLine.validate(arguments)
        return CommandConfiguration(
            fileURL: fileURL,
            programArguments: arguments,
            originalDigest: digest(data)
        )
    }

    func saving(programArguments arguments: [String]) throws -> CommandConfiguration {
        try CommandLine.validate(arguments)
        let currentData = try Data(contentsOf: fileURL)
        guard Self.digest(currentData) == originalDigest else {
            throw CommandConfigurationError.conflict
        }
        var dictionary = try Self.propertyListDictionary(from: currentData)
        dictionary["ProgramArguments"] = arguments
        let output = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let temporaryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try output.write(to: temporaryURL)
        let validated = try Self.propertyListDictionary(from: Data(contentsOf: temporaryURL))
        guard validated["ProgramArguments"] as? [String] == arguments else {
            throw CommandConfigurationError.invalidPropertyList
        }
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        return CommandConfiguration(fileURL: fileURL, programArguments: arguments, originalDigest: Self.digest(output))
    }

    private static func propertyListDictionary(from data: Data) throws -> [String: Any] {
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CommandConfigurationError.invalidPropertyList
        }
        return dictionary
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
