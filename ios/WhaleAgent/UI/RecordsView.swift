import SwiftUI

struct RecordsView: View {
    @ObservedObject var model: AppModel
    var onBackToChat: () -> Void = {}
    var showsClose: Bool = false
    var onClose: () -> Void = {}
    @State private var filter = "all"

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [OperationRecord]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredActions) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: grouped[day]?.sorted { $0.createdAt > $1.createdAt } ?? [])
        }
    }

    private var filteredActions: [OperationRecord] {
        switch filter {
        case "success":
            return model.recentActions.filter(\.isSuccess)
        case "review":
            return model.recentActions.filter { !$0.isSuccess }
        default:
            return model.recentActions
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty && model.taskRecords.isEmpty {
                        emptyState
                    } else {
                        summaryCard
                            .padding(.top, 14)
                        filterRow
                            .padding(.top, 12)
                        if !model.taskRecords.isEmpty {
                            taskSection
                        }
                        ForEach(groups) { group in
                            Text(label(for: group.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WhaleTheme.muted)
                                .padding(.top, 18)
                                .padding(.bottom, 10)
                            ForEach(group.items) { action in
                                OperationRecordCard(action: action)
                                    .padding(.bottom, 11)
                            }
                        }
                    }
                }
                .padding(.horizontal, WhaleTheme.pagePadding)
                .padding(.bottom, showsClose ? 26 : WhaleTabBar.height + 34)
            }
            .scrollIndicators(.hidden)
            .horizontalTabSwipe(
                onPrevious: { stepFilter(-1) },
                onNext: { stepFilter(1) }
            )
        }
    }

    private func stepFilter(_ delta: Int) {
        let keys = ["all", "success", "review"]
        guard let index = keys.firstIndex(of: filter) else { return }
        let next = min(max(index + delta, 0), keys.count - 1)
        guard next != index else { return }
        withAnimation(.snappy(duration: 0.22)) { filter = keys[next] }
    }

    private var recentWeekActions: [OperationRecord] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return model.recentActions.filter { $0.createdAt >= start }
    }

    private var summaryCard: some View {
        let actions = recentWeekActions
        let done = actions.filter(\.isSuccess).count
        let review = actions.count - done
        return HStack(spacing: 0) {
            summaryMetric("\(actions.count)", label: "最近 7 天", tint: WhaleTheme.ink)
            summaryDivider
            summaryMetric("\(done)", label: "已完成", tint: WhaleTheme.success)
            summaryDivider
            summaryMetric("\(review)", label: "待核对", tint: WhaleTheme.coral)
        }
        .whaleCard(padding: 16)
    }

    private func summaryMetric(_ value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WhaleTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(WhaleTheme.line)
            .frame(width: 0.5, height: 30)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            filterChip("all", title: "全部")
            filterChip("success", title: "已完成")
            filterChip("review", title: "待核对")
            Spacer(minLength: 0)
        }
    }

    private func filterChip(_ key: String, title: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { filter = key }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filter == key ? WhaleTheme.onAccent : WhaleTheme.muted)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    filter == key ? WhaleTheme.accent : WhaleTheme.soft.opacity(0.75),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近任务")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WhaleTheme.muted)
                .padding(.top, 18)
            ForEach(model.taskRecords.prefix(8)) { task in
                taskCard(task)
            }
        }
    }

    private func taskCard(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WhaleTheme.accent)
                Text(task.goal)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(2)
                Spacer()

            }
            HStack(spacing: 8) {
                Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if let reply = task.reply, !reply.isEmpty {
                    Text("·")
                    Text(reply)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(WhaleTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whaleCard(padding: 15)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("任务与记录")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(WhaleTheme.ink)
                Text("提醒、日程与地点操作的真实结果")
                    .font(.system(size: 12))
                    .foregroundStyle(WhaleTheme.muted)
            }
            Spacer()
            if showsClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .whaleGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭记录")
            } else {
                Button(action: onBackToChat) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(WhaleTheme.ink)
                        .whaleGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("回到对话")
            }
        }
        .padding(.horizontal, WhaleTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            WhaleIconTile(systemName: "clock", size: 68)
            Text("还没有记录")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(WhaleTheme.ink)
            Text("完成一次提醒、日程、地点或音乐操作后，结果会出现在这里。")
                .font(.system(size: 14))
                .foregroundStyle(WhaleTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 88)
        .padding(.horizontal, 24)
    }

    private func label(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day())
    }
}

struct OperationRecordCard: View {
    let action: OperationRecord
    var compact: Bool = false

    private var tint: Color { action.isSuccess ? WhaleTheme.accent : WhaleTheme.coral }

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill((action.isSuccess ? WhaleTheme.accentSoft : WhaleTheme.amberSoft))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: action.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WhaleTheme.ink)
                    .lineLimit(1)
                Text(action.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(WhaleTheme.muted)
            }

            Spacer(minLength: 6)

            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(WhaleTheme.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WhaleTheme.glassStroke, lineWidth: 0.7)
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill((action.isSuccess ? WhaleTheme.accentSoft : WhaleTheme.amberSoft))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WhaleTheme.ink)
                        .lineLimit(3)
                    Text(action.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(WhaleTheme.muted)
                }

                Spacer(minLength: 6)

                Text(action.isSuccess ? "已完成" : "待核对")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12), in: Capsule())
            }

            if !action.detail.isEmpty {
                Text(action.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(WhaleTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whaleCard(padding: 15)
    }
}
