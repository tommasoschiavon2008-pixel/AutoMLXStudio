import SwiftUI

struct OptimizeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Dynamic Quantization")
                    .font(.largeTitle.bold())
                Text("Analyze layer sensitivity and create a mixed-precision MLX model tuned to a selected operating profile.")
                    .foregroundStyle(.secondary)
            }

            Section("Source model") {
                TextField("Hugging Face model or local path", text: $appState.modelIdentifier)
                    .textFieldStyle(.roundedBorder)
                Text("For learned quantization, use an unquantized or higher-precision source model when possible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Optimization profile") {
                Picker("Profile", selection: $appState.optimizationProfile) {
                    ForEach(OptimizationProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Target BPW", value: String(format: "%.2f", appState.optimizationProfile.targetBPW))
                LabeledContent("Low precision", value: "\(appState.optimizationProfile.lowBits)-bit")
                LabeledContent("High precision", value: "\(appState.optimizationProfile.highBits)-bit")
            }

            Section("Memory goal") {
                Slider(value: $appState.targetMemoryGB, in: 4...max(4, appState.hardware.memoryGB), step: 0.5) {
                    Text("Target memory")
                }
                LabeledContent("Target", value: String(format: "%.1f GB", appState.targetMemoryGB))
                Text("V1 records this hardware target for the workflow. Automatic iterative BPW selection from measured RAM is planned for V2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                TextField("Output base path", text: $appState.outputModelPath)
                    .textFieldStyle(.roundedBorder)

                Button {
                    appState.runDynamicQuantization()
                } label: {
                    Label("Run Dynamic Quantization", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.activeProcessDescription != nil)
            }
        }
        .formStyle(.grouped)
    }
}
