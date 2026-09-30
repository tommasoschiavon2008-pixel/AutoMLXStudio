import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $appState.selection) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
                    .padding(.vertical, 3)
                    .accessibilityLabel(item.rawValue) // Gives every sidebar destination, including Benchmark, an explicit stable assistive label.
            }
            .navigationTitle("AutoMLX Studio")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                StatusBar()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selection ?? .dashboard {
        case .dashboard:
            DashboardView()
        case .chat:
            ChatView()
        case .projects: // Routes the third sidebar destination to local project and Project Memory management.
            ProjectsView() // Opens project and document management between Chat and agent orchestration.
        case .agents:
            AgentsView() // Shows the centralized agent registry and the latest real workflow trace.
        case .models:
            ModelsView() // Shows installed physical models, assignments, and the single-server runtime.
        case .remoteModels: // Supports sidebar selection and Engineering's configuration link.
            RemoteModelsView(controller: appState.remoteModelsController) // Reuses the app-owned server state across navigation.
        case .engineering: // Opens the existing native Engineering surface.
            EngineeringView(controller: appState.engineeringController, remoteController: appState.remoteModelsController) // Reuses both app-owned controllers without recreating an active session.
        case .optimize:
            OptimizeView()
        case .benchmark:
            BenchmarkView(controller: appState.benchmarkController) // Reuses the app-owned evaluation state across sidebar navigation.
        case .settings:
            SettingsView()
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(appState.statusText)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let work = appState.activeProcessDescription {
                ProgressView()
                    .controlSize(.small)
                Text(work)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if appState.serverRunning {
                Label("Port \(appState.serverPort)", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.bar)
    }

    private var statusColor: Color {
        if appState.serverRunning { return .green }
        if appState.statusText.localizedCaseInsensitiveContains("error")
            || appState.statusText.localizedCaseInsensitiveContains("failed")
            || appState.statusText.localizedCaseInsensitiveContains("use") {
            return .orange
        }
        return .secondary
    }
}
