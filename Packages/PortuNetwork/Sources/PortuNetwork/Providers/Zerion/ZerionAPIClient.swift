import Foundation

public actor ZerionAPIClient {
    public typealias APIKeyProvider = @Sendable () throws -> String
    typealias PacingNow = @Sendable () -> Duration
    typealias PacingSleep = @Sendable (Duration) async throws -> Void

    public static let defaultMinimumRequestInterval: Duration = .seconds(1)
    private static let baseURL = URL(string: "https://api.zerion.io/v1/")!

    private let apiKey: APIKeyProvider
    private let session: URLSession
    private let decoder: JSONDecoder
    private let minimumRequestInterval: Duration
    private let maximumRetryAttempts: Int
    private let maximumRetryDelaySeconds: Int
    private let pacingNow: PacingNow
    private let pacingSleep: PacingSleep
    private var nextRequestTime: Duration?

    private enum RetryMode {
        case standard
        case analyticsPreparation(deadline: Duration)
    }

    public init(
        apiKey: @escaping APIKeyProvider,
        session: URLSession = .shared,
        minimumRequestInterval: Duration = defaultMinimumRequestInterval,
        maximumRetryAttempts: Int = 2,
        maximumRetryDelaySeconds: Int = 10) {
        self.apiKey = apiKey
        self.session = session
        self.minimumRequestInterval = minimumRequestInterval
        self.maximumRetryAttempts = max(0, maximumRetryAttempts)
        self.maximumRetryDelaySeconds = max(0, maximumRetryDelaySeconds)
        self.decoder = JSONDecoder()
        let clock = ContinuousClock()
        let origin = clock.now
        self.pacingNow = { origin.duration(to: clock.now) }
        self.pacingSleep = { try await clock.sleep(for: $0) }
    }

    init(
        apiKey: @escaping APIKeyProvider,
        session: URLSession,
        minimumRequestInterval: Duration,
        maximumRetryAttempts: Int = 2,
        maximumRetryDelaySeconds: Int = 10,
        pacingNow: @escaping PacingNow,
        pacingSleep: @escaping PacingSleep) {
        self.apiKey = apiKey
        self.session = session
        self.minimumRequestInterval = minimumRequestInterval
        self.maximumRetryAttempts = max(0, maximumRetryAttempts)
        self.maximumRetryDelaySeconds = max(0, maximumRetryDelaySeconds)
        self.decoder = JSONDecoder()
        self.pacingNow = pacingNow
        self.pacingSleep = pacingSleep
    }

    func get<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = []) async throws -> Response {
        try await get(path: path, queryItems: queryItems, retryMode: .standard)
    }

    func getAnalytics<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        maximumPreparationWait: Duration = .seconds(120)) async throws -> Response {
        let deadline = analyticsPreparationDeadline(maximumWait: maximumPreparationWait)
        return try await getAnalytics(
            path: path,
            queryItems: queryItems,
            preparationDeadline: deadline)
    }

    func analyticsPreparationDeadline(
        maximumWait: Duration = .seconds(120)) -> Duration {
        pacingNow() + max(.zero, maximumWait)
    }

    func getAnalytics<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        preparationDeadline: Duration) async throws -> Response {
        try await get(
            path: path,
            queryItems: queryItems,
            retryMode: .analyticsPreparation(deadline: preparationDeadline))
    }

    private func get<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem],
        retryMode: RetryMode) async throws -> Response {
        guard
            !path.hasPrefix("/"),
            !path.contains(".."),
            var components = URLComponents(
                url: Self.baseURL.appending(path: path, directoryHint: .notDirectory),
                resolvingAgainstBaseURL: false)
        else {
            throw ZerionError.untrustedURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ZerionError.untrustedURL
        }
        return try await get(url: url, retryMode: retryMode)
    }

    func get<Response: Decodable & Sendable>(next url: URL) async throws -> Response {
        try await get(url: url, retryMode: .standard)
    }

    private func get<Response: Decodable & Sendable>(
        url: URL,
        retryMode: RetryMode) async throws -> Response {
        try validate(url)
        let key = try apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ZerionError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Basic \(Data("\(key):".utf8).base64EncodedString())",
            forHTTPHeaderField: "Authorization")

        var attempt = 0
        let preparationDeadline: Duration? = switch retryMode {
        case .standard:
            nil
        case let .analyticsPreparation(deadline):
            deadline
        }
        while true {
            try await paceRequest()
            if let preparationDeadline, pacingNow() >= preparationDeadline {
                throw ZerionError.temporarilyUnavailable(retryAfter: nil)
            }
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZerionError.invalidResponse
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                do {
                    return try decoder.decode(Response.self, from: data)
                } catch {
                    throw ZerionError.decodingFailed
                }
            }

            let error = Self.error(from: httpResponse, data: data)
            if
                case let .temporarilyUnavailable(retryAfter) = error,
                let preparationDeadline,
                let retryAfter,
                retryAfter > 0 {
                let delay = Duration.seconds(retryAfter)
                let now = pacingNow()
                guard now < preparationDeadline, now + delay <= preparationDeadline else {
                    throw error
                }
                try await pacingSleep(delay)
                guard pacingNow() < preparationDeadline else {
                    throw error
                }
                continue
            }
            guard attempt < maximumRetryAttempts, Self.isRetryable(httpResponse.statusCode) else {
                throw error
            }
            if
                case let .rateLimited(_, remainingDay, remainingMonth, _) = error,
                remainingDay == 0 || remainingMonth == 0 {
                throw error
            }
            attempt += 1
            if let seconds = Self.integerHeader("Retry-After", in: httpResponse), seconds > 0 {
                guard seconds <= maximumRetryDelaySeconds else {
                    throw error
                }
                try await pacingSleep(.seconds(seconds))
            }
        }
    }

    private func paceRequest() async throws {
        let now = pacingNow()
        let slot = nextRequestTime.map { max(now, $0) } ?? now
        nextRequestTime = slot + minimumRequestInterval
        if slot > now {
            try await pacingSleep(slot - now)
        }
    }

    private func validate(_ url: URL) throws {
        guard
            url.scheme == "https",
            url.host == "api.zerion.io",
            url.path == "/v1" || url.path.hasPrefix("/v1/")
        else {
            throw ZerionError.untrustedURL
        }
    }

    private static func isRetryable(_ statusCode: Int) -> Bool {
        statusCode == 429 || [500, 502, 503, 504].contains(statusCode)
    }

    private static func error(from response: HTTPURLResponse, data: Data) -> ZerionError {
        switch response.statusCode {
        case 400:
            structuredError(statusCode: response.statusCode, data: data) ?? .badRequest
        case 401, 403:
            .unauthorized
        case 402:
            .paymentRequired
        case 404:
            .notFound
        case 429:
            .rateLimited(
                remainingSecond: integerHeader(
                    names: ["RateLimit-Org-Second-Remaining", "X-RateLimit-Remaining-Second"],
                    in: response),
                remainingDay: integerHeader(
                    names: ["RateLimit-Org-Day-Remaining", "X-RateLimit-Remaining-Day"],
                    in: response),
                remainingMonth: integerHeader(
                    names: ["RateLimit-Org-Month-Remaining", "X-RateLimit-Remaining-Month"],
                    in: response),
                reset: firstHeader(
                    names: ["RateLimit-Org-Second-Reset", "X-RateLimit-Reset"],
                    in: response))
        case 503:
            .temporarilyUnavailable(retryAfter: integerHeader("Retry-After", in: response))
        default:
            structuredError(statusCode: response.statusCode, data: data)
                ?? .httpError(statusCode: response.statusCode)
        }
    }

    private static func structuredError(statusCode: Int, data: Data) -> ZerionError? {
        guard let entry = try? JSONDecoder().decode(ZerionErrorEnvelope.self, from: data).errors.first else {
            return nil
        }
        return .apiError(statusCode: statusCode, title: entry.title, detail: entry.detail)
    }

    private static func integerHeader(_ name: String, in response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: name).flatMap(Int.init)
    }

    private static func integerHeader(names: [String], in response: HTTPURLResponse) -> Int? {
        firstHeader(names: names, in: response).flatMap(Int.init)
    }

    private static func firstHeader(names: [String], in response: HTTPURLResponse) -> String? {
        names.lazy.compactMap { response.value(forHTTPHeaderField: $0) }.first
    }
}
