import SwiftUI

struct QuickActionEditor: View {
    @Binding var actions: [QuickAction]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("首页固定两到三个常用操作") {
                    ForEach(QuickAction.allCases) { action in
                        Button {
                            if actions.contains(action) {
                                if actions.count > 2 { actions.removeAll { $0 == action } }
                            } else if actions.count < 3 { actions.append(action) }
                            InteractionPreferences.setQuickActions(actions)
                        } label: {
                            HStack {
                                Label(action.title, systemImage: action.icon)
                                Spacer()
                                if actions.contains(action) { Image(systemName: "checkmark").foregroundStyle(WhaleTheme.accent) }
                            }.foregroundStyle(WhaleTheme.ink).frame(minHeight: 44)
                        }
                    }
                }
                Section("已选顺序") {
                    ForEach(actions) { action in Label(action.title, systemImage: action.icon) }
                        .onMove { offsets, target in actions.move(fromOffsets: offsets, toOffset: target); InteractionPreferences.setQuickActions(actions) }
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("常用操作").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

extension Notification.Name {
    static let whalePrefillDraft = Notification.Name("whale.composer.prefill")
}
