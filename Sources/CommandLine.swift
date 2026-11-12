import Foundation

enum CommandLineError: Error, LocalizedError {
    case emptyCommand
    case unterminatedQuote
    case trailingEscape
    case programPathNotAbsolute(String)
    case programNotExecutable(String)

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "命令不能为空。"
        case .unterminatedQuote:
            return "命令包含未闭合的引号。"
        case .trailingEscape:
            return "命令末尾的反斜线缺少要转义的字符。"
        case .programPathNotAbsolute(let path):
            return "程序路径必须是绝对路径：\(path)"
        case .programNotExecutable(let path):
            return "程序路径不存在、不是文件或不可执行：\(path)"
        }
    }
}

enum CommandLine {
    private enum ParseState {
        case unquoted
        case singleQuoted
        case doubleQuoted
    }

    static func parse(_ command: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var state = ParseState.unquoted
        var tokenStarted = false
        var iterator = command.makeIterator()

        while let character = iterator.next() {
            switch state {
            case .unquoted:
                if character.isWhitespace {
                    if tokenStarted {
                        arguments.append(current)
                        current = ""
                        tokenStarted = false
                    }
                } else if character == "'" {
                    state = .singleQuoted
                    tokenStarted = true
                } else if character == "\"" {
                    state = .doubleQuoted
                    tokenStarted = true
                } else if character == "\\" {
                    guard let escaped = iterator.next() else { throw CommandLineError.trailingEscape }
                    current.append(escaped)
                    tokenStarted = true
                } else {
                    current.append(character)
                    tokenStarted = true
                }
            case .singleQuoted:
                if character == "'" {
                    state = .unquoted
                } else {
                    current.append(character)
                }
            case .doubleQuoted:
                if character == "\"" {
                    state = .unquoted
                } else if character == "\\" {
                    guard let escaped = iterator.next() else { throw CommandLineError.trailingEscape }
                    current.append(escaped)
                } else {
                    current.append(character)
                }
            }
        }

        guard state == .unquoted else { throw CommandLineError.unterminatedQuote }
        if tokenStarted {
            arguments.append(current)
        }
        try validate(arguments)
        return arguments
    }

    static func string(from arguments: [String]) throws -> String {
        try validate(arguments)
        return arguments.map(quote).joined(separator: " ")
    }

    static func validate(_ arguments: [String]) throws {
        guard let program = arguments.first, !program.isEmpty else {
            throw CommandLineError.emptyCommand
        }
        guard program.hasPrefix("/") else {
            throw CommandLineError.programPathNotAbsolute(program)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: program, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: program) else {
            throw CommandLineError.programNotExecutable(program)
        }
    }

    private static func quote(_ argument: String) -> String {
        if !argument.isEmpty && argument.allSatisfy({ $0.isLetter || $0.isNumber || "_-./:=@+,%".contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
