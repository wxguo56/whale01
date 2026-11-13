import SwiftUI

struct TodoTimeEditor: View {
    let original: String
    let onAdd: (String, Date) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var due = Date().addingTimeInterval(3600)
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("待办内容") { TextField("内容", text: $title, axis: .vertical).lineLimit(1...4) }
                Section("由你选择具体时间") {
                    DatePicker("提醒时间", selection: $due, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Text("请核对日期、时间和内容，点击添加后才会保存。")
                        .font(.subheadline).foregroundStyle(WhaleTheme.muted)
                }
                if let error { Text(error).foregroundStyle(WhaleTheme.danger) }
                Button {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await onAdd(title.trimmingCharacters(in: .whitespacesAndNewlines), due); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { if saving { ProgressView() } else { Text("添加提醒") } }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle("补充提醒时间").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) } }
        }.onAppear { title = original }
    }
}
