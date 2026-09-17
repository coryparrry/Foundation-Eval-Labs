import Foundation

public enum DeveloperDirectory {
    public static let defaultPath = "/Applications/Xcode.app/Contents/Developer"

    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        xcodeSelect: (() throws -> String)? = nil
    ) -> String {
        if let override = environment["DEVELOPER_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        if let selected = try? (xcodeSelect ?? xcodeSelectPrintPath)() {
            let path = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return defaultPath
    }

    private static func xcodeSelectPrintPath() throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CaptureFileIOError.io("xcode-select -p failed.")
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
