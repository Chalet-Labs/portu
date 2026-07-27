import Foundation

struct ZerionCollectionEnvelope<Resource: Decodable & Sendable>: Decodable {
    let data: [Resource]
    let links: ZerionLinks?
}

struct ZerionSingleEnvelope<Resource: Decodable & Sendable>: Decodable {
    let data: Resource
}

struct ZerionLinks: Decodable {
    let next: URL?
}

struct ZerionEmptyResource: Decodable {}

struct ZerionErrorEnvelope: Decodable {
    let errors: [Entry]

    struct Entry: Decodable {
        let title: String?
        let detail: String?
    }
}
