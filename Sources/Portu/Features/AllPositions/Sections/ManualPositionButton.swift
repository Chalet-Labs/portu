import SwiftUI

struct ManualPositionButton: View {
    @State private var isPresentingEditor = false

    private let onComplete: @MainActor () -> Void

    init(onComplete: @escaping @MainActor () -> Void = {}) {
        self.onComplete = onComplete
    }

    var body: some View {
        Button("Add Position", systemImage: "plus") {
            isPresentingEditor = true
        }
        .sheet(isPresented: $isPresentingEditor) {
            ManualPositionEditor {
                isPresentingEditor = false
                onComplete()
            }
        }
    }
}
