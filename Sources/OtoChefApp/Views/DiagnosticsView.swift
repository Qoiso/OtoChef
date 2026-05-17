import SwiftUI

struct DiagnosticsView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("诊断")
                .font(.title)
                .fontWeight(.semibold)

            Button {
                store.validate()
            } label: {
                Label("运行预检", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)

            if store.validationErrors.isEmpty {
                Label("当前配置通过基础预检", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                ForEach(store.validationErrors) { error in
                    Label(error.message, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding(24)
    }
}
