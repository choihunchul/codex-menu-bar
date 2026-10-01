import Darwin
import Foundation

struct AntigravityLimitState {
    var limits: [NamedLimitBucket]
    var observedAt: Date
    var isStale = false

    static let empty = AntigravityLimitState(limits: [], observedAt: .distantPast)
}

/// Reads the official /usage command without sending a model prompt.
final class AntigravityLimitReader: @unchecked Sendable {
    private let executable: URL?
    private let lock = NSLock()
    private var suspended = false
    private var activeProcess: Process?

    func setSuspended(_ value: Bool) {
        lock.lock()
        suspended = value
        if value, let process = activeProcess, process.isRunning {
            process.terminate()
        }
        lock.unlock()
    }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let candidates = [
            home.appendingPathComponent(".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy")
        ]
        executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func readLatest() -> AntigravityLimitState? {
        guard let executable else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-menu-bar-quota-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("usage.json")
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["-p", "/usage", "--output-format", "json"]
            process.currentDirectoryURL = directory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            lock.lock()
            guard !suspended else { lock.unlock(); return nil }
            do {
                try process.run()
                activeProcess = process
                lock.unlock()
            } catch {
                lock.unlock()
                return nil
            }
            defer {
                lock.lock()
                activeProcess = nil
                lock.unlock()
            }
            guard finished.wait(timeout: .now() + 45) == .success else {
                if process.isRunning { process.terminate() }
                if finished.wait(timeout: .now() + 2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
                return nil
            }
            guard process.terminationStatus == 0,
                  let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 1_048_576 else { return nil }
            return Self.decodeUsageReport(from: try Data(contentsOf: output))
        } catch {
            return nil
        }
    }

    static func decodeUsageReport(from data: Data, observedAt: Date = Date()) -> AntigravityLimitState? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let report = try? decoder.decode(UsageReport.self, from: data),
              report.status == "SUCCESS", report.command.name == "usage" else { return nil }
        var limits: [NamedLimitBucket] = []
        for group in report.command.data.groups {
            for bucket in group.buckets where bucket.disabled != true {
                guard let remaining = bucket.remainingFraction, remaining.isFinite,
                      (0...1).contains(remaining) else { continue }
                let minutes: Double?
                switch bucket.window {
                case "weekly": minutes = 10_080
                case "5h": minutes = 300
                default: minutes = nil
                }
                let formatter = ISO8601DateFormatter()
                var reset = bucket.resetTime.flatMap { formatter.date(from: $0) }
                if reset == nil {
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    reset = bucket.resetTime.flatMap { formatter.date(from: $0) }
                }
                let name = "\(group.name) \(bucket.window ?? bucket.name)"
                limits.append(NamedLimitBucket(name: name, bucket: LimitBucket(
                    usedPercent: (1 - remaining) * 100, windowMinutes: minutes,
                    resetAt: reset?.timeIntervalSince1970)))
            }
        }
        guard !limits.isEmpty else { return nil }
        return AntigravityLimitState(limits: limits, observedAt: observedAt)
    }
}

private struct UsageReport: Decodable {
    var status: String
    var command: Command
    struct Command: Decodable {
        var name: String
        var data: Quota
    }
    struct Quota: Decodable { var groups: [Group] }
    struct Group: Decodable {
        var name: String
        var buckets: [Bucket]
    }
    struct Bucket: Decodable {
        var name: String
        var window: String?
        var remainingFraction: Double?
        var resetTime: String?
        var disabled: Bool?
    }
}
