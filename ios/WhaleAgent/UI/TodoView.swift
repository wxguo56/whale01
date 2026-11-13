import SwiftUI
import UIKit

struct TodoReminder: Identifiable, Equatable {
    let id: String
    let title: String
    let completed: Bool
    let listName: String
    let dueAt: Date?
    let notes: String?
    let deduplicated: Bool

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              let id = object.optionalString("recordId"),
              let title = object.optionalString("title"),
              !title.isEmpty else { return nil }
        self.id = id
        self.title = title
        self.completed = object.optionalBool("completed") ?? false
        self.listName = object.optionalString("listName") ?? "提醒事项"
        self.dueAt = object.optionalString("dueAt").flatMap(ToolDate.parse)
        self.notes = object.optionalString("notes")
        self.deduplicated = object.optionalBool("deduplicated") ?? false
    }
}

private enum TodoFilter: String, CaseIterable, Identifiable {
    case pending
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待办"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        }
    }
}

private enum TodoQuickCommand {
    case complete(String)
    case restore(String)
    case delete(String)

    static func parse(_ raw: String) -> TodoQuickCommand? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["帮我", "请", "我要"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !text.isEmpty else { return nil }

        let actions: [(String, (String) -> TodoQuickCommand)] = [
            ("标记完成", TodoQuickCommand.complete),
            ("取消完成", TodoQuickCommand.restore),
            ("已完成", TodoQuickCommand.complete),
            ("完成", TodoQuickCommand.complete),
            ("勾掉", TodoQuickCommand.complete),
            ("恢复", TodoQuickCommand.restore),
            ("删除", TodoQuickCommand.delete),
            ("删掉", TodoQuickCommand.delete),
            ("移除", TodoQuickCommand.delete)
        ]

        for (prefix, make) in actions where text.hasPrefix(prefix) {
            var rest = String(text.dropFirst(prefix.count))
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,\n"))
            if !rest.isEmpty { return make(rest) }
        }

        for suffix in ["完成了", "做完了", "已完成", "搞定了"] where text.hasSuffix(suffix) {
            let rest = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return .complete(rest) }
        }

        return nil
    }
}

struct TodoView: View {
    @ObservedObject var model: AppModel
    var embedded: Bool = false
    var onBackToChat: (() -> Void)? = nil
    var bottomBarInset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VoiceInputController()

    @State private var filter: TodoFilter = .pending
    @State private var items: [TodoReminder] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var busyIds: Set<String> = []
    @State private var errorText: String?
    @State private var toast: String?
    @State private var undoAction: TodoUndo?
    @State private var undoExpiresAt = Date.distantPast
    @State private var showTimeEditor = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let drafts = ComposerDraftStore()
    @State private var pendingDeletion: TodoReminder?
    @FocusState private var composerFocused: Bool

    private var reminderStatus: String { model.permissionsSnapshot["reminder"] ?? "unknown" }
    private var pendingItems: [TodoReminder] { items.filter { !$0.completed } }
    private var inProgressItems: [TodoReminder] {
        let start = Calendar.current.startOfDay(for: Date())
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return items.filter { item in
            guard !item.completed, let due = item.dueAt else { return false }
            return due < endOfToday
        }
    }
    private var completedItems: [TodoReminder] { items.filter(\.completed) }
    private var visibleItems: [TodoReminder] {
        switch filter {
        case .pending: return pendingItems
        case .inProgress: return inProgressItems
        case .completed: return completedItems
        }
    }

    var body: some View {
        if embedded {
            page
        } else {
            NavigationStack {
                page
            }
        }
    }

    private var page: some View {
        ZStack(alignment: .top) {
                WhaleBackdrop().ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                                .id("todo-top")
                            if reminderStatus != "granted" { permissionCard }
                            statsCard
                            filterBar
                            content
                            if let errorText { errorBanner(errorText) }
                            hint
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await reload() }
                    .onTapGesture { composerFocused = false }
                    .horizontalTabSwipe(
                        onPrevious: { stepFilter(-1) },
                        onNext: { stepFilter(1) }
                    )
                    .onChange(of: filter) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("todo-top", anchor: .top) }
                    }
                }

                if let toast {
                    HStack(spacing: 12) {
                        Text(toast).font(.subheadline).foregroundStyle(WhaleTheme.ink)
                        if undoAction != nil {
                            Button("撤销") { undoLastChange() }.font(.subheadline.weight(.semibold)).whaleTouchTarget()
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 4)
                        .background(WhaleTheme.card, in: Capsule()).overlay(Capsule().stroke(WhaleTheme.line))
                        .padding(.top, 8)
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer.padding(.bottom, embedded ? bottomBarInset : 0)
            }
            .navigationBarHidden(true)
            .task { draft = drafts.load(context: "todo"); await reload() }
            .onChange(of: draft) { _, text in drafts.save(text, context: "todo") }
            .sheet(isPresented: $showTimeEditor) {
                TodoTimeEditor(original: draft) { title, due in
                    let item = try await model.createTodoReminder(title: title, dueAt: due)
                    draft = ""; upsert(item); undoAction = item.deduplicated ? nil : .added(item)
                    showToast(item.deduplicated ? "已有相同提醒" : "已添加 · " + title, undo: !item.deduplicated)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await reload() }
                }
            }
            .onChange(of: voice.transcript) { _, text in
                if !text.isEmpty { draft = text }
            }
            .onChange(of: voice.finalResult) { _, result in
                guard let result, voice.errorText == nil, !result.text.isEmpty else { return }
                draft = result.text
            }
            .onDisappear { voice.cancel() }
            .alert("删除这条待办？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
                Button("取消", role: .cancel) { pendingDeletion = nil }
                Button("删除", role: .destructive) {
                    if let item = pendingDeletion { performDelete(item) }
                    pendingDeletion = nil
                }
            } message: {
                Text(pendingDeletion?.title ?? "")
            }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WhaleIconTile(systemName: "checklist", size: 46, tint: WhaleTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("待办")
                    .whaleFont(size: 24, weight: .bold, design: .rounded)
                    .foregroundStyle(WhaleTheme.ink)
                Text("新增、完成，随手就能记好")
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer(minLength: 8)
            Button {
                if embedded { onBackToChat?() } else { dismiss() }
            } label: {
                Image(systemName: embedded ? "bubble.left.and.bubble.right" : "xmark")
                    .font(.system(size: embedded ? 15 : 14, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .whaleGlassCircle(size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(embedded ? "回到对话" : "关闭待办")
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要提醒事项权限", systemImage: "checklist")
                .whaleFont(size: 15, weight: .semibold)
                .foregroundStyle(WhaleTheme.ink)

            Text(reminderStatus == "denied"
                 ? "权限已被拒绝。请到 设置 › 隐私与安全性 › 提醒事项 中允许鲸鱼访问；返回后会自动刷新。"
                 : "允许后，这里会直接显示手机里真实的提醒事项，新增和勾选也会写回系统。")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if reminderStatus == "denied" {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } else {
                    Task {
                        await model.requestPermission("reminder")
                        await reload()
                    }
                }
            } label: {
                Text(reminderStatus == "denied" ? "打开系统设置" : "允许访问提醒事项")
                    .whaleFont(size: 14, weight: .semibold)
                    .foregroundStyle(WhaleTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(WhaleTheme.auroraGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .whaleCard(padding: 16)
    }

    private func stepFilter(_ delta: Int) {
        let all = TodoFilter.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        let next = min(max(index + delta, 0), all.count - 1)
        guard next != index else { return }
        composerFocused = false
        withAnimation(.easeInOut(duration: 0.18)) { filter = all[next] }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton(.pending, count: pendingItems.count)
            filterButton(.inProgress, count: inProgressItems.count)
            filterButton(.completed, count: completedItems.count)
            Spacer(minLength: 0)
        }
    }

    private var statsCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 0) {
                statMetric(.pending, count: pendingItems.count, label: "待办事项", tint: WhaleTheme.ink)
                statDivider
                statMetric(.inProgress, count: inProgressItems.count, label: "进行中", tint: WhaleTheme.coral)
                statDivider
                statMetric(.completed, count: completedItems.count, label: "已完成", tint: WhaleTheme.success)
            }
            Text("进行中 = 今天到期或已逾期；待办 = 全部未完成")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 8)
        .background(WhaleTheme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
        }
    }

    private func statMetric(_ value: TodoFilter, count: Int, label: String, tint: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = value }
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .whaleFont(size: 23, weight: .bold, design: .rounded)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(label)
                    .whaleFont(size: 13, weight: .medium)
                    .foregroundStyle(WhaleTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filter == value ? tint.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(count) 条")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(WhaleTheme.line.opacity(0.55))
            .frame(width: 0.6, height: 34)
    }

    private func filterButton(_ value: TodoFilter, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = value }
        } label: {
            HStack(spacing: 6) {
                Text(value.title)
                Text("\(count)")
                    .whaleFont(size: 13, weight: .bold, design: .rounded)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((filter == value ? WhaleTheme.onAccent : WhaleTheme.muted).opacity(0.12), in: Capsule())
            }
            .whaleFont(size: 13, weight: .semibold)
            .foregroundStyle(filter == value ? WhaleTheme.onAccent : WhaleTheme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if filter == value {
                    Capsule().fill(WhaleTheme.auroraGradient)
                } else {
                    Capsule().fill(WhaleTheme.card.opacity(0.8))
                }
            }
            .overlay(Capsule().strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            HStack(spacing: 9) {
                ProgressView().scaleEffect(0.8)
                Text("正在读取提醒事项…")
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if visibleItems.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 9) {
                ForEach(visibleItems) { item in
                    row(item)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyIcon)
                .whaleFont(size: 28, weight: .light)
                .foregroundStyle(WhaleTheme.muted.opacity(0.7))
            Text(emptyTitle)
                .whaleFont(size: 15, weight: .semibold)
                .foregroundStyle(WhaleTheme.ink)
            Text(emptyHint)
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var emptyIcon: String {
        switch filter {
        case .pending: return "checkmark.circle"
        case .inProgress: return "clock.badge.checkmark"
        case .completed: return "archivebox"
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .pending: return "还没有待办"
        case .inProgress: return "没有进行中的事项"
        case .completed: return "还没有已完成事项"
        }
    }

    private var emptyHint: String {
        switch filter {
        case .pending: return "在下面写一句，直接加到系统提醒事项。"
        case .inProgress: return "今天到期或已逾期的未完成事项会出现在这里。"
        case .completed: return "勾掉的事会出现在这里，可以再恢复。"
        }
    }

    private func row(_ item: TodoReminder) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Button { toggle(item) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.completed ? WhaleTheme.success : WhaleTheme.line, lineWidth: 1.6)
                        .background(Circle().fill(item.completed ? WhaleTheme.success.opacity(0.14) : Color.clear))
                        .frame(width: 27, height: 27)
                    if busyIds.contains(item.id) {
                        ProgressView().scaleEffect(0.55)
                    } else if item.completed {
                        Image(systemName: "checkmark")
                            .whaleFont(size: 13, weight: .bold)
                            .foregroundStyle(WhaleTheme.success)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busyIds.contains(item.id))
            .accessibilityLabel(item.completed ? "恢复 \(item.title)" : "完成 \(item.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .whaleFont(size: 14, weight: .medium)
                    .foregroundStyle(item.completed ? WhaleTheme.muted : WhaleTheme.ink)
                    .strikethrough(item.completed, color: WhaleTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    if let due = item.dueAt {
                        Label(dueText(due), systemImage: "clock")
                            .whaleFont(size: 13, weight: .medium)
                            .foregroundStyle(dueColor(item, due))
                    } else {
                        Text("无日期")
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted.opacity(0.75))
                    }
                    Text(item.listName)
                        .whaleFont(size: 13, weight: .medium)
                        .foregroundStyle(WhaleTheme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WhaleTheme.soft, in: Capsule())
                    if let notes = item.notes, !notes.isEmpty {
                        Image(systemName: "note.text")
                            .whaleFont(size: 13)
                            .foregroundStyle(WhaleTheme.muted.opacity(0.7))
                            .accessibilityLabel("有备注")
                    }
                }
            }

            Spacer(minLength: 4)

            Menu {
                if item.completed {
                    Button("恢复为待办", systemImage: "arrow.uturn.backward") { toggle(item) }
                } else {
                    Button("标记完成", systemImage: "checkmark.circle") { toggle(item) }
                }
                Button("删除待办", systemImage: "trash", role: .destructive) { delete(item) }
            } label: {
                Image(systemName: "ellipsis")
                    .whaleFont(size: 14, weight: .semibold)
                    .foregroundStyle(WhaleTheme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WhaleTheme.card.opacity(item.completed ? 0.55 : 0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
        )
        .contextMenu {
            Button("删除待办", systemImage: "trash", role: .destructive) { delete(item) }
        }
    }

    private var hint: some View {
        Text("直接写内容新增，或点麦克风说一句；输入「完成 买菜」勾掉，「删除 买菜」移除。")
            .whaleFont(size: 13)
            .foregroundStyle(WhaleTheme.muted.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(WhaleTheme.warm)
            if message.contains("提醒时间") {
                Button("补充具体时间") { showTimeEditor = true }.font(.body).whaleTouchTarget()
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(WhaleTheme.soft, in: RoundedRectangle(cornerRadius: 14))
    }

    private var composer: some View {
        VStack(spacing: 7) {
            if let voiceError = voice.errorText {
                Label(voiceError, systemImage: "mic.slash.fill")
                    .whaleFont(size: 13)
                    .foregroundStyle(WhaleTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if voice.isRecording {
                voiceStrip
            }
            HStack(spacing: 8) {
                Button {
                    composerFocused = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "waveform" : "mic.fill")
                        .whaleFont(size: 17, weight: .semibold)
                        .foregroundStyle(voice.isRecording ? WhaleTheme.onAccent : WhaleTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(
                            voice.isRecording ? WhaleTheme.danger : WhaleTheme.accentSoft,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || voice.isFinalizing)
                .accessibilityLabel(voice.isRecording ? "停止语音输入" : "语音新增待办")

                TextField("记一件事，或点击麦克风", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .whaleFont(size: 14)
                    .focused($composerFocused)
                    .submitLabel(.return)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button { submitDraft() } label: {
                    ZStack {
                        Circle()
                            .fill(WhaleTheme.auroraGradient)
                            .frame(width: 44, height: 44)
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(WhaleTheme.onAccent)
                        } else {
                            Image(systemName: "arrow.up")
                                .whaleFont(size: 14, weight: .bold)
                                .foregroundStyle(WhaleTheme.onAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("提交待办")
            }
            .padding(.leading, 13)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(WhaleTheme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.8)
            )

            Text("点击提交后保存；语音识别后可先检查内容")
                .whaleFont(size: 13)
                .foregroundStyle(WhaleTheme.muted.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var voiceStrip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(WhaleTheme.danger)
                .frame(width: 8, height: 8)
            Text(voice.transcript.isEmpty ? "正在听你说…" : voice.transcript)
                .whaleFont(size: 13, weight: .medium)
                .foregroundStyle(WhaleTheme.ink)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button {
                voice.stop()
            } label: {
                Text("停止")
                    .whaleFont(size: 13, weight: .semibold)
                    .foregroundStyle(WhaleTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WhaleTheme.danger.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(WhaleTheme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(WhaleTheme.danger.opacity(0.22), lineWidth: 0.8)
        )
    }

    private func submitDraft() {
        submitText(draft)
    }

    private func submitText(_ text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isSubmitting else { return }
        errorText = nil
        undoAction = nil
        isSubmitting = true

        Task {
            do {
                if let command = TodoQuickCommand.parse(raw) {
                    let message = try await run(command)
                    draft = ""
                    await reload(silent: true)
                    showToast(message, undo: undoAction != nil)
                } else {
                    let parsed = TodoQuickParser.parseAdd(raw)
                    if let message = parsed.validationError {
                        throw ToolExecutionError(code: "needs_clarification", message: message)
                    }
                    let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else {
                        throw ToolExecutionError(code: "empty_reminder", message: "写点具体内容再添加。")
                    }
                    let item = try await model.createTodoReminder(title: title, dueAt: parsed.dueAt)
                    draft = ""
                    filter = .pending
                    upsert(item)
                    undoAction = item.deduplicated ? nil : .added(item)
                    await reload(silent: true)
                    if let dueAt = parsed.dueAt {
                        showToast(item.deduplicated ? "已有相同提醒" : "已添加 · \(dueText(dueAt))", undo: !item.deduplicated)
                    } else {
                        showToast(item.deduplicated ? "已有相同提醒" : "已添加 · \(item.title)", undo: !item.deduplicated)
                    }
                }
            } catch {
                errorText = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func run(_ command: TodoQuickCommand) async throws -> String {
        switch command {
        case .complete(let keyword):
            let target = try uniqueMatch(keyword, in: pendingItems, missing: "没有找到未完成的「\(keyword)」。")
            let updated = try await model.setTodoReminder(target, completed: true)
            upsert(updated)
            undoAction = .completion(before: target, after: updated)
            return "已完成 · \(target.title)"
        case .restore(let keyword):
            let target = try uniqueMatch(keyword, in: completedItems, missing: "没有找到已完成的「\(keyword)」。")
            let updated = try await model.setTodoReminder(target, completed: false)
            upsert(updated)
            undoAction = .completion(before: target, after: updated)
            return "已恢复 · \(target.title)"
        case .delete(let keyword):
            let target = try uniqueMatch(keyword, in: items, missing: "没有找到「\(keyword)」。")
            pendingDeletion = target
            return "请核对要删除的待办"
        }
    }

    private func uniqueMatch(_ keyword: String, in source: [TodoReminder], missing: String) throws -> TodoReminder {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = source.filter { $0.title.caseInsensitiveCompare(key) == .orderedSame }
        let matches = exact.isEmpty ? source.filter { $0.title.localizedCaseInsensitiveContains(key) } : exact
        if matches.isEmpty { throw ToolExecutionError(code: "reminder_not_found", message: missing) }
        if matches.count > 1 {
            let names = matches.prefix(3).map(\.title).joined(separator: "、")
            throw ToolExecutionError(
                code: "ambiguous_reminder",
                message: "有 \(matches.count) 条匹配「\(key)」：\(names)。请写更完整的标题。"
            )
        }
        return matches[0]
    }

    private func toggle(_ item: TodoReminder) {
        guard !busyIds.contains(item.id) else { return }
        busyIds.insert(item.id)
        errorText = nil
        Task {
            do {
                let updated = try await model.setTodoReminder(item, completed: !item.completed)
                upsert(updated)
                undoAction = .completion(before: item, after: updated)
                await reload(silent: true)
                showToast(item.completed ? "已恢复 · \(item.title)" : "已完成 · \(item.title)", undo: true)
            } catch {
                errorText = error.localizedDescription
            }
            busyIds.remove(item.id)
        }
    }

    private func delete(_ item: TodoReminder) {
        pendingDeletion = item
    }

    private func performDelete(_ item: TodoReminder) {
        guard !busyIds.contains(item.id) else { return }
        busyIds.insert(item.id)
        errorText = nil
        Task {
            do {
                try await model.deleteTodoReminder(item)
                removeLocal(item.id)
                await reload(silent: true)
                showToast("已删除 · \(item.title)")
            } catch {
                errorText = error.localizedDescription
            }
            busyIds.remove(item.id)
        }
    }

    private func reload(silent: Bool = false) async {
        guard !isLoading else { return }
        model.refreshPermissions()
        guard reminderStatus == "granted" else { items = []; return }
        isLoading = true
        if !silent { errorText = nil }
        defer { isLoading = false }
        do {
            items = try await model.loadTodoReminders(includeCompleted: true)
            model.refreshPermissions()
        } catch {
            let permissionDenied = (error as? ToolExecutionError)?.code == "permission_denied"
            if !permissionDenied || items.isEmpty {
                errorText = error.localizedDescription
            }
            model.refreshPermissions()
        }
    }

    private func upsert(_ item: TodoReminder) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        items.sort { left, right in
            if left.completed != right.completed { return !left.completed }
            switch (left.dueAt, right.dueAt) {
            case let (leftDate?, rightDate?): return leftDate < rightDate
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        }
    }

    private func removeLocal(_ id: String) {
        items.removeAll { $0.id == id }
    }

    private func showToast(_ text: String, undo: Bool = false) {
        toast = text
        if !undo { undoAction = nil }
        undoExpiresAt = Date().addingTimeInterval(8)
        let expires = undoExpiresAt
        Task {
            try? await Task.sleep(nanoseconds: undo ? 8_000_000_000 : 3_000_000_000)
            if undoExpiresAt == expires { toast = nil; undoAction = nil }
        }
    }

    private func undoLastChange() {
        guard let action = undoAction, !isSubmitting else { return }
        let pressedAt = Date()
        let expiry = undoExpiresAt
        guard pressedAt <= expiry else { undoAction = nil; return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let latest = try await model.loadTodoReminders(includeCompleted: true)
                let current = latest.first { $0.id == action.expected.id }
                guard action.canUndo(current: current, now: pressedAt, expiresAt: expiry) else {
                    throw ToolExecutionError(code: "undo_changed", message: "事项已变化或撤销时间已过，请到待办里核对。")
                }
                switch action {
                case .added(let item): try await model.deleteTodoReminder(item); removeLocal(item.id)
                case .completion(let before, let after): let restored = try await model.setTodoReminder(after, completed: before.completed); upsert(restored)
                }
                showToast("已撤销本次修改")
                await reload(silent: true)
            } catch { errorText = error.localizedDescription }
        }
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInTomorrow(date) { return "明天 \(time)" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func dueColor(_ item: TodoReminder, _ date: Date) -> Color {
        if item.completed { return WhaleTheme.muted }
        if date < Date() { return WhaleTheme.danger }
        if Calendar.current.isDateInToday(date) { return WhaleTheme.coral }
        return WhaleTheme.moon
    }
}
