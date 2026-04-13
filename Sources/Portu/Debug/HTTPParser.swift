#if DEBUG

    import Foundation

    struct HTTPRequest {
        let method: String
        let path: String
        let queryParams: [String: String]
    }

    struct HTTPResponse {
        let statusCode: Int
        let body: Data
        var headers: [String: String] = [:]

        var statusText: String {
            switch statusCode {
            case 200: "OK"
            case 400: "Bad Request"
            case 404: "Not Found"
            case 405: "Method Not Allowed"
            case 500: "Internal Server Error"
            default: "Status \(statusCode)"
            }
        }
    }

    enum HTTPParser {
        private static let maxRequestLineLength = 8192
        private static let headerTerminator = Data("\r\n\r\n".utf8)

        static func parse(_ data: Data) -> HTTPRequest? {
            guard
                !data.isEmpty,
                data.range(of: headerTerminator) != nil
            else { return nil }

            guard let firstLineEnd = data.range(of: Data("\r\n".utf8)) else { return nil }
            let requestLineData = data[data.startIndex ..< firstLineEnd.lowerBound]

            guard
                requestLineData.count <= maxRequestLineLength,
                let requestLine = String(data: requestLineData, encoding: .utf8)
            else { return nil }

            // "GET /path HTTP/1.1"
            let parts = requestLine.split(separator: " ", maxSplits: 2)
            guard parts.count == 3, parts[2].hasPrefix("HTTP/") else { return nil }

            let method = String(parts[0])
            let rawURI = String(parts[1])

            let (path, queryParams) = parseURI(rawURI)
            return HTTPRequest(method: method, path: path, queryParams: queryParams)
        }

        private static func parseURI(_ uri: String) -> (path: String, queryParams: [String: String]) {
            guard let questionMark = uri.firstIndex(of: "?") else {
                return (uri, [:])
            }

            let path = String(uri[uri.startIndex ..< questionMark])
            let queryString = String(uri[uri.index(after: questionMark)...])

            var params: [String: String] = [:]
            for pair in queryString.split(separator: "&", omittingEmptySubsequences: true) {
                if let eqIndex = pair.firstIndex(of: "=") {
                    let key = String(pair[pair.startIndex ..< eqIndex])
                    let value = String(pair[pair.index(after: eqIndex)...])
                    params[key] = value
                } else {
                    params[String(pair)] = ""
                }
            }

            return (path, params)
        }
    }

#endif
