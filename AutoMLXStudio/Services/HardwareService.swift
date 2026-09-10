import Foundation

actor HardwareService {
    func readProfile() -> HardwareProfile {
        HardwareProfile(
            chip: shell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            memoryGB: memoryGB(),
            architecture: shell("/usr/bin/uname", ["-m"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private func memoryGB() -> Double {
        let raw = shell("/usr/sbin/sysctl", ["-n", "hw.memsize"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bytes = Double(raw) else { return 0 }
        return bytes / 1_073_741_824
    }

    private func shell(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
