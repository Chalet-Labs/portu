import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var csvContentType: UTType {
        UTType(filenameExtension: "csv") ?? .plainText
    }

    static var readableContentTypes: [UTType] {
        [csvContentType]
    }

    let text: String

    init(
        text: String
    ) {
        self.text = text
    }

    init(
        configuration: ReadConfiguration
    ) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
