import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Dashboard")
                        .font(.largeTitle.bold())
                    Text("Local MLX runtime, hardware profile and model performance.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    metricCard("Chip", appState.hardware.chip, "cpu")
                    metricCard("Unified Memory", String(format: "%.0f GB", appState.hardware.memoryGB), "memorychip")
                    metricCard("Architecture", appState.hardware.architecture, "apple.logo")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Current model")
                                    .font(.headline)
                                Text(appState.modelIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button(appState.serverRunning ? "Stop Server" : "Start Server") {
                                    appState.serverRunning ? appState.stopServer() : appState.startServer()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Benchmark") {
                                    appState.runBenchmark()
                                }

                                Button("Optimize") {
                                    appState.selection = .optimize
                                }
                            }
                        }

                        Divider()

                        HStack(spacing: 18) {
                            Label(
                                appState.serverRunning ? "Server running" : "Server offline",
                                systemImage: appState.serverRunning ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(appState.serverRunning ? .green : .secondary)

                            Label("Port \(appState.serverPort)", systemImage: "network")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .padding(8)
                }

                GroupBox("Engine log") {
                    ScrollView {
                        Text(appState.logText.isEmpty ? "No log output yet." : appState.logText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(minHeight: 210, idealHeight: 280)
                }
            }
            .padding(24)
        }
    }

    private func metricCard(_ title: String, _ value: String, _ symbol: String) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value.isEmpty ? "Unknown" : value)
                        .font(.headline)
                        .lineLimit(2)

                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(6)
        }
    }
}
