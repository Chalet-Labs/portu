import PortuCore
import SwiftUI

struct APIKeysSettingsTab: View {
    @State private var viewModel = APIKeysViewModel()
    @State private var newRPCChain: Chain = .ethereum
    @State private var newRPCURL = ""

    var body: some View {
        Form {
            Section("Zapper") {
                TextField("API Key", text: $viewModel.zapperAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Section("DeBank") {
                TextField("API Key", text: $viewModel.debankAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                TextField("API Key", text: $viewModel.coingeckoAPIKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("CoinGecko")
            } footer: {
                Text("Optional. Provides higher rate limits.")
                    .foregroundStyle(.secondary)
            }

            Section("Custom RPCs") {
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
                                viewModel.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

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
                        viewModel.save()
                        newRPCURL = ""
                    }
                    .disabled(newRPCURL.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("API Keys")
        .onAppear { viewModel.load() }
        .onChange(of: viewModel.zapperAPIKey) { viewModel.save() }
        .onChange(of: viewModel.debankAPIKey) { viewModel.save() }
        .onChange(of: viewModel.coingeckoAPIKey) { viewModel.save() }
    }

    private var availableChains: [Chain] {
        Chain.allCases.filter { viewModel.rpcEndpoints[$0] == nil }
    }
}
