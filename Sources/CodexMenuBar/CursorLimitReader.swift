import Foundation
import SQLite3

struct CursorLimitState: Sendable {
    var apiPercentUsed: Double?
    var totalPercentUsed: Double?
    var totalSpendUSD: Double?
    var includedSpendUSD: Double?
    var limitUSD: Double?
    var totalTokens: Int?
    var totalRequests: Int?
    var bonusSpendUSD: Double? = nil
    var onDemandSpendUSD: Double? = nil
    var billingCycleEnd: Date? = nil
    var isStale = false
    var observedAt: Date
    var source: String
    
    static let empty = CursorLimitState(
        apiPercentUsed: nil,
        totalPercentUsed: nil,
        totalSpendUSD: nil,
        includedSpendUSD: nil,
        limitUSD: nil,
        totalTokens: nil,
        totalRequests: nil,
        observedAt: Date(),
        source: "empty"
    )
}

final class CursorLimitReader: @unchecked Sendable {
    private let globalStoragePath: URL
    private let liveUsageURL = URL(string: "https://cursor.com/api/usage-summary")!
    private let tokenUsageURL = URL(string: "https://cursor.com/api/usage")!
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var suspended = false
    private var activeTasks: [URLSessionDataTask] = []

    func setSuspended(_ value: Bool) {
        lock.lock()
        suspended = value
        let tasks = value ? activeTasks : []
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    private func startTask(_ request: URLRequest, result: URLResultBox, semaphore: DispatchSemaphore) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !suspended else { return false }
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            result.data = data
            result.response = response
            semaphore.signal()
        }
        activeTasks.append(task)
        task.resume()
        return true
    }

    init(cursorHome: URL) {
        globalStoragePath = cursorHome.appendingPathComponent("User/globalStorage/state.vscdb")
    }
    
    func readAccessToken() -> String? {
        guard FileManager.default.fileExists(atPath: globalStoragePath.path) else {
            return nil
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(globalStoragePath.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        
        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cText = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: cText)
    }
    
    func parseUserId(from token: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        return sub
    }
    
    func readLiveUsage() -> CursorLimitState? {
        defer {
            lock.lock()
            activeTasks.removeAll()
            lock.unlock()
        }
        guard let token = readAccessToken(), let userId = parseUserId(from: token) else {
            return nil
        }
        
        let cookieValue = "\(userId)::\(token)"
        
        // Read the dashboard summary; amounts are cents, percentages are 0...100.
        var request = URLRequest(url: liveUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/settings", forHTTPHeaderField: "Referer")
        
        let semaphore = DispatchSemaphore(value: 0)
        let result = URLResultBox()
        
        guard startTask(request, result: result, semaphore: semaphore) else { return nil }
        
        guard semaphore.wait(timeout: .now() + 7.0) == .success,
              let http = result.response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let data = result.data,
              let state = Self.decodeUsageSummary(from: data) else {
            return nil
        }
        
        // Fetch model tokens (GET)
        var getRequest = URLRequest(url: tokenUsageURL)
        getRequest.httpMethod = "GET"
        getRequest.timeoutInterval = 6.0
        getRequest.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        
        let getSemaphore = DispatchSemaphore(value: 0)
        let getResult = URLResultBox()
        guard startTask(getRequest, result: getResult, semaphore: getSemaphore) else { return nil }
        
        var totalTokens = 0
        var totalRequests = 0
        
        if getSemaphore.wait(timeout: .now() + 7.0) == .success,
           let getHttp = getResult.response as? HTTPURLResponse,
           (200..<300).contains(getHttp.statusCode),
           let getData = getResult.data,
           let json = try? JSONSerialization.jsonObject(with: getData) as? [String: Any] {
            
            for (key, val) in json {
                if key != "startOfMonth", let dict = val as? [String: Any] {
                    if let tokens = dict["numTokens"] as? Int {
                        totalTokens += tokens
                    }
                    if let reqs = dict["numRequests"] as? Int {
                        totalRequests += reqs
                    }
                }
            }
        }
        
        var resultState = state
        resultState.totalTokens = totalTokens > 0 ? totalTokens : nil
        resultState.totalRequests = totalRequests > 0 ? totalRequests : nil
        return resultState
    }

    static func decodeUsageSummary(from data: Data, observedAt: Date = Date()) -> CursorLimitState? {
        guard let payload = try? JSONDecoder().decode(CursorUsageSummary.self, from: data),
              let plan = payload.individualUsage?.plan else { return nil }
        let derivedPercent = plan.used.flatMap { used in
            plan.limit.flatMap { $0 > 0 ? Double(used) / Double($0) * 100 : nil }
        }
        return CursorLimitState(
            apiPercentUsed: plan.apiPercentUsed,
            totalPercentUsed: plan.totalPercentUsed ?? derivedPercent,
            totalSpendUSD: plan.breakdown?.total.map { Double($0) / 100 },
            includedSpendUSD: plan.used.map { Double($0) / 100 },
            limitUSD: plan.limit.map { Double($0) / 100 },
            totalTokens: nil,
            totalRequests: nil,
            bonusSpendUSD: plan.breakdown?.bonus.map { Double($0) / 100 },
            onDemandSpendUSD: payload.individualUsage?.onDemand?.used.map { Double($0) / 100 },
            billingCycleEnd: payload.billingCycleEnd.flatMap { value in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
            },
            observedAt: observedAt,
            source: "live"
        )
    }
}

private struct CursorUsageSummary: Decodable {
    var billingCycleEnd: String?
    var individualUsage: IndividualUsage?
    struct IndividualUsage: Decodable {
        var plan: Plan?
        var onDemand: OnDemand?
    }
    struct Plan: Decodable {
        var used: Int?
        var limit: Int?
        var apiPercentUsed: Double?
        var totalPercentUsed: Double?
        var breakdown: Breakdown?
    }
    struct Breakdown: Decodable {
        var total: Int?
        var bonus: Int?
    }
    struct OnDemand: Decodable { var used: Int? }
}
