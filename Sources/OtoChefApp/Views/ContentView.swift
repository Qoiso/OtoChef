import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case newJob = "新任务"
    case recentJobs = "最近任务"
    case settings = "设置"
    case diagnostics = "诊断"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .newJob:
            return "plus.circle"
        case .recentJobs:
            return "clock"
        case .settings:
            return "gearshape"
        case .diagnostics:
            return "stethoscope"
        }
    }
}

struct ContentView: View {
    @State private var store = JobStore()
    @SceneStorage("selectedSection") private var selectedSectionRawValue = AppSection.newJob.rawValue

    private var selection: Binding<AppSection> {
        Binding {
            AppSection(rawValue: selectedSectionRawValue) ?? .newJob
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
            switch selection.wrappedValue {
            case .newJob:
                NewJobView(store: store)
            case .recentJobs:
                RecentJobsView(store: store)
            case .settings:
                SettingsView(settings: $store.draft.settings)
            case .diagnostics:
                DiagnosticsView(store: store)
            }
        }
        .onChange(of: store.draft.settings) {
            store.saveSettings()
        }
    }
}
