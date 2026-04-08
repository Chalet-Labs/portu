import PortuCore
import SwiftUI

struct APIKeysSettingsTab: View {
    @State private var viewModel = APIKeysViewModel()
    @State private var newRPCChain: Chain = .ethereum
    @State private var newRPCURL = ""
    @State private var showError = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                apiKeyField("Zapper", text: $viewModel.zapperAPIKey)
                apiKeyField("DeBank", text: $viewModel.debankAPIKey)
                apiKeyField(
                    "CoinGecko",
                    text: $viewModel.coingeckoAPIKey,
                    hint: "Optional. Provides higher rate limits.")

                rpcSection
            }
            .padding()
        }
        .navigationTitle("API Keys")
        .onAppear { viewModel.load() }
        .onChange(of: viewModel.zapperAPIKey) { debounceSave() }
        .onChange(of: viewModel.debankAPIKey) { debounceSave() }
        .onChange(of: viewModel.coingeckoAPIKey) { debounceSave() }
        .onChange(of: viewModel.keychainError) { _, error in
            showError = error != nil
        }
        .alert("Keychain Error", isPresented: $showError) {
            Button("OK") { viewModel.keychainError = nil }
        } message: {
            Text(viewModel.keychainError ?? "")
        }
    }

    private func apiKeyField(
        _ title: String,
        text: Binding<String>,
        hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            TextField("Enter API key", text: text)
                .textFieldStyle(.roundedBorder)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rpcSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom RPCs")
                .font(.headline)

            ForEach(
                viewModel.rpcEndpoints.sorted(by: { $0.key.rawValue < $1.key.rawValue }),
                id: \.key) { chain, url in
                    HStack {
                        Text(chain.rawValue.capitalized)
                            .frame(width: 80, alignment: .leading)
                        Text(url)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeRPCEndpoint(chain: chain)
                            debounceSave()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

            if !availableChains.isEmpty {
                HStack {
                    Picker("Chain", selection: $newRPCChain) {
                        ForEach(availableChains, id: \.self) { chain in
                            Text(chain.rawValue.capitalized).tag(chain)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    TextField("RPC URL", text: $newRPCURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        guard !newRPCURL.isEmpty else { return }
                        viewModel.addRPCEndpoint(chain: newRPCChain, url: newRPCURL)
                        newRPCURL = ""
                        if let next = availableChains.first {
                            newRPCChain = next
                        }
                        debounceSave()
                    }
                    .disabled(newRPCURL.isEmpty)
                }
            }
        }
    }

    private var availableChains: [Chain] {
        Chain.allCases.filter { viewModel.rpcEndpoints[$0] == nil }
    }

    private func debounceSave() {
        guard !viewModel.isLoading else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            viewModel.save()
        }
    }
}
