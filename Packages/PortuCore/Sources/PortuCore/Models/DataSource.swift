public enum DataSource: String, Codable, CaseIterable, Sendable {
    case zapper
    case zerion
    case exchange
    case manual
}
