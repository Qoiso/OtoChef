import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case audio = "音声"
    case video = "视频"
    case recentJobs = "最近任务"
    case settings = "设置"
    case diagnostics = "诊断"
    case logs = "日志"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .audio:
            return "waveform"
        case .video:
            return "arrow.down.circle"
        case .recentJobs:
            return "clock"
        case .settings:
            return "gearshape"
        case .diagnostics:
            return "stethoscope"
        case .logs:
            return "doc.text.magnifyingglass"
        }
    }
}

struct ContentView: View {
    @State private var store = JobStore()
    @SceneStorage("selectedSection") private var selectedSectionRawValue = AppSection.audio.rawValue

    private var selection: Binding<AppSection> {
        Binding {
            if selectedSectionRawValue == "新任务" {
                return .audio
            }
            return AppSection(rawValue: selectedSectionRawValue) ?? .audio
        } set: { newValue in
            selectedSectionRawValue = newValue.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
        } detail: {
            ZStack {
                EmbossedBackgroundView()

                selectedDetailView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: store.draft.settings) {
            store.saveSettings()
        }
    }

    @ViewBuilder
    private var selectedDetailView: some View {
        switch selection.wrappedValue {
        case .audio:
            NewJobView(store: store)
        case .video:
            VideoDownloadView(store: store)
        case .recentJobs:
            RecentJobsView(store: store)
        case .settings:
            SettingsView(settings: $store.draft.settings)
        case .diagnostics:
            DiagnosticsView(store: store)
        case .logs:
            LogsView(store: store)
        }
    }
}
