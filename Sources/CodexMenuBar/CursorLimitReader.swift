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
    private let liveUsageURL = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!
    private let tokenUsageURL = URL(string: "https://cursor.com/api/usage")!
    private let decoder = JSONDecoder()

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
        guard let token = readAccessToken(), let userId = parseUserId(from: token) else {
            return nil
        }
        
        let cookieValue = "\(userId)::\(token)"
        
        // Fetch plan usage (POST)
        var request = URLRequest(url: liveUsageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 6.0
        request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/settings", forHTTPHeaderField: "Referer")
        
        struct ResponsePayload: Decodable {
            struct PlanUsage: Decodable {
                let totalSpend: Double?
                let includedSpend: Double?
                let limit: Double?
                let apiPercentUsed: Double?
                let totalPercentUsed: Double?
            }
            let planUsage: PlanUsage?
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        let result = URLResultBox()
        
        URLSession.shared.dataTask(with: request) { data, response, _ in
            result.data = data
            result.response = response
            semaphore.signal()
        }.resume()
        
        guard semaphore.wait(timeout: .now() + 7.0) == .success,
              let http = result.response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let data = result.data,
              let payload = try? decoder.decode(ResponsePayload.self, from: data),
              let plan = payload.planUsage else {
            return nil
        }
        
        // Fetch model tokens (GET)
        var getRequest = URLRequest(url: tokenUsageURL)
        getRequest.httpMethod = "GET"
        getRequest.timeoutInterval = 6.0
        getRequest.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        
        let getSemaphore = DispatchSemaphore(value: 0)
        let getResult = URLResultBox()
        URLSession.shared.dataTask(with: getRequest) { data, response, _ in
            getResult.data = data
            getResult.response = response
            getSemaphore.signal()
        }.resume()
        
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
        
        return CursorLimitState(
            apiPercentUsed: plan.apiPercentUsed,
            totalPercentUsed: plan.totalPercentUsed,
            totalSpendUSD: plan.totalSpend.map { $0 / 100.0 },
            includedSpendUSD: plan.includedSpend.map { $0 / 100.0 },
            limitUSD: plan.limit.map { $0 / 100.0 },
            totalTokens: totalTokens > 0 ? totalTokens : nil,
            totalRequests: totalRequests > 0 ? totalRequests : nil,
            observedAt: Date(),
            source: "live"
        )
    }
}
