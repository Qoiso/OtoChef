import SwiftUI

struct RecentJobsView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近任务")
                .font(.title)
                .fontWeight(.semibold)

            if store.recentJobs.isEmpty {
                ContentUnavailableView("暂无最近任务", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.recentJobs) { job in
                    JobProgressRow(job: job)
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
    }
}
