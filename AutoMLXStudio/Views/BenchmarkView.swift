import SwiftUI

struct BenchmarkView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Benchmark")
                        .font(.largeTitle.bold())
                    Text("Measure real MLX inference performance on this Mac.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !appState.benchmarkResults.isEmpty {
                    Button("Clear Results") {
                        appState.benchmarkResults.removeAll()
                    }
                }

                Button("Run Benchmark") {
                    appState.runBenchmark()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.activeProcessDescription != nil)
            }

            if let latest = appState.benchmarkResults.first {
                HStack(spacing: 12) {
                    metric("Prompt", String(format: "%.1f tok/s", latest.promptTokensPerSecond))
                    metric("Generation", String(format: "%.1f tok/s", latest.generationTokensPerSecond))
                    metric("Peak RAM", String(format: "%.2f GB", latest.peakMemoryGB))
                }
            }

            if appState.benchmarkResults.isEmpty {
                ContentUnavailableView(
                    "No benchmark results",
                    systemImage: "speedometer",
                    description: Text("Run the first benchmark to establish a baseline.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(appState.benchmarkResults) {
                    TableColumn("Model") { result in
                        Text(result.model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn("Prompt tok/s") { result in
                        Text(String(format: "%.2f", result.promptTokensPerSecond))
                    }
                    TableColumn("Generation tok/s") { result in
                        Text(String(format: "%.2f", result.generationTokensPerSecond))
                    }
                    TableColumn("Peak RAM") { result in
                        Text(String(format: "%.2f GB", result.peakMemoryGB))
                    }
                    TableColumn("Date") { result in
                        Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .padding(24)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}
