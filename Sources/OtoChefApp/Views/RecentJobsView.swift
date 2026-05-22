import AppKit
import SwiftUI

struct RecentJobsView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近任务")
                .font(.title)
                .fontWeight(.semibold)

            if store.completedRecentJobs.isEmpty {
                ContentUnavailableView("暂无已完成任务", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.completedRecentJobs) { job in
                    JobProgressRow(
                        job: job,
                        onOpenOutputDirectory: {
                            NSWorkspace.shared.open(URL(fileURLWithPath: job.outputDirectory, isDirectory: true))
                        },
                        onClear: {
                            store.clearCompletedRecentJob(id: job.id)
                        }
                    )
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
    }
}
